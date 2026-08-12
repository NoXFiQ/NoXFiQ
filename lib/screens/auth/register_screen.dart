import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Register'),
        backgroundColor: AppColors.primary,
      ),
      body: const Center(
        child: Text(
          'Register Screen - Implementation in progress',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}