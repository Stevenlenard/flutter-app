import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class RegisterChoiceScreen extends StatelessWidget {
  const RegisterChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppDecorations.loginBackground,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(150),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF00796B), size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 1),
              // 👤 Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.loginButtonEnd.withAlpha(100),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.person_add_rounded, size: 54, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: AppColors.tealText,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select your account type to continue',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textGray,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 48),
              // Options
              _buildChoiceCard(
                context: context,
                title: 'Resident',
                subtitle: 'Track trucks and file complaints',
                icon: Icons.home_rounded,
                iconColor: const Color(0xFF2196F3),
                bgColor: const Color(0xFFE3F2FD),
                route: '/register_resident',
              ),
              const SizedBox(height: 20),
              _buildChoiceCard(
                context: context,
                title: 'Driver',
                subtitle: 'Manage routes and track collections',
                icon: Icons.local_shipping_rounded,
                iconColor: const Color(0xFF4CAF50),
                bgColor: const Color(0xFFE8F5E9),
                route: '/register_driver',
              ),
              const Spacer(flex: 3),
              const Column(
                children: [
                  Text(
                    '© 2026 Brgy. Balintawak Lipa City',
                    style: TextStyle(
                      color: Color(0xFF00796B),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'All rights reserved',
                    style: TextStyle(color: Color(0xFF00796B), fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String route,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(100), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, route),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: iconColor, size: 32),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF757575),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade300, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
