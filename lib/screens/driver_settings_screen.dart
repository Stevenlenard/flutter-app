import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../api/api_service.dart';
import '../utils/custom_notification.dart';

class DriverSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const DriverSettingsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  final ApiService _apiService = ApiService();
  UserData? _user;
  bool _pushNotifications = true;

  // Controllers for password change
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // 🏛️ ORGANIZED HEADER
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
              child: Row(
                children: [
                  if (!widget.isEmbedded || widget.onBack != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 20),
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Configuration", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                    Text("Manage profile and vehicle details", style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontWeight: FontWeight.w600)),
                  ]),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  children: [
                    _buildSectionHeader("Duty Profile"),
                    _buildProfileCard(),

                    _buildSectionHeader("Notifications"),
                    _buildNotificationCard(),

                    _buildSectionHeader("Security & Data"),
                    _buildActionList([
                      _MenuOption("Change Account Password", Icons.lock_outline_rounded, () => _showChangePasswordModal(context)),
                      _MenuOption("Update Profile Details", Icons.badge_outlined, () => _showEditProfileModal(context)),
                    ]),

                    _buildSectionHeader("Driver Support"),
                    _buildActionList([
                      _MenuOption("Route FAQs", Icons.help_outline_rounded, () => _showFAQsModal(context)),
                      _MenuOption("Dispatch Line", Icons.support_agent_rounded, () => _showContactSupportModal(context)),
                      _MenuOption("Legal & Version", Icons.info_outline_rounded, () => _showAboutModal(context)),
                    ]),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                      child: ElevatedButton.icon(
                        onPressed: () => _showLogoutDialog(context),
                        icon: const Icon(Icons.logout_rounded, color: Colors.white),
                        label: const Text("Sign Out Safely", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), minimumSize: const Size(double.infinity, 64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 8, shadowColor: const Color(0xFF00BFA5).withAlpha(100)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUpdatePassword() async {
    final oldPass = _oldPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      CustomNotification.showTopNotification(context, "Please fill all password fields");
      return;
    }

    if (newPass != confirmPass) {
      CustomNotification.showTopNotification(context, "New passwords do not match");
      return;
    }

    setState(() => _isPasswordLoading = true);

    try {
      if (_user == null) return;

      final response = await _apiService.changePassword(
        _user!.userId,
        _user!.role,
        oldPass,
        newPass,
      );

      if (response.data['success'] == true) {
        if (mounted) {
          Navigator.pop(context);
          CustomNotification.showTopNotification(context, "Password updated successfully", false);
          _oldPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        }
      } else {
        if (mounted) {
          CustomNotification.showTopNotification(context, response.data['message'] ?? "Failed to update password");
        }
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "An error occurred: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isPasswordLoading = false);
      }
    }
  }

  // --- REFINED COMPONENTS ---

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.fromLTRB(28, 28, 24, 12), child: Align(alignment: Alignment.centerLeft, child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF9E9E9E), letterSpacing: 1.5))));
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(
        children: [
          _buildInfoRow("Full Name", _user?.name ?? "Driver", Icons.person_outline_rounded),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFF5F5F5))),
          _buildInfoRow("Assigned Truck", _user?.preferredTruck ?? "GT-001", Icons.local_shipping_outlined),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFF5F5F5))),
          _buildInfoRow("License No.", _user?.licenseNumber ?? "N/A", Icons.badge_outlined),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFF5F5F5))),
          _buildInfoRow("Contact No.", _user?.phone ?? "N/A", Icons.phone_android_rounded),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String val, IconData icon) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: const Color(0xFF00BFA5))),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A))),
      ])),
    ]);
  }

  Widget _buildNotificationCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.notifications_active_outlined, color: Color(0xFF00BFA5), size: 24)),
        const SizedBox(width: 20),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Duty Alerts", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1A1A1A))),
          Text("Receive route notifications", style: TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w500)),
        ])),
        Switch(value: _pushNotifications, onChanged: (v) => setState(() => _pushNotifications = v), activeColor: const Color(0xFF00BFA5)),
      ]),
    );
  }

  Widget _buildActionList(List<_MenuOption> options) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(children: options.map((opt) => Column(children: [
        InkWell(onTap: opt.onTap, borderRadius: BorderRadius.circular(24), child: Padding(padding: const EdgeInsets.all(24), child: Row(children: [
          Icon(opt.icon, size: 22, color: const Color(0xFF424242)),
          const SizedBox(width: 16),
          Expanded(child: Text(opt.title, style: const TextStyle(fontSize: 15, color: Color(0xFF424242), fontWeight: FontWeight.w700))),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFD1D1D1)),
        ]))),
        if (options.indexOf(opt) != options.length - 1) const Divider(height: 1, color: Color(0xFFF5F5F5), indent: 64, endIndent: 24),
      ])).toList()),
    );
  }

  // --- MODALS ---

  void _showChangePasswordModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
          insetPadding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_reset_rounded, color: Color(0xFF00BFA5), size: 28),
                      const SizedBox(width: 16),
                      const Text("Security Update", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text("Update your account password to ensure maximum security.", style: TextStyle(color: Color(0xFF757575), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 32),
                  _buildDialogInput("Current Password", true, controller: _oldPasswordController),
                  const SizedBox(height: 16),
                  _buildDialogInput("New Secure Password", true, controller: _newPasswordController),
                  const SizedBox(height: 16),
                  _buildDialogInput("Confirm New Password", true, controller: _confirmPasswordController),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isPasswordLoading ? null : _handleUpdatePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: _isPasswordLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("UPDATE PASSWORD", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _isPasswordLoading ? null : () => Navigator.pop(context),
                      child: const Text("CLOSE", style: TextStyle(color: Color(0xFFBDBDBD), fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditProfileModal(BuildContext context) {
    _showCustomDialog(context, Icons.manage_accounts_rounded, "Profile Sync", "Update your regional information and contact details.", [
      _buildDialogInput("Full Legal Name", false, val: _user?.name ?? "Driver"),
      const SizedBox(height: 16),
      _buildDialogInput("Mobile Connection", false, val: _user?.phone ?? "N/A"),
      const SizedBox(height: 16),
      _buildDialogInput("Assigned Truck", false, val: _user?.preferredTruck ?? "GT-001"),
    ], "SAVE CHANGES", const Color(0xFF00BFA5));
  }

  void _showFAQsModal(BuildContext context) {
    _showCustomDialog(context, Icons.quiz_rounded, "Duty Help", "Common questions regarding route management.", [
      _buildFAQ("Route Guidance?", "Your active route is updated in real-time on the Map tab based on collection status."),
      _buildFAQ("Marking Full?", "When the truck is at capacity, tap 'MARK FULL' to notify dispatch and residents."),
      _buildFAQ("GPS Issues?", "Ensure your device location services are high-accuracy and you have active data."),
    ], null, null);
  }

  void _showContactSupportModal(BuildContext context) {
    _showCustomDialog(context, Icons.support_agent_rounded, "Contact Dispatch", "Immediate assistance from our logistics team.", [
      _buildContactItem(Icons.phone_rounded, "+63 912 345 6789"),
      _buildContactItem(Icons.email_rounded, "dispatch@garbagetracker.com"),
    ], null, null);
  }

  void _showAboutModal(BuildContext context) {
    _showCustomDialog(context, Icons.info_outline_rounded, "About System", "Garbage Tracker Driver 1.0", [
      const Text("Efficiency-focused driver solution for automated waste collection tracking.", style: TextStyle(color: Color(0xFF616161), fontSize: 14, height: 1.6, fontWeight: FontWeight.w500)),
      const SizedBox(height: 24),
      const Center(child: Text("Version 1.0.4\n© 2026 Logistics Team", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
    ], null, null);
  }

  // --- MODAL UTILS ---

  void _showCustomDialog(BuildContext context, IconData icon, String title, String sub, List<Widget> body, String? btnText, Color? btnColor) {
    showDialog(context: context, builder: (context) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)), insetPadding: const EdgeInsets.all(24), child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: const Color(0xFF00BFA5), size: 28), const SizedBox(width: 16), Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)))]),
      const SizedBox(height: 12),
      Text(sub, style: const TextStyle(color: Color(0xFF757575), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
      const SizedBox(height: 32),
      ...body,
      if (btnText != null) ...[
        const SizedBox(height: 32),
        ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: btnColor, minimumSize: const Size(double.infinity, 64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0), child: Text(btnText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
      ],
      const SizedBox(height: 12),
      Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE", style: TextStyle(color: Color(0xFFBDBDBD), fontWeight: FontWeight.w900, letterSpacing: 1.2)))),
    ]))));
  }

  Widget _buildDialogInput(String label, bool isPass, {String? val, TextEditingController? controller}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF0F0F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          if (controller != null)
            TextField(
              controller: controller,
              obscureText: isPass,
              style: const TextStyle(fontSize: 15, color: Color(0xFF424242), fontWeight: FontWeight.w700),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
            )
          else
            Row(
              children: [
                Expanded(child: Text(val ?? (isPass ? "••••••••" : ""), style: const TextStyle(fontSize: 15, color: Color(0xFF424242), fontWeight: FontWeight.w700))),
                if (isPass) const Icon(Icons.visibility_off_rounded, size: 18, color: Colors.black12)
              ],
            )
        ],
      ),
    );
  }

  Widget _buildFAQ(String q, String a) {
    return Padding(padding: const EdgeInsets.only(bottom: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(q, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A))), const SizedBox(height: 8), Text(a, style: const TextStyle(fontSize: 13, color: Color(0xFF757575), height: 1.5))]));
  }

  Widget _buildContactItem(IconData icon, String val) {
    return Padding(padding: const EdgeInsets.only(bottom: 20), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF0F2F1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: const Color(0xFF00BFA5))), const SizedBox(width: 20), Text(val, style: const TextStyle(fontSize: 15, color: Color(0xFF424242), fontWeight: FontWeight.w700))]));
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => Dialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)), child: Padding(padding: const EdgeInsets.all(36), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFFFFF0F2), shape: BoxShape.circle), child: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF1744), size: 36)),
      const SizedBox(height: 28),
      const Text("Secure Sign Out?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 16),
      const Text("End your current duty session and sign out.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF757575), fontSize: 13, height: 1.5, fontWeight: FontWeight.w500)),
      const SizedBox(height: 36),
      ElevatedButton(onPressed: () async { await SessionManager.logout(); if (!mounted) return; Navigator.pushReplacementNamed(context, '/'); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), minimumSize: const Size(double.infinity, 64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0), child: const Text("SIGN OUT", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1))),
      const SizedBox(height: 16),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Color(0xFFBDBDBD), fontWeight: FontWeight.w900, letterSpacing: 1.2))),
    ]))));
  }
}

class _MenuOption {
  final String title; final IconData icon; final VoidCallback onTap;
  _MenuOption(this.title, this.icon, this.onTap);
}
