import 'package:flutter/material.dart';

class AppColors {
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color secondaryBlue = Color(0xFF1976D2);
  static const Color accentBlue = Color(0xFFE3F2FD);
  
  static const Color loginGradientStart = Color(0xFFE0F2F1);
  static const Color loginGradientEnd = Color(0xFFB2DFDB);
  
  static const Color loginButtonStart = Color(0xFF00897B);
  static const Color loginButtonEnd = Color(0xFF00796B);
  
  static const Color tealText = Color(0xFF00796B);
  static const Color tealLink = Color(0xFF00897B);
  
  static const Color emeraldGreen = Color(0xFF2E7D32);
  static const Color emeraldLight = Color(0xFFC8E6C9);
  
  static const Color dashboardGradientStart = Color(0xFF64E0C0);
  static const Color dashboardGradientEnd = Color(0xFF64E0C0);
  
  static const Color cardGreenBg = Color(0xFFEDF9F0);
  static const Color cardRedBg = Color(0xFFFFF0F2);
  static const Color cardBlueBg = Color(0xFFF1F8FE);
  static const Color cardYellowBg = Color(0xFFFFFDF1);
  
  static const Color statusGreen = Color(0xFF00C853);
  static const Color statusRed = Color(0xFFFF1744);
  static const Color statusYellow = Color(0xFFFFAB00);
  
  static const Color textGray = Color(0xFF666666);
  static const Color lightGray = Color(0xFFE0E0E0);
  static const Color inputHint = Color(0xFF555555);
  static const Color inputLabel = Color(0xFF333333);

  static const Color residentIcon = Color(0xFF2196F3);
  static const Color driverIcon = Color(0xFF4CAF50);
  static const Color residentBg = Color(0xFFE3F2FD);
  static const Color driverBg = Color(0xFFE8F5E9);
}

class AppDecorations {
  static const BoxDecoration loginBackground = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFE0F7FA),
        Color(0xFFB2DFDB),
        Color(0xFF80CBC4),
      ],
    ),
  );

  static BoxDecoration inputDecoration = BoxDecoration(
    color: const Color(0xFFF5F5F5),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
  );

  static const BoxDecoration dashboardHeader = BoxDecoration(
    color: AppColors.dashboardGradientStart,
  );

  static BoxDecoration loginButton = BoxDecoration(
    gradient: const LinearGradient(
      colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd],
    ),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: AppColors.loginButtonEnd.withAlpha(80),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );

  static BoxDecoration cardDecoration({Color? color, double radius = 20}) {
    return BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(15),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
