import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: AppColors.primary,
      ),
      body: const Center(
        child: Text(
          'Admin Dashboard - Implementation in progress',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}