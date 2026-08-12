import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: AppColors.primary,
      ),
      body: const Center(
        child: Text(
          'Login Screen - Implementation in progress',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}