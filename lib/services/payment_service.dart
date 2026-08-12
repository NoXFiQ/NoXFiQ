import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'notification_service.dart';

class PaymentService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final NotificationService _notificationService = NotificationService();
  final Uuid _uuid = const Uuid();
  
  List<PaymentModel> _payments = [];
  bool _isLoading = false;
  PaymentModel? _currentPayment;
  
  List<PaymentModel> get payments => _payments;
  bool get isLoading => _isLoading;
  PaymentModel? get currentPayment => _currentPayment;
  
  // Initialize payment service
  Future<void> initialize() async {
    await loadPayments();
  }
  
  // Initiate payment
  Future<PaymentModel?> initiatePayment({
    required String userId,
    required String userName,
    required String userPhone,
    required PaymentType type,
    required PaymentMethod method,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final amount = PaymentPricing.getPrice(type);
      final paymentId = _uuid.v4();
      final referenceNumber = _generateReferenceNumber();
      
      final payment = PaymentModel(
        id: paymentId,
        userId: userId,
        userName: userName,
        userPhone: userPhone,
        type: type,
        amount: amount,
        method: method,
        transactionId: '',
        referenceNumber: referenceNumber,
        createdAt: DateTime.now(),
      );
      
      // Save payment to Firestore
      await _firestore
          .collection(AppConfig.paymentsCollection)
          .doc(paymentId)
          .set(payment.toMap());
      
      // Process payment based on method
      final result = await _processPayment(payment);
      
      if (result != null) {
        _currentPayment = result;
        await loadPayments();
        
        // Notify admin
        await _notificationService.sendPaymentNotificationToAdmin(result);
        
        return result;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error initiating payment: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Process payment based on method
  Future<PaymentModel?> _processPayment(PaymentModel payment) async {
    try {
      switch (payment.method) {
        case PaymentMethod.lipaNamba:
          return await _processLipaNambaPayment(payment);
        case PaymentMethod.vodacom:
          return await _processVodacomPayment(payment);
        case PaymentMethod.airtel:
          return await _processAirtelPayment(payment);
        case PaymentMethod.halotel:
          return await _processHalotelPayment(payment);
        case PaymentMethod.tigo:
          return await _processTigoPayment(payment);
      }
    } catch (e) {
      debugPrint('Error processing payment: $e');
      return null;
    }
  }
  
  // Process Lipa Namba payment
  Future<PaymentModel?> _processLipaNambaPayment(PaymentModel payment) async {
    try {
      final network = MobileMoneyNetworks.networks[PaymentMethod.lipaNamba]!;
      const apiKey = 'YOUR_LIPA_NAMBA_API_KEY';
      
      final response = await http.post(
        Uri.parse('${network.apiEndpoint}/payments/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'amount': payment.amount,
          'phone': payment.userPhone,
          'reference': payment.referenceNumber,
          'description': 'Soko Kitaa ${payment.typeName}',
          'callback_url': 'https://sokokitaa.com/callback',
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedPayment = payment.copyWith(
          transactionId: data['transaction_id'] ?? '',
          status: PaymentStatus.pending,
        );
        
        await _updatePayment(updatedPayment);
        return updatedPayment;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error processing Lipa Namba payment: $e');
      return null;
    }
  }
  
  // Process Vodacom M-Pesa payment
  Future<PaymentModel?> _processVodacomPayment(PaymentModel payment) async {
    try {
      final network = MobileMoneyNetworks.networks[PaymentMethod.vodacom]!;
      const apiKey = 'YOUR_VODACOM_API_KEY';
      
      final response = await http.post(
        Uri.parse('${network.apiEndpoint}/mpesa/stkpush'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'BusinessShortCode': 'YOUR_BUSINESS_CODE',
          'Password': 'YOUR_PASSWORD',
          'Timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
          'TransactionType': 'CustomerPayBillOnline',
          'Amount': payment.amount.toInt(),
          'PartyA': payment.userPhone,
          'PartyB': 'YOUR_BUSINESS_CODE',
          'PhoneNumber': payment.userPhone,
          'CallBackURL': 'https://sokokitaa.com/callback',
          'AccountReference': payment.referenceNumber,
          'TransactionDesc': 'Soko Kitaa ${payment.typeName}',
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedPayment = payment.copyWith(
          transactionId: data['CheckoutRequestID'] ?? '',
          status: PaymentStatus.pending,
        );
        
        await _updatePayment(updatedPayment);
        return updatedPayment;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error processing Vodacom payment: $e');
      return null;
    }
  }
  
  // Process Airtel Money payment
  Future<PaymentModel?> _processAirtelPayment(PaymentModel payment) async {
    try {
      final network = MobileMoneyNetworks.networks[PaymentMethod.airtel]!;
      const apiKey = 'YOUR_AIRTEL_API_KEY';
      
      final response = await http.post(
        Uri.parse('${network.apiEndpoint}/merchant/v1/payments/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'X-Country': 'TZ',
          'X-Currency': 'TZS',
        },
        body: jsonEncode({
          'reference': payment.referenceNumber,
          'subscriber': {
            'country': 'TZ',
            'currency': 'TZS',
            'msisdn': payment.userPhone,
          },
          'transaction': {
            'amount': payment.amount,
            'country': 'TZ',
            'currency': 'TZS',
            'id': payment.id,
          },
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedPayment = payment.copyWith(
          transactionId: data['data']['transaction']['id'] ?? '',
          status: PaymentStatus.pending,
        );
        
        await _updatePayment(updatedPayment);
        return updatedPayment;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error processing Airtel payment: $e');
      return null;
    }
  }
  
  // Process Halotel payment
  Future<PaymentModel?> _processHalotelPayment(PaymentModel payment) async {
    try {
      // Halotel API integration would go here
      // For now, mark as pending and require manual verification
      final updatedPayment = payment.copyWith(
        transactionId: _uuid.v4(),
        status: PaymentStatus.pending,
      );
      
      await _updatePayment(updatedPayment);
      return updatedPayment;
    } catch (e) {
      debugPrint('Error processing Halotel payment: $e');
      return null;
    }
  }
  
  // Process Tigo Pesa payment
  Future<PaymentModel?> _processTigoPayment(PaymentModel payment) async {
    try {
      // Tigo Pesa API integration would go here
      // For now, mark as pending and require manual verification
      final updatedPayment = payment.copyWith(
        transactionId: _uuid.v4(),
        status: PaymentStatus.pending,
      );
      
      await _updatePayment(updatedPayment);
      return updatedPayment;
    } catch (e) {
      debugPrint('Error processing Tigo payment: $e');
      return null;
    }
  }
  
  // Upload payment receipt
  Future<bool> uploadPaymentReceipt(String paymentId, File receiptImage) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final fileName = '${paymentId}_receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(AppConfig.paymentReceiptsPath).child(fileName);
      
      final uploadTask = ref.putFile(receiptImage);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Update payment with receipt URL
      await _firestore
          .collection(AppConfig.paymentsCollection)
          .doc(paymentId)
          .update({
        'receiptImageUrl': downloadUrl,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      
      await loadPayments();
      return true;
    } catch (e) {
      debugPrint('Error uploading payment receipt: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Approve payment (admin only)
  Future<bool> approvePayment(String paymentId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final payment = await getPaymentById(paymentId);
      if (payment == null) return false;
      
      final updatedPayment = payment.copyWith(
        status: PaymentStatus.completed,
        completedAt: DateTime.now(),
      );
      
      await _updatePayment(updatedPayment);
      
      // Send confirmation to user
      await _notificationService.sendPaymentConfirmation(updatedPayment);
      
      return true;
    } catch (e) {
      debugPrint('Error approving payment: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Reject payment (admin only)
  Future<bool> rejectPayment(String paymentId, String reason) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final updatedPayment = PaymentModel(
        id: paymentId,
        userId: '',
        userName: '',
        userPhone: '',
        type: PaymentType.prePremium,
        amount: 0,
        method: PaymentMethod.lipaNamba,
        status: PaymentStatus.failed,
        transactionId: '',
        referenceNumber: '',
        createdAt: DateTime.now(),
        failureReason: reason,
      );
      
      await _updatePayment(updatedPayment);
      return true;
    } catch (e) {
      debugPrint('Error rejecting payment: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Get payment by ID
  Future<PaymentModel?> getPaymentById(String paymentId) async {
    try {
      final doc = await _firestore
          .collection(AppConfig.paymentsCollection)
          .doc(paymentId)
          .get();
      
      if (doc.exists) {
        return PaymentModel.fromFirestore(doc);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting payment by ID: $e');
      return null;
    }
  }
  
  // Get payments by user ID
  Future<List<PaymentModel>> getPaymentsByUserId(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.paymentsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      
      return querySnapshot.docs
          .map((doc) => PaymentModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting payments by user ID: $e');
      return [];
    }
  }
  
  // Load all payments
  Future<void> loadPayments() async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.paymentsCollection)
          .orderBy('createdAt', descending: true)
          .get();
      
      _payments = querySnapshot.docs
          .map((doc) => PaymentModel.fromFirestore(doc))
          .toList();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading payments: $e');
    }
  }
  
  // Update payment
  Future<void> _updatePayment(PaymentModel payment) async {
    try {
      await _firestore
          .collection(AppConfig.paymentsCollection)
          .doc(payment.id)
          .update(payment.toMap());
      
      await loadPayments();
    } catch (e) {
      debugPrint('Error updating payment: $e');
    }
  }
  
  // Generate reference number
  String _generateReferenceNumber() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'SK$timestamp';
  }
  
  // Get payment statistics (for admin)
  Future<Map<String, dynamic>> getPaymentStatistics() async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.paymentsCollection)
          .get();
      
      final payments = querySnapshot.docs
          .map((doc) => PaymentModel.fromFirestore(doc))
          .toList();
      
      final totalPayments = payments.length;
      final completedPayments = payments.where((p) => p.isCompleted).length;
      final pendingPayments = payments.where((p) => p.isPending).length;
      final failedPayments = payments.where((p) => p.isFailed).length;
      
      final totalRevenue = payments
          .where((p) => p.isCompleted)
          .fold(0.0, (sum, p) => sum + p.amount);
      
      return {
        'totalPayments': totalPayments,
        'completedPayments': completedPayments,
        'pendingPayments': pendingPayments,
        'failedPayments': failedPayments,
        'totalRevenue': totalRevenue,
        'successRate': totalPayments > 0 ? (completedPayments / totalPayments) * 100 : 0.0,
      };
    } catch (e) {
      debugPrint('Error getting payment statistics: $e');
      return {};
    }
  }
  
  // Check payment status
  Future<PaymentStatus> checkPaymentStatus(String paymentId) async {
    try {
      final payment = await getPaymentById(paymentId);
      return payment?.status ?? PaymentStatus.failed;
    } catch (e) {
      debugPrint('Error checking payment status: $e');
      return PaymentStatus.failed;
    }
  }
  
  // Get available payment methods
  List<PaymentMethod> getAvailablePaymentMethods() {
    return MobileMoneyNetworks.availableNetworks;
  }
  
  // Get payment method info
  MobileMoneyNetwork? getPaymentMethodInfo(PaymentMethod method) {
    return MobileMoneyNetworks.networks[method];
  }
  
  // Clear current payment
  void clearCurrentPayment() {
    _currentPayment = null;
    notifyListeners();
  }
}