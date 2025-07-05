import 'package:cloud_firestore/cloud_firestore.dart';

enum UserType { free, prePremium, fullPremium, admin }

class UserModel {
  final String id;
  final String email;
  final String phoneNumber;
  final String fullName;
  final UserType userType;
  final DateTime? premiumExpiryDate;
  final int dailyProductsUploaded;
  final DateTime lastUploadDate;
  final LocationData? location;
  final bool isActive;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> paymentHistory;
  final double totalSpent;

  UserModel({
    required this.id,
    required this.email,
    required this.phoneNumber,
    required this.fullName,
    this.userType = UserType.free,
    this.premiumExpiryDate,
    this.dailyProductsUploaded = 0,
    required this.lastUploadDate,
    this.location,
    this.isActive = true,
    this.isVerified = false,
    required this.createdAt,
    required this.updatedAt,
    this.paymentHistory = const [],
    this.totalSpent = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'phoneNumber': phoneNumber,
      'fullName': fullName,
      'userType': userType.index,
      'premiumExpiryDate': premiumExpiryDate?.millisecondsSinceEpoch,
      'dailyProductsUploaded': dailyProductsUploaded,
      'lastUploadDate': lastUploadDate.millisecondsSinceEpoch,
      'location': location?.toMap(),
      'isActive': isActive,
      'isVerified': isVerified,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'paymentHistory': paymentHistory,
      'totalSpent': totalSpent,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      fullName: map['fullName'] ?? '',
      userType: UserType.values[map['userType'] ?? 0],
      premiumExpiryDate: map['premiumExpiryDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['premiumExpiryDate'])
          : null,
      dailyProductsUploaded: map['dailyProductsUploaded']?.toInt() ?? 0,
      lastUploadDate: DateTime.fromMillisecondsSinceEpoch(map['lastUploadDate']),
      location: map['location'] != null 
          ? LocationData.fromMap(map['location'])
          : null,
      isActive: map['isActive'] ?? true,
      isVerified: map['isVerified'] ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
      paymentHistory: List<String>.from(map['paymentHistory'] ?? []),
      totalSpent: map['totalSpent']?.toDouble() ?? 0.0,
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel.fromMap(data);
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? phoneNumber,
    String? fullName,
    UserType? userType,
    DateTime? premiumExpiryDate,
    int? dailyProductsUploaded,
    DateTime? lastUploadDate,
    LocationData? location,
    bool? isActive,
    bool? isVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? paymentHistory,
    double? totalSpent,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      fullName: fullName ?? this.fullName,
      userType: userType ?? this.userType,
      premiumExpiryDate: premiumExpiryDate ?? this.premiumExpiryDate,
      dailyProductsUploaded: dailyProductsUploaded ?? this.dailyProductsUploaded,
      lastUploadDate: lastUploadDate ?? this.lastUploadDate,
      location: location ?? this.location,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentHistory: paymentHistory ?? this.paymentHistory,
      totalSpent: totalSpent ?? this.totalSpent,
    );
  }

  bool get isPremium => userType == UserType.prePremium || userType == UserType.fullPremium;
  bool get isAdmin => userType == UserType.admin;
  bool get canUploadProducts => isPremium && isActive && isVerified;
  bool get canViewSellerLocation => isPremium;
  
  bool get isPremiumExpired {
    if (premiumExpiryDate == null) return true;
    return DateTime.now().isAfter(premiumExpiryDate!);
  }

  int get maxDailyUploads {
    if (userType == UserType.fullPremium) return 50; // Unlimited for full premium
    if (userType == UserType.prePremium) return 5;
    return 0;
  }
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
}