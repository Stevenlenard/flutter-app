import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../api/api_service.dart';
import '../api/api_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();

  int _currentStep = 1; // 1: Email, 2: OTP, 3: New Password
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppDecorations.loginBackground,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        _buildHeader(),
                        const Spacer(flex: 1),
                        _buildLogo(),
                        const SizedBox(height: 32),
                        _buildTitle(),
                        const SizedBox(height: 8),
                        _buildSubtitle(),
                        const SizedBox(height: 48),

                        _buildMainCard(),

                        const Spacer(flex: 2),
                        _buildFooter(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
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
              onPressed: () {
                if (_currentStep > 1) {
                  setState(() => _currentStep--);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentStep == 1 ? 'Verification' : (_currentStep == 2 ? 'Enter Token' : 'New Password'),
                style: const TextStyle(
                  color: AppColors.tealText,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const Text(
                'Account Recovery',
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    IconData icon = Icons.lock_reset_rounded;
    if (_currentStep == 2) icon = Icons.vibration_rounded;
    if (_currentStep == 3) icon = Icons.security_rounded;

    return Container(
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
      child: Icon(icon, size: 54, color: Colors.white),
    );
  }

  Widget _buildTitle() {
    String title = 'Reset Password';
    if (_currentStep == 2) title = 'Verify Token';
    if (_currentStep == 3) title = 'Create New';

    return Text(
      title,
      style: const TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w900,
        color: AppColors.tealText,
        letterSpacing: -1.5,
      ),
    );
  }

  Widget _buildSubtitle() {
    String sub = 'Step 1 of 3: Verify your identity';
    if (_currentStep == 2) sub = 'Step 2 of 3: Enter the 6-digit code';
    if (_currentStep == 3) sub = 'Step 3 of 3: Secure your account';

    return Text(
      sub,
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.textGray,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMainCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
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
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentStep == 1) _buildStep1Fields(),
            if (_currentStep == 2) _buildStep2Fields(),
            if (_currentStep == 3) _buildStep3Fields(),
            const SizedBox(height: 40),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Email Address',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.inputLabel),
          ),
        ),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel),
          decoration: _inputDecoration('Enter your registered email', Icons.email_outlined),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter your email';
            final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
            if (!emailRegex.hasMatch(value)) return 'Please enter a valid email format';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStep2Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Verification Token',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.inputLabel),
          ),
        ),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.tealText, letterSpacing: 8),
          decoration: _inputDecoration('000000', Icons.vpn_key_outlined).copyWith(counterText: ""),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter the code';
            if (value.length < 6) return 'Enter all 6 digits';
            return null;
          },
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            "Code sent to: ${_emailController.text}",
            style: const TextStyle(fontSize: 12, color: AppColors.textGray, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'New Password',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.inputLabel),
          ),
        ),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel),
          decoration: _inputDecoration('Enter new password', Icons.lock_outline_rounded).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey, size: 20),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter a password';
            if (value.length < 6) return 'Minimum 6 characters required';
            return null;
          },
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Confirm Password',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.inputLabel),
          ),
        ),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscurePassword,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel),
          decoration: _inputDecoration('Confirm your password', Icons.lock_clock_outlined),
          validator: (value) {
            if (value != _passwordController.text) return 'Passwords do not match';
            return null;
          },
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15, fontWeight: FontWeight.w400),
      prefixIcon: Icon(icon, color: const Color(0xB400796B), size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      filled: true,
      fillColor: Colors.grey.shade50,
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.tealText, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
    );
  }

  Widget _buildSubmitButton() {
    String text = 'Send Verification';
    if (_currentStep == 2) text = 'Verify Token';
    if (_currentStep == 3) text = 'Reset Password';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _handleAction,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: AppDecorations.loginButton,
          child: Container(
            width: double.infinity,
            height: 64,
            alignment: Alignment.center,
            child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ),
        ),
      ),
    );
  }

  void _handleAction() {
    if (!_formKey.currentState!.validate()) return;
    if (_currentStep == 1) _sendEmail();
    else if (_currentStep == 2) _verifyOTP();
    else if (_currentStep == 3) _resetPassword();
  }

  void _sendEmail() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.forgotPassword(_emailController.text.trim());
      if (response.data['success'] == true) {
        _showSuccess(response.data['message'] ?? 'OTP sent to your email');
        setState(() => _currentStep = 2);
      } else {
        _showError(response.data['message'] ?? 'Email not found');
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _verifyOTP() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.verifyOTP(_emailController.text.trim(), _otpController.text.trim());
      if (response.data['success'] == true) {
        _showSuccess(response.data['message'] ?? 'OTP Verified');
        setState(() => _currentStep = 3);
      } else {
        _showError(response.data['message'] ?? 'Invalid OTP');
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetPassword() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.resetPassword(
        _emailController.text.trim(),
        _otpController.text.trim(),
        _passwordController.text,
      );
      if (response.data['success'] == true) {
        _showSuccess('Password updated successfully! Please login.');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        _showError(response.data['message'] ?? 'Failed to reset password');
      }
    } catch (e) {
      _showConnectionError();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  void _showConnectionError() {
    if (!mounted) return;
    const url = ApiClient.baseUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connection Error to $url. Check if XAMPP is running and the folder name in htdocs is correct.'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 8),
      ),
    );
  }

  Widget _buildFooter() {
    return const Column(
      children: [
        Text('© 2026 Brgy. Balintawak Lipa City', style: TextStyle(color: Color(0xFF00796B), fontSize: 13, fontWeight: FontWeight.bold)),
        Text('All rights reserved', style: TextStyle(color: Color(0xFF00796B), fontSize: 11)),
      ],
    );
  }
}
