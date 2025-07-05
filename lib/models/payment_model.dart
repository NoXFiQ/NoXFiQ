import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { pending, completed, failed, cancelled }
enum PaymentMethod { lipaNamba, vodacom, airtel, halotel, tigo }
enum PaymentType { prePremium, fullPremium, promotion }

class PaymentModel {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final PaymentType type;
  final double amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final String transactionId;
  final String referenceNumber;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? failureReason;
  final String? receiptImageUrl;
  final Map<String, dynamic> metadata;

  PaymentModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.type,
    required this.amount,
    required this.method,
    this.status = PaymentStatus.pending,
    required this.transactionId,
    required this.referenceNumber,
    required this.createdAt,
    this.completedAt,
    this.failureReason,
    this.receiptImageUrl,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'type': type.index,
      'amount': amount,
      'method': method.index,
      'status': status.index,
      'transactionId': transactionId,
      'referenceNumber': referenceNumber,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'failureReason': failureReason,
      'receiptImageUrl': receiptImageUrl,
      'metadata': metadata,
    };
  }

  factory PaymentModel.fromMap(Map<String, dynamic> map) {
    return PaymentModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userPhone: map['userPhone'] ?? '',
      type: PaymentType.values[map['type'] ?? 0],
      amount: map['amount']?.toDouble() ?? 0.0,
      method: PaymentMethod.values[map['method'] ?? 0],
      status: PaymentStatus.values[map['status'] ?? 0],
      transactionId: map['transactionId'] ?? '',
      referenceNumber: map['referenceNumber'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      completedAt: map['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'])
          : null,
      failureReason: map['failureReason'],
      receiptImageUrl: map['receiptImageUrl'],
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }

  factory PaymentModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return PaymentModel.fromMap(data);
  }

  PaymentModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userPhone,
    PaymentType? type,
    double? amount,
    PaymentMethod? method,
    PaymentStatus? status,
    String? transactionId,
    String? referenceNumber,
    DateTime? createdAt,
    DateTime? completedAt,
    String? failureReason,
    String? receiptImageUrl,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      status: status ?? this.status,
      transactionId: transactionId ?? this.transactionId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      failureReason: failureReason ?? this.failureReason,
      receiptImageUrl: receiptImageUrl ?? this.receiptImageUrl,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isPending => status == PaymentStatus.pending;
  bool get isCompleted => status == PaymentStatus.completed;
  bool get isFailed => status == PaymentStatus.failed;
  String get formattedAmount => 'TZS ${amount.toStringAsFixed(0)}';
  String get methodName => _getMethodName(method);
  String get typeName => _getTypeName(type);

  static String _getMethodName(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.lipaNamba:
        return 'Lipa Namba';
      case PaymentMethod.vodacom:
        return 'Vodacom M-Pesa';
      case PaymentMethod.airtel:
        return 'Airtel Money';
      case PaymentMethod.halotel:
        return 'Halotel';
      case PaymentMethod.tigo:
        return 'Tigo Pesa';
    }
  }

  static String _getTypeName(PaymentType type) {
    switch (type) {
      case PaymentType.prePremium:
        return 'Pre-Premium (2 months)';
      case PaymentType.fullPremium:
        return 'Full Premium';
      case PaymentType.promotion:
        return 'Product Promotion';
    }
  }
}

// Tanzania Mobile Money Network Information
class MobileMoneyNetworks {
  static const Map<PaymentMethod, MobileMoneyNetwork> networks = {
    PaymentMethod.lipaNamba: MobileMoneyNetwork(
      name: 'Lipa Namba',
      code: 'LN',
      ussd: '*150*01#',
      apiEndpoint: 'https://api.lipanamba.com',
      color: 0xFF1E88E5,
    ),
    PaymentMethod.vodacom: MobileMoneyNetwork(
      name: 'Vodacom M-Pesa',
      code: 'MPESA',
      ussd: '*150*00#',
      apiEndpoint: 'https://api.vodacom.co.tz',
      color: 0xFFE53935,
    ),
    PaymentMethod.airtel: MobileMoneyNetwork(
      name: 'Airtel Money',
      code: 'AIRTEL',
      ussd: '*150*60#',
      apiEndpoint: 'https://api.airtel.co.tz',
      color: 0xFFE53935,
    ),
    PaymentMethod.halotel: MobileMoneyNetwork(
      name: 'Halotel',
      code: 'HALO',
      ussd: '*150*88#',
      apiEndpoint: 'https://api.halotel.co.tz',
      color: 0xFF7B1FA2,
    ),
    PaymentMethod.tigo: MobileMoneyNetwork(
      name: 'Tigo Pesa',
      code: 'TIGO',
      ussd: '*150*71#',
      apiEndpoint: 'https://api.tigo.co.tz',
      color: 0xFF1976D2,
    ),
  };

  static List<PaymentMethod> get availableNetworks => networks.keys.toList();
}

class MobileMoneyNetwork {
  final String name;
  final String code;
  final String ussd;
  final String apiEndpoint;
  final int color;

  const MobileMoneyNetwork({
    required this.name,
    required this.code,
    required this.ussd,
    required this.apiEndpoint,
    required this.color,
  });
}

// Payment pricing
class PaymentPricing {
  static const double prePremiumPrice = 10000.0; // TZS
  static const double fullPremiumPrice = 20000.0; // TZS
  static const int prePremiumDurationMonths = 2;
  static const int fullPremiumDurationMonths = 12;

  static double getPrice(PaymentType type) {
    switch (type) {
      case PaymentType.prePremium:
        return prePremiumPrice;
      case PaymentType.fullPremium:
        return fullPremiumPrice;
      case PaymentType.promotion:
        return 5000.0; // TZS for product promotion
    }
  }

  static int getDurationMonths(PaymentType type) {
    switch (type) {
      case PaymentType.prePremium:
        return prePremiumDurationMonths;
      case PaymentType.fullPremium:
        return fullPremiumDurationMonths;
      case PaymentType.promotion:
        return 1; // 1 month promotion
    }
  }
}