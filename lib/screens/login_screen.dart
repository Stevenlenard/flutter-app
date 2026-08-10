import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../api/api_client.dart';
import '../utils/session_manager.dart';
import '../utils/app_theme.dart';
import '../utils/system_logger.dart';
import '../utils/login_security_manager.dart';
import '../widgets/legal_agreement_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  final ApiService _apiService = ApiService();

  // Security & Lockout State
  SecurityStatus? _securityStatus;
  Timer? _lockoutTimer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _checkInitialSecurity();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _checkInitialSecurity() async {
    // We'll check security whenever username changes or on button press
    // For now, let's just initialize
  }

  void _startLockoutCountdown(DateTime lockoutUntil) {
    _lockoutTimer?.cancel();
    void updateTimer() {
      final now = DateTime.now();
      final diff = lockoutUntil.difference(now);
      if (diff.isNegative) {
        setState(() {
          _secondsRemaining = 0;
          _securityStatus = SecurityStatus(attempts: 0, isLocked: false);
        });
        _lockoutTimer?.cancel();
      } else {
        setState(() {
          _secondsRemaining = diff.inSeconds;
        });
      }
    }
    updateTimer();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) => updateTimer());
  }

  void _handleLogin() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your username')));
      return;
    }

    // 1. Check Security Status first
    final status = await LoginSecurityManager.checkStatus(username);
    if (status.isLocked) {
      setState(() => _securityStatus = status);
      _startLockoutCountdown(status.lockoutUntil!);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      debugPrint("Connecting to: ${ApiClient.baseUrl}");
      final response = await _apiService.login(username, password);
      final data = response.data;
      
      debugPrint("Login Response: $data");

      if (data is Map && data['success'] == true) {
        // Reset security on success
        await LoginSecurityManager.resetAttempts(username);

        final user = data['user'];
        if (user == null || user is! Map) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid user data received from server')),
          );
          return;
        }

        if (data['message'].toString().toUpperCase().contains('2FA_REQUIRED')) {
          if (!mounted) return;
          Navigator.pushNamed(context, '/verify_2fa', arguments: user);
          return;
        }

        await SessionManager.saveUser(Map<String, dynamic>.from(user));
        await SystemLogger.logEvent("LOGIN", "Successful login from ${user['name'] ?? 'Admin'}");

        if (!mounted) return;

        String role = user['role'].toString().toLowerCase();
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin_dashboard');
        } else if (role == 'resident') {
          Navigator.pushReplacementNamed(context, '/resident_dashboard');
        } else if (role == 'driver') {
          Navigator.pushReplacementNamed(context, '/driver_dashboard');
        }
      } else {
        // Record failed attempt
        final newStatus = await LoginSecurityManager.recordFailedAttempt(username);
        setState(() {
          _securityStatus = newStatus;
        });

        if (newStatus.isLocked) {
          _startLockoutCountdown(newStatus.lockoutUntil!);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const Spacer(flex: 3),
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 500),
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                  child: const Icon(Icons.local_shipping_rounded, size: 54, color: Colors.white),
                                ),
                                const SizedBox(height: 32),
                                const Text(
                                  'Garbage Tracker',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.tealText,
                                    letterSpacing: -1.5,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Brgy. Balintawak, Lipa City',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textGray,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 48),

                                // Username Field
                                _buildRefinedTextField(
                                  label: 'Username',
                                  hint: 'Enter your username',
                                  controller: _usernameController,
                                  icon: Icons.person_outline_rounded,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your username';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),

                                // Password Field
                                _buildRefinedTextField(
                                  label: 'Password',
                                  hint: 'Enter your password',
                                  controller: _passwordController,
                                  isPassword: true,
                                  obscureText: _obscurePassword,
                                  icon: Icons.lock_outline_rounded,
                                  onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your password';
                                    }
                                    if (value.length < 6) {
                                      return 'Password must be at least 6 characters';
                                    }
                                    return null;
                                  },
                                ),

                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.pushNamed(context, '/forgot_password'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.tealLink,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // FAILED ATTEMPTS WARNING
                                if (_securityStatus != null && _securityStatus!.attempts > 0 && !_securityStatus!.isLocked)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.orange.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Incorrect email or password. You have ${_securityStatus!.remainingAttempts} attempts remaining.',
                                            style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                if (_securityStatus?.isLocked == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 20),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.red.shade200),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.lock_clock_rounded, color: Colors.red.shade900, size: 20),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Too many failed login attempts.',
                                                style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Login is temporarily disabled for 1 minute.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.red.shade900, fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Try again in: ${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            color: Colors.red.shade900,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextButton.icon(
                                          onPressed: () => Navigator.pushNamed(context, '/forgot_password'),
                                          icon: const Icon(Icons.refresh_rounded, size: 18),
                                          label: const Text('Reset your password'),
                                          style: TextButton.styleFrom(foregroundColor: Colors.red.shade900),
                                        ),
                                      ],
                                    ),
                                  ),

                                const SizedBox(height: 20),

                                _buildAnimatedLoginButton(),

                                const SizedBox(height: 32),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Don't have an account? ",
                                      style: TextStyle(color: AppColors.textGray, fontSize: 14),
                                    ),
                                    GestureDetector(
                                      onTap: () => Navigator.pushNamed(context, '/register'),
                                      child: const Text(
                                        'Create Account',
                                        style: TextStyle(
                                          color: AppColors.tealLink,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                children: [
                                  GestureDetector(
                                    onTap: () => LegalAgreementDialog.show(context, isTerms: true),
                                    child: const Text(
                                      'Terms & Conditions',
                                      style: TextStyle(
                                        color: AppColors.tealLink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  const Text('•', style: TextStyle(color: AppColors.textGray)),
                                  GestureDetector(
                                    onTap: () => LegalAgreementDialog.show(context, isTerms: false),
                                    child: const Text(
                                      'Privacy Policy',
                                      style: TextStyle(
                                        color: AppColors.tealLink,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '© 2026 Brgy. Balintawak Lipa City',
                                style: TextStyle(
                                  color: Color(0xFF00796B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'All rights reserved',
                                style: TextStyle(color: Color(0xFF00796B), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRefinedTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    IconData? icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.inputLabel,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: isPassword ? obscureText : false,
          validator: validator,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inputLabel),
          textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: (_) {
            if (isPassword) {
              _handleLogin();
            }
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15, fontWeight: FontWeight.w400),
            prefixIcon: icon != null ? Icon(icon, color: AppColors.tealText.withAlpha(180), size: 22) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: onTogglePassword,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  double _buttonScale = 1.0;

  Widget _buildAnimatedLoginButton() {
    bool isLocked = _securityStatus?.isLocked == true;
    return GestureDetector(
      onTapDown: isLocked ? null : (_) => setState(() => _buttonScale = 0.95),
      onTapUp: isLocked ? null : (_) => setState(() => _buttonScale = 1.0),
      onTapCancel: isLocked ? null : () => setState(() => _buttonScale = 1.0),
      onTap: (_isLoading || isLocked) ? null : _handleLogin,
      child: AnimatedScale(
        scale: _buttonScale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: isLocked
              ? AppDecorations.loginButton.copyWith(
                  gradient: LinearGradient(
                    colors: [Colors.grey.shade400, Colors.grey.shade500],
                  ),
                  boxShadow: [],
                )
              : AppDecorations.loginButton,
          alignment: Alignment.center,
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Text(
                  isLocked ? 'Locked' : 'Sign In',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
