import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'notification_service.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _verificationId;
  
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isPremium => _currentUser?.isPremium ?? false;
  bool get canUploadProducts => _currentUser?.canUploadProducts ?? false;
  
  // Initialize service
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _loadUserData(user.uid);
      }
    } catch (e) {
      debugPrint('Error initializing auth service: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Register with email and password
  Future<bool> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required LocationData location,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (credential.user != null) {
        final userData = UserModel(
          id: credential.user!.uid,
          email: email,
          phoneNumber: phoneNumber,
          fullName: fullName,
          location: location,
          lastUploadDate: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        await _firestore
            .collection(AppConfig.usersCollection)
            .doc(credential.user!.uid)
            .set(userData.toMap());
        
        _currentUser = userData;
        await _saveUserToPreferences(userData);
        
        // Send welcome notification
        await _notificationService.sendWelcomeNotification(userData);
        
        notifyListeners();
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error registering user: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Login with email and password
  Future<bool> loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (credential.user != null) {
        await _loadUserData(credential.user!.uid);
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error signing in: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Send OTP to phone number
  Future<bool> sendOTP(String phoneNumber) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('OTP verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
      
      return true;
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Verify OTP
  Future<bool> verifyOTP(String smsCode) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      if (_verificationId == null) return false;
      
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      
      final userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user != null) {
        await _loadUserData(userCredential.user!.uid);
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Update user premium status
  Future<bool> updateUserPremiumStatus({
    required String userId,
    required UserType userType,
    required DateTime expiryDate,
  }) async {
    try {
      final updatedUser = _currentUser?.copyWith(
        userType: userType,
        premiumExpiryDate: expiryDate,
        updatedAt: DateTime.now(),
      );
      
      if (updatedUser != null) {
        await _firestore
            .collection(AppConfig.usersCollection)
            .doc(userId)
            .update(updatedUser.toMap());
        
        _currentUser = updatedUser;
        await _saveUserToPreferences(updatedUser);
        notifyListeners();
        
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error updating premium status: $e');
      return false;
    }
  }
  
  // Update daily product upload count
  Future<bool> updateDailyProductCount() async {
    try {
      if (_currentUser == null) return false;
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastUpload = DateTime(
        _currentUser!.lastUploadDate.year,
        _currentUser!.lastUploadDate.month,
        _currentUser!.lastUploadDate.day,
      );
      
      int newCount = 1;
      if (today.isAtSameMomentAs(lastUpload)) {
        newCount = _currentUser!.dailyProductsUploaded + 1;
      }
      
      final updatedUser = _currentUser!.copyWith(
        dailyProductsUploaded: newCount,
        lastUploadDate: now,
        updatedAt: now,
      );
      
      await _firestore
          .collection(AppConfig.usersCollection)
          .doc(_currentUser!.id)
          .update(updatedUser.toMap());
      
      _currentUser = updatedUser;
      await _saveUserToPreferences(updatedUser);
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('Error updating daily product count: $e');
      return false;
    }
  }
  
  // Check if user can upload products today
  bool canUploadToday() {
    if (_currentUser == null || !_currentUser!.canUploadProducts) {
      return false;
    }
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastUpload = DateTime(
      _currentUser!.lastUploadDate.year,
      _currentUser!.lastUploadDate.month,
      _currentUser!.lastUploadDate.day,
    );
    
    if (!today.isAtSameMomentAs(lastUpload)) {
      return true; // New day, reset count
    }
    
    return _currentUser!.dailyProductsUploaded < _currentUser!.maxDailyUploads;
  }
  
  // Reset password
  Future<bool> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      debugPrint('Error resetting password: $e');
      return false;
    }
  }
  
  // Update user profile
  Future<bool> updateProfile({
    required String fullName,
    required String phoneNumber,
    LocationData? location,
  }) async {
    try {
      if (_currentUser == null) return false;
      
      final updatedUser = _currentUser!.copyWith(
        fullName: fullName,
        phoneNumber: phoneNumber,
        location: location ?? _currentUser!.location,
        updatedAt: DateTime.now(),
      );
      
      await _firestore
          .collection(AppConfig.usersCollection)
          .doc(_currentUser!.id)
          .update(updatedUser.toMap());
      
      _currentUser = updatedUser;
      await _saveUserToPreferences(updatedUser);
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return false;
    }
  }
  
  // Logout
  Future<void> logout() async {
    try {
      await _auth.signOut();
      _currentUser = null;
      await _clearUserFromPreferences();
      notifyListeners();
    } catch (e) {
      debugPrint('Error logging out: $e');
    }
  }
  
  // Load user data from Firestore
  Future<void> _loadUserData(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConfig.usersCollection)
          .doc(userId)
          .get();
      
      if (doc.exists) {
        _currentUser = UserModel.fromFirestore(doc);
        await _saveUserToPreferences(_currentUser!);
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }
  
  // Save user to shared preferences
  Future<void> _saveUserToPreferences(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', user.id);
      await prefs.setString('user_email', user.email);
      await prefs.setString('user_name', user.fullName);
      await prefs.setString('user_phone', user.phoneNumber);
      await prefs.setInt('user_type', user.userType.index);
      await prefs.setBool('is_premium', user.isPremium);
    } catch (e) {
      debugPrint('Error saving user to preferences: $e');
    }
  }
  
  // Clear user from shared preferences
  Future<void> _clearUserFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_id');
      await prefs.remove('user_email');
      await prefs.remove('user_name');
      await prefs.remove('user_phone');
      await prefs.remove('user_type');
      await prefs.remove('is_premium');
    } catch (e) {
      debugPrint('Error clearing user from preferences: $e');
    }
  }
  
  // Get user by ID (for admin)
  Future<UserModel?> getUserById(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConfig.usersCollection)
          .doc(userId)
          .get();
      
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting user by ID: $e');
      return null;
    }
  }
  
  // Get all users (for admin)
  Future<List<UserModel>> getAllUsers() async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.usersCollection)
          .orderBy('createdAt', descending: true)
          .get();
      
      return querySnapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting all users: $e');
      return [];
    }
  }
  
  // Update user status (for admin)
  Future<bool> updateUserStatus(String userId, bool isActive) async {
    try {
      await _firestore
          .collection(AppConfig.usersCollection)
          .doc(userId)
          .update({
        'isActive': isActive,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      
      return true;
    } catch (e) {
      debugPrint('Error updating user status: $e');
      return false;
    }
  }
  
  // Verify user account (for admin)
  Future<bool> verifyUserAccount(String userId) async {
    try {
      await _firestore
          .collection(AppConfig.usersCollection)
          .doc(userId)
          .update({
        'isVerified': true,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      
      return true;
    } catch (e) {
      debugPrint('Error verifying user account: $e');
      return false;
    }
  }
}