import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';

class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _licenseController = TextEditingController();
  final _phoneController = TextEditingController();
  final _truckController = TextEditingController();
  bool _isLoading = false;
  bool _obs1 = true;
  bool _obs2 = true;

  void _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final registerData = {
        'username': _usernameController.text.trim(),
        'name': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'role': 'driver',
        'phone': _phoneController.text.trim(),
        'license_number': _licenseController.text.trim(),
        'preferred_truck': _truckController.text.trim(),
      };

      final response = await ApiService().register(registerData);

      if (response.data['success'] == true) {
        try {
          await FirebaseDatabase.instance.ref('notifications').push().set({
            "type": "REGISTRATION",
            "title": "New Driver Registered",
            "message": "${_fullNameController.text} has joined as a driver.",
            "timestamp": ServerValue.timestamp,
            "isRead": false,
            "relatedId": _usernameController.text.trim(),
          });
        } catch (e) {
          debugPrint("Firebase Notification Error: $e");
        }

        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please wait for admin approval.'),
            duration: Duration(seconds: 3),
          ),
        );
        
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.data['message'] ?? 'Registration failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(235),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.white.withAlpha(100), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(15),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                              spreadRadius: -5,
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(Icons.lock_outline_rounded, 'Driver Credentials'),
                              const SizedBox(height: 8),
                              _buildInput(_usernameController, 'Username', 'Enter your username', icon: Icons.person_outline_rounded),
                              _buildInput(_emailController, 'Email Address', 'Enter your email', icon: Icons.email_outlined),
                              _buildInput(_passwordController, 'Password', 'Create a password', isPass: true, obs: _obs1, onToggle: () => setState(() => _obs1 = !_obs1), icon: Icons.lock_outline_rounded),
                              _buildInput(_confirmPasswordController, 'Confirm Password', 'Repeat your password', isPass: true, obs: _obs2, onToggle: () => setState(() => _obs2 = !_obs2), icon: Icons.lock_clock_outlined),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Divider(height: 1, color: Color(0x1F000000)),
                              ),

                              _buildSectionHeader(Icons.local_shipping_outlined, 'Work Information'),
                              const SizedBox(height: 8),
                              _buildInput(_fullNameController, 'Full Name', 'Enter your full name', icon: Icons.face_outlined),
                              _buildInput(_licenseController, 'License Number', 'Enter your license number', icon: Icons.badge_outlined),
                              _buildInput(_phoneController, 'Contact Number', 'Enter your phone number', icon: Icons.phone_android_outlined),
                              _buildInput(_truckController, 'Preferred Truck (Optional)', 'Enter truck assignment', action: TextInputAction.done, icon: Icons.local_shipping_outlined),

                              const SizedBox(height: 48),

                              _buildSubmitButton(),

                              const SizedBox(height: 16),
                              Center(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    "Back to Login",
                                    style: TextStyle(
                                      color: AppColors.textGray,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(150),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF00796B), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver',
                style: TextStyle(
                  color: AppColors.tealText,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              Text(
                'Registration Form',
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.tealText.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_shipping_rounded, color: AppColors.tealText, size: 28),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppColors.tealText, size: 22),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.tealText,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
    TextEditingController ctrl,
    String label,
    String hint, {
    IconData? icon,
    bool isPass = false,
    bool obs = false,
    VoidCallback? onToggle,
    TextInputAction action = TextInputAction.next,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.inputLabel,
              letterSpacing: 0.2,
            ),
          ),
        ),
        TextFormField(
          controller: ctrl,
          obscureText: obs,
          textInputAction: action,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel),
          onFieldSubmitted: (_) { if(action == TextInputAction.done) _submitRequest(); },
          validator: (value) {
            if (value == null || value.isEmpty) {
              if (label.contains('Optional')) return null;
              return 'Required';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15, fontWeight: FontWeight.w400),
            prefixIcon: icon != null ? Icon(icon, color: const Color(0xB400796B), size: 20) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            filled: true,
            fillColor: Colors.grey.shade50,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.tealText, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.redAccent, width: 2),
            ),
            suffixIcon: isPass
              ? IconButton(
                  icon: Icon(
                    obs ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                  onPressed: onToggle
                )
              : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _submitRequest,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: AppDecorations.loginButton,
          child: Container(
            width: double.infinity,
            height: 64,
            alignment: Alignment.center,
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text(
                    'Register as Driver',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
