import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class ProductDetailsScreen extends StatelessWidget {
  const ProductDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Product Details'),
        backgroundColor: AppColors.primary,
      ),
      body: const Center(
        child: Text(
          'Product Details Screen - Implementation in progress',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}