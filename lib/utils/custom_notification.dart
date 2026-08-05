import 'package:flutter/material.dart';

class CustomNotification {
  static void showTopNotification(BuildContext context, String message, [bool isError = true]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }
}
