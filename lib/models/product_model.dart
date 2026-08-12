import 'package:cloud_firestore/cloud_firestore.dart';

enum ProductStatus { active, sold, inactive }

class ProductModel {
  final String id;
  final String sellerId;
  final String sellerName;
  final String sellerPhone;
  final String title;
  final String description;
  final double price;
  final String category;
  final List<String> imageUrls;
  final ProductStatus status;
  final LocationData location;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int views;
  final List<String> interestedBuyers;
  final bool isPromoted;
  final DateTime? promotedUntil;
  final Map<String, dynamic> metadata;

  ProductModel({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.sellerPhone,
    required this.title,
    required this.description,
    required this.price,
    required this.category,
    required this.imageUrls,
    this.status = ProductStatus.active,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
    this.views = 0,
    this.interestedBuyers = const [],
    this.isPromoted = false,
    this.promotedUntil,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerPhone': sellerPhone,
      'title': title,
      'description': description,
      'price': price,
      'category': category,
      'imageUrls': imageUrls,
      'status': status.index,
      'location': location.toMap(),
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'views': views,
      'interestedBuyers': interestedBuyers,
      'isPromoted': isPromoted,
      'promotedUntil': promotedUntil?.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] ?? '',
      sellerId: map['sellerId'] ?? '',
      sellerName: map['sellerName'] ?? '',
      sellerPhone: map['sellerPhone'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      price: map['price']?.toDouble() ?? 0.0,
      category: map['category'] ?? '',
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      status: ProductStatus.values[map['status'] ?? 0],
      location: LocationData.fromMap(map['location']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
      views: map['views']?.toInt() ?? 0,
      interestedBuyers: List<String>.from(map['interestedBuyers'] ?? []),
      isPromoted: map['isPromoted'] ?? false,
      promotedUntil: map['promotedUntil'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['promotedUntil'])
          : null,
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }

  factory ProductModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ProductModel.fromMap(data);
  }

  ProductModel copyWith({
    String? id,
    String? sellerId,
    String? sellerName,
    String? sellerPhone,
    String? title,
    String? description,
    double? price,
    String? category,
    List<String>? imageUrls,
    ProductStatus? status,
    LocationData? location,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? views,
    List<String>? interestedBuyers,
    bool? isPromoted,
    DateTime? promotedUntil,
    Map<String, dynamic>? metadata,
  }) {
    return ProductModel(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerPhone: sellerPhone ?? this.sellerPhone,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      views: views ?? this.views,
      interestedBuyers: interestedBuyers ?? this.interestedBuyers,
      isPromoted: isPromoted ?? this.isPromoted,
      promotedUntil: promotedUntil ?? this.promotedUntil,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isActive => status == ProductStatus.active;
  bool get isSold => status == ProductStatus.sold;
  String get formattedPrice => 'TZS ${price.toStringAsFixed(0)}';
}

class LocationData {
  final double latitude;
  final double longitude;
  final String region;
  final String district;
  final String ward;
  final String street;
  final String address;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.region,
    required this.district,
    required this.ward,
    required this.street,
    required this.address,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'region': region,
      'district': district,
      'ward': ward,
      'street': street,
      'address': address,
    };
  }

  factory LocationData.fromMap(Map<String, dynamic> map) {
    return LocationData(
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      region: map['region'] ?? '',
      district: map['district'] ?? '',
      ward: map['ward'] ?? '',
      street: map['street'] ?? '',
      address: map['address'] ?? '',
    );
  }

  String get fullAddress => '$street, $ward, $district, $region';
}

// Product categories for Tanzania market
class ProductCategories {
  static const List<String> categories = [
    'Electronics',
    'Fashion & Clothing',
    'Home & Garden',
    'Automotive',
    'Sports & Recreation',
    'Books & Education',
    'Health & Beauty',
    'Food & Beverages',
    'Agriculture & Farming',
    'Business & Industrial',
    'Real Estate',
    'Services',
  ];

  static const Map<String, String> categoryTranslations = {
    'Electronics': 'Elektroniki',
    'Fashion & Clothing': 'Mavazi na Mitindo',
    'Home & Garden': 'Nyumba na Bustani',
    'Automotive': 'Magari',
    'Sports & Recreation': 'Michezo',
    'Books & Education': 'Vitabu na Elimu',
    'Health & Beauty': 'Afya na Urembo',
    'Food & Beverages': 'Chakula na Vinywaji',
    'Agriculture & Farming': 'Kilimo',
    'Business & Industrial': 'Biashara',
    'Real Estate': 'Mali Isiyohamishika',
    'Services': 'Huduma',
  };
}