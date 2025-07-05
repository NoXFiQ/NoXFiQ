import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'notification_service.dart';

class ProductService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final NotificationService _notificationService = NotificationService();
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();
  
  List<ProductModel> _products = [];
  List<ProductModel> _filteredProducts = [];
  List<ProductModel> _myProducts = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedCategory = '';
  String _selectedRegion = '';
  ProductModel? _selectedProduct;
  
  List<ProductModel> get products => _filteredProducts;
  List<ProductModel> get myProducts => _myProducts;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedCategory => _selectedCategory;
  String get selectedRegion => _selectedRegion;
  ProductModel? get selectedProduct => _selectedProduct;
  
  // Initialize product service
  Future<void> initialize() async {
    await loadProducts();
  }
  
  // Load all products
  Future<void> loadProducts() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .where('status', isEqualTo: ProductStatus.active.index)
          .orderBy('createdAt', descending: true)
          .get();
      
      _products = querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
      
      _applyFilters();
    } catch (e) {
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Load user products
  Future<void> loadUserProducts(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .where('sellerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      
      _myProducts = querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user products: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Upload product
  Future<bool> uploadProduct({
    required String sellerId,
    required String sellerName,
    required String sellerPhone,
    required String title,
    required String description,
    required double price,
    required String category,
    required LocationData location,
    required List<XFile> images,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Validate inputs
      if (title.isEmpty || description.isEmpty || price <= 0 || images.isEmpty) {
        return false;
      }
      
      if (images.length > AppConfig.maxProductImages) {
        return false;
      }
      
      // Upload images
      final imageUrls = await _uploadImages(images);
      if (imageUrls.isEmpty) {
        return false;
      }
      
      // Create product
      final productId = _uuid.v4();
      final product = ProductModel(
        id: productId,
        sellerId: sellerId,
        sellerName: sellerName,
        sellerPhone: sellerPhone,
        title: title,
        description: description,
        price: price,
        category: category,
        imageUrls: imageUrls,
        location: location,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Save to Firestore
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .set(product.toMap());
      
      // Reload products
      await loadProducts();
      
      // Send notification
      await _notificationService.sendProductNotification(
        title: 'Bidhaa Mpya!',
        message: 'Bidhaa "$title" imeongezwa kikamilifu',
        userId: sellerId,
      );
      
      return true;
    } catch (e) {
      debugPrint('Error uploading product: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Update product
  Future<bool> updateProduct({
    required String productId,
    required String title,
    required String description,
    required double price,
    required String category,
    List<XFile>? newImages,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final product = await getProductById(productId);
      if (product == null) return false;
      
      List<String> imageUrls = product.imageUrls;
      
      // Upload new images if provided
      if (newImages != null && newImages.isNotEmpty) {
        final newImageUrls = await _uploadImages(newImages);
        if (newImageUrls.isNotEmpty) {
          imageUrls = [...imageUrls, ...newImageUrls];
          
          // Remove old images if exceeding limit
          if (imageUrls.length > AppConfig.maxProductImages) {
            imageUrls = imageUrls.take(AppConfig.maxProductImages).toList();
          }
        }
      }
      
      final updatedProduct = product.copyWith(
        title: title,
        description: description,
        price: price,
        category: category,
        imageUrls: imageUrls,
        updatedAt: DateTime.now(),
      );
      
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .update(updatedProduct.toMap());
      
      await loadProducts();
      return true;
    } catch (e) {
      debugPrint('Error updating product: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Mark product as sold
  Future<bool> markProductAsSold(String productId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .update({
        'status': ProductStatus.sold.index,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      
      await loadProducts();
      return true;
    } catch (e) {
      debugPrint('Error marking product as sold: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Delete product
  Future<bool> deleteProduct(String productId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Get product to delete images
      final product = await getProductById(productId);
      if (product != null) {
        // Delete images from storage
        await _deleteImages(product.imageUrls);
      }
      
      // Delete product document
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .delete();
      
      await loadProducts();
      return true;
    } catch (e) {
      debugPrint('Error deleting product: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Get product by ID
  Future<ProductModel?> getProductById(String productId) async {
    try {
      final doc = await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .get();
      
      if (doc.exists) {
        return ProductModel.fromFirestore(doc);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting product by ID: $e');
      return null;
    }
  }
  
  // Search products
  Future<void> searchProducts(String query) async {
    _searchQuery = query;
    _applyFilters();
  }
  
  // Filter by category
  void filterByCategory(String category) {
    _selectedCategory = category;
    _applyFilters();
  }
  
  // Filter by region
  void filterByRegion(String region) {
    _selectedRegion = region;
    _applyFilters();
  }
  
  // Clear filters
  void clearFilters() {
    _searchQuery = '';
    _selectedCategory = '';
    _selectedRegion = '';
    _applyFilters();
  }
  
  // Apply filters
  void _applyFilters() {
    _filteredProducts = _products.where((product) {
      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!product.title.toLowerCase().contains(query) &&
            !product.description.toLowerCase().contains(query) &&
            !product.category.toLowerCase().contains(query)) {
          return false;
        }
      }
      
      // Category filter
      if (_selectedCategory.isNotEmpty && product.category != _selectedCategory) {
        return false;
      }
      
      // Region filter
      if (_selectedRegion.isNotEmpty && product.location.region != _selectedRegion) {
        return false;
      }
      
      return true;
    }).toList();
    
    notifyListeners();
  }
  
  // Get products by category
  Future<List<ProductModel>> getProductsByCategory(String category) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .where('category', isEqualTo: category)
          .where('status', isEqualTo: ProductStatus.active.index)
          .orderBy('createdAt', descending: true)
          .get();
      
      return querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting products by category: $e');
      return [];
    }
  }
  
  // Get products by region
  Future<List<ProductModel>> getProductsByRegion(String region) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .where('location.region', isEqualTo: region)
          .where('status', isEqualTo: ProductStatus.active.index)
          .orderBy('createdAt', descending: true)
          .get();
      
      return querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting products by region: $e');
      return [];
    }
  }
  
  // Get nearby products
  Future<List<ProductModel>> getNearbyProducts(
    LocationData userLocation,
    double radiusKm,
  ) async {
    try {
      // For now, return all products and filter by distance
      // In a real app, you would use GeoHash or similar for efficient geo queries
      final allProducts = await _getAllProducts();
      
      return allProducts.where((product) {
        final distance = _calculateDistance(
          userLocation.latitude,
          userLocation.longitude,
          product.location.latitude,
          product.location.longitude,
        );
        return distance <= radiusKm * 1000; // Convert km to meters
      }).toList();
    } catch (e) {
      debugPrint('Error getting nearby products: $e');
      return [];
    }
  }
  
  // Get all products (for admin or filtering)
  Future<List<ProductModel>> _getAllProducts() async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .orderBy('createdAt', descending: true)
          .get();
      
      return querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting all products: $e');
      return [];
    }
  }
  
  // Increment product view count
  Future<void> incrementProductViews(String productId) async {
    try {
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .update({
        'views': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('Error incrementing product views: $e');
    }
  }
  
  // Add interested buyer
  Future<void> addInterestedBuyer(String productId, String buyerId) async {
    try {
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .update({
        'interestedBuyers': FieldValue.arrayUnion([buyerId]),
      });
    } catch (e) {
      debugPrint('Error adding interested buyer: $e');
    }
  }
  
  // Set selected product
  void setSelectedProduct(ProductModel? product) {
    _selectedProduct = product;
    notifyListeners();
  }
  
  // Upload images to Firebase Storage
  Future<List<String>> _uploadImages(List<XFile> images) async {
    try {
      final List<String> imageUrls = [];
      
      for (final image in images) {
        // Check file size
        final file = File(image.path);
        final fileSizeInMB = await file.length() / (1024 * 1024);
        
        if (fileSizeInMB > AppConfig.maxImageSizeMB) {
          continue; // Skip oversized images
        }
        
        final fileName = '${_uuid.v4()}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = _storage.ref().child(AppConfig.productImagesPath).child(fileName);
        
        final uploadTask = ref.putFile(file);
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();
        
        imageUrls.add(downloadUrl);
      }
      
      return imageUrls;
    } catch (e) {
      debugPrint('Error uploading images: $e');
      return [];
    }
  }
  
  // Delete images from Firebase Storage
  Future<void> _deleteImages(List<String> imageUrls) async {
    try {
      for (final url in imageUrls) {
        final ref = _storage.refFromURL(url);
        await ref.delete();
      }
    } catch (e) {
      debugPrint('Error deleting images: $e');
    }
  }
  
  // Calculate distance between two coordinates
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    
    final double lat1Rad = lat1 * (3.14159265359 / 180);
    final double lat2Rad = lat2 * (3.14159265359 / 180);
    final double deltaLatRad = (lat2 - lat1) * (3.14159265359 / 180);
    final double deltaLonRad = (lon2 - lon1) * (3.14159265359 / 180);
    
    final double a = (deltaLatRad / 2).sin() * (deltaLatRad / 2).sin() +
        lat1Rad.cos() * lat2Rad.cos() *
        (deltaLonRad / 2).sin() * (deltaLonRad / 2).sin();
    
    final double c = 2 * (a.sqrt()).atan2((1 - a).sqrt());
    
    return earthRadius * c;
  }
  
  // Get product statistics
  Future<Map<String, dynamic>> getProductStatistics() async {
    try {
      final allProducts = await _getAllProducts();
      final activeProducts = allProducts.where((p) => p.isActive).length;
      final soldProducts = allProducts.where((p) => p.isSold).length;
      final totalViews = allProducts.fold(0, (sum, p) => sum + p.views);
      
      final categoryStats = <String, int>{};
      for (final product in allProducts) {
        categoryStats[product.category] = (categoryStats[product.category] ?? 0) + 1;
      }
      
      return {
        'totalProducts': allProducts.length,
        'activeProducts': activeProducts,
        'soldProducts': soldProducts,
        'totalViews': totalViews,
        'categoryStats': categoryStats,
      };
    } catch (e) {
      debugPrint('Error getting product statistics: $e');
      return {};
    }
  }
  
  // Get trending products
  Future<List<ProductModel>> getTrendingProducts({int limit = 10}) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .where('status', isEqualTo: ProductStatus.active.index)
          .orderBy('views', descending: true)
          .limit(limit)
          .get();
      
      return querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting trending products: $e');
      return [];
    }
  }
  
  // Get recent products
  Future<List<ProductModel>> getRecentProducts({int limit = 10}) async {
    try {
      final querySnapshot = await _firestore
          .collection(AppConfig.productsCollection)
          .where('status', isEqualTo: ProductStatus.active.index)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting recent products: $e');
      return [];
    }
  }
  
  // Promote product (admin)
  Future<bool> promoteProduct(String productId, int durationDays) async {
    try {
      final promotedUntil = DateTime.now().add(Duration(days: durationDays));
      
      await _firestore
          .collection(AppConfig.productsCollection)
          .doc(productId)
          .update({
        'isPromoted': true,
        'promotedUntil': promotedUntil.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      
      return true;
    } catch (e) {
      debugPrint('Error promoting product: $e');
      return false;
    }
  }
  
  // Check if user can upload products
  bool canUserUploadProducts(UserModel user) {
    if (!user.canUploadProducts) return false;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastUpload = DateTime(
      user.lastUploadDate.year,
      user.lastUploadDate.month,
      user.lastUploadDate.day,
    );
    
    if (!today.isAtSameMomentAs(lastUpload)) {
      return true; // New day, reset count
    }
    
    return user.dailyProductsUploaded < user.maxDailyUploads;
  }
}