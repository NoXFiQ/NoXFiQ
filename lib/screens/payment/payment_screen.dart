import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: AppColors.primary,
      ),
      body: const Center(
        child: Text(
          'Payment Screen - Implementation in progress',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}