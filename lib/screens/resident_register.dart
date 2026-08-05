import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';

class ResidentRegisterScreen extends StatefulWidget {
  const ResidentRegisterScreen({super.key});

  @override
  State<ResidentRegisterScreen> createState() => _ResidentRegisterScreenState();
}

class _ResidentRegisterScreenState extends State<ResidentRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String? _selectedPurok;
  bool _isLoading = false;
  bool _obs1 = true;
  bool _obs2 = true;

  final List<String> _puroks = ["Purok 2", "Purok 3", "Purok 4", "Dos Riles", "Sentro", "San Isidro", "Paraiso", "Riverside", "Kalaw Street", "Home Subdivision", "Tanco Road / Ayala Highway", "Brixton Area"];
  final ApiService _apiService = ApiService();

  void _handleRegister() async {
    if (!_formKey.currentState!.validate() || _selectedPurok == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a Purok')),
      );
      return;
    }

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
        'role': 'resident',
        'phone': _phoneController.text.trim(),
        'purok': _selectedPurok,
        'complete_address': _addressController.text.trim(),
      };

      final response = await _apiService.register(registerData);

      if (response.data['success'] == true) {
        try {
          await FirebaseDatabase.instance.ref('notifications').push().set({
            'type': 'REGISTRATION',
            'title': 'New Registration',
            'message': '${_fullNameController.text} has registered as a resident.',
            'timestamp': ServerValue.timestamp,
            'isRead': false,
            'relatedId': _usernameController.text
          });
        } catch (e) {
          debugPrint("Firebase Notification Error: $e");
        }

        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.data['message'] ?? 'Registration successful! Please wait for admin approval.'),
            duration: const Duration(seconds: 3),
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
                              _buildSectionHeader(Icons.lock_outline_rounded, 'Account Credentials'),
                              const SizedBox(height: 8),
                              _buildInput(_usernameController, 'Username', 'Enter your username', icon: Icons.person_outline_rounded),
                              _buildInput(_emailController, 'Email Address', 'Enter your email', icon: Icons.email_outlined),
                              _buildInput(_passwordController, 'Password', 'Create a password', isPass: true, obs: _obs1, onToggle: () => setState(() => _obs1 = !_obs1), icon: Icons.lock_outline_rounded),
                              _buildInput(_confirmPasswordController, 'Confirm Password', 'Repeat your password', isPass: true, obs: _obs2, onToggle: () => setState(() => _obs2 = !_obs2), icon: Icons.lock_clock_outlined),

                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Divider(height: 1, color: Color(0x1F000000)),
                              ),

                              _buildSectionHeader(Icons.badge_outlined, 'Personal Details'),
                              const SizedBox(height: 8),
                              _buildInput(_fullNameController, 'Full Name', 'Enter your full name', icon: Icons.face_outlined),
                              _buildInput(_phoneController, 'Contact Number', 'Enter your phone number', icon: Icons.phone_android_outlined),
                              _buildPurokDropdown(),
                              _buildInput(_addressController, 'Complete Address', 'Enter your home address', maxLines: 3, action: TextInputAction.done, icon: Icons.home_outlined),

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
                'Resident',
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
            child: const Icon(Icons.home_work_rounded, color: AppColors.tealText, size: 28),
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
    int maxLines = 1,
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
          maxLines: maxLines,
          textInputAction: action,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel),
          onFieldSubmitted: (_) { if(action == TextInputAction.done) _handleRegister(); },
          validator: (value) {
            if (value == null || value.isEmpty) return 'Required';
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

  Widget _buildPurokDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 24, left: 4, bottom: 8),
          child: Text(
            'Purok',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.inputLabel,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200, width: 1.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              value: _selectedPurok,
              validator: (value) => value == null ? 'Please select a Purok' : null,
              hint: const Text('Select your location', style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 15, fontWeight: FontWeight.w400)),
              isExpanded: true,
              icon: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.tealText, size: 24),
              ),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xB400796B), size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                border: InputBorder.none,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.tealText, width: 2),
                ),
                errorStyle: const TextStyle(height: 0),
              ),
              items: _puroks.map((p) => DropdownMenuItem(
                value: p,
                child: Text(p, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel))
              )).toList(),
              onChanged: (v) => setState(() => _selectedPurok = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _handleRegister,
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
                    'Submit Registration',
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
