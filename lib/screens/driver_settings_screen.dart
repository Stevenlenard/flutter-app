import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../api/api_service.dart';
import '../utils/custom_notification.dart';

class DriverSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  final String? currentSessionId;

  const DriverSettingsScreen({
    super.key, 
    this.isEmbedded = false, 
    this.onBack,
    this.currentSessionId,
  });

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  UserData? _user;
  
  bool _isNavigating = false;

  // Settings values
  bool _dutyAlerts = true;
  bool _collectionNotifications = true;
  bool _maintenanceNotifications = true;
  bool _emergencyAlerts = true;
  
  // Device/App info
  String _gpsAccuracy = "Checking...";
  final String _appVersion = "1.0.0 Driver";

  // Controllers for edit profile
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  // Controllers for password change
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadSettings();
    _startGpsMonitor();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      _nameController.text = _user!.name;
      _phoneController.text = _user!.phone ?? "";
      _emailController.text = _user!.email;
      _addressController.text = _user!.completeAddress ?? "";
    }
    if (mounted) setState(() {});
  }

  void _loadSettings() async {
    if (_user == null) return;
    
    final ref = _database.ref('driver_settings/${_user!.userId}');
    final snapshot = await ref.get();
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      setState(() {
        _dutyAlerts = data['dutyAlerts'] ?? true;
        _collectionNotifications = data['collectionNotifications'] ?? true;
        _maintenanceNotifications = data['maintenanceNotifications'] ?? true;
        _emergencyAlerts = data['emergencyAlerts'] ?? true;
      });
    } else {
      // Initialize with default values
      await ref.set({
        'dutyAlerts': true,
        'collectionNotifications': true,
        'maintenanceNotifications': true,
        'emergencyAlerts': true,
        'lastUpdated': ServerValue.timestamp,
      });
    }
  }

  void _startGpsMonitor() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      if (mounted) {
        setState(() {
          _gpsAccuracy = "±${position.accuracy.toStringAsFixed(1)} meters";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _gpsAccuracy = "GPS Disabled");
    }
  }

  Future<void> _updateSettings(String key, bool value) async {
    if (_user == null) return;
    
    String label = "";
    if (key == 'dutyAlerts') label = "Duty Alerts";
    else if (key == 'collectionNotifications') label = "Collection Notifications";
    else if (key == 'maintenanceNotifications') label = "Maintenance Notifications";
    else if (key == 'emergencyAlerts') label = "Emergency Alerts";

    try {
      await _database.ref('driver_settings/${_user!.userId}').update({
        key: value,
        'lastUpdated': ServerValue.timestamp,
      });

      if (mounted) {
        setState(() {
          if (key == 'dutyAlerts') _dutyAlerts = value;
          else if (key == 'collectionNotifications') _collectionNotifications = value;
          else if (key == 'maintenanceNotifications') _maintenanceNotifications = value;
          else if (key == 'emergencyAlerts') _emergencyAlerts = value;
        });
        CustomNotification.showTopNotification(context, "$label ${value ? 'enabled' : 'disabled'} successfully.", false);
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.showTopNotification(context, "Failed to update $label. Try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 20),
                    _buildRouteManagement(),
                    const SizedBox(height: 20),
                    _buildTruckInformation(),
                    const SizedBox(height: 20),
                    _buildNotificationsSection(),
                    const SizedBox(height: 20),
                    _buildAppInformation(),
                    const SizedBox(height: 30),
                    _buildLogoutButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Driver Settings",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -0.5
                ),
              ),
              Text(
                "Manage preferences",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500
                ),
              ),
            ],
          ),
          if (widget.onBack != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: widget.onBack,
            )
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10)
          )
        ],
        border: Border.all(color: Colors.grey.shade100)
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 18, color: Colors.black),
              const SizedBox(width: 8),
              const Text(
                "Driver Profile",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildProfileField(
            icon: Icons.person,
            label: "Full Name",
            value: _user?.name ?? "Loading...",
            onTap: () => _showEditProfileModal(),
          ),
          const SizedBox(height: 12),
          _buildProfileField(
            icon: Icons.phone,
            label: "Contact Number",
            value: _user?.phone ?? "Not set",
            onTap: () => _showEditProfileModal(),
          ),
          const SizedBox(height: 12),
          _buildProfileField(
            icon: Icons.local_shipping,
            label: "Assigned Truck",
            value: _user?.preferredTruck ?? "None",
            onTap: null,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileField({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade400, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF2C3E50)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteManagement() {
    return _buildSectionCard(
      icon: Icons.location_on,
      title: "Route Management",
      children: [
        _buildMenuAction("View Daily Routes", () => _showDailyRoutes()),
        _buildDivider(),
        _buildMenuAction("Performance Stats", () => _showPerformanceStats()),
      ],
    );
  }

  Widget _buildTruckInformation() {
    return _buildSectionCard(
      icon: Icons.local_shipping,
      title: "Truck Information",
      children: [
        _buildMenuAction("Truck Details", () => _showTruckDetails()),
        _buildDivider(),
        _buildMenuAction("Maintenance Schedule", () => _showMaintenanceSchedule()),
        _buildDivider(),
        _buildMenuAction("Report Issue", () => _showReportIssue()),
        _buildDivider(),
        _buildMenuAction("Issue History", () => _showIssueHistory()),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return _buildSectionCard(
      icon: Icons.notifications,
      title: "Notifications",
      children: [
        _buildMenuAction("Notification Preferences", () => _showNotificationPreferences()),
        _buildDivider(),
        _buildMenuAction("Alert History", () => _showAlertHistory()),
      ],
    );
  }

  Widget _buildAppInformation() {
    return _buildSectionCard(
      icon: Icons.info_outline,
      title: "App Information",
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _buildInfoRow("Version", _appVersion),
        const SizedBox(height: 16),
        _buildInfoRow("GPS Accuracy", _gpsAccuracy, valueColor: AppColors.statusGreen),
        const SizedBox(height: 16),
        _buildInfoRow("Last Updated", "April 2026"),
        const SizedBox(height: 16),
        _buildMenuAction("Security (Change Password)", () => _showChangePasswordModal(), showIcon: false, padding: EdgeInsets.zero),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 15)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: valueColor ?? const Color(0xFF2C3E50))),
      ],
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    EdgeInsets? padding
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
        border: Border.all(color: Colors.grey.shade100)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Colors.black),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
          ),
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuAction(String title, VoidCallback onTap, {bool showIcon = true, EdgeInsets? padding}) {
    return InkWell(
      onTap: () {
        if (_isNavigating) return;
        onTap();
      },
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
            if (showIcon) Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.grey.shade100, indent: 24, endIndent: 24);
  }

  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.tealText.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))]
      ),
      child: ElevatedButton(
        onPressed: () => _showLogoutDialog(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.tealText,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout, size: 20),
            SizedBox(width: 12),
            Text("Logout", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  // --- TRUCK INFORMATION METHODS ---

  void _showTruckDetails() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final truckId = _user?.preferredTruck ?? "GT-001";
      final ref = _database.ref('trucks/$truckId');
      final snapshot = await ref.get();
      
      Map<String, dynamic> truckData = {};
      if (snapshot.exists) {
        truckData = Map<String, dynamic>.from(snapshot.value as Map);
      }

      final idCtrl = TextEditingController(text: truckId);
      final plateCtrl = TextEditingController(text: truckData['plateNumber'] ?? "");
      final modelCtrl = TextEditingController(text: truckData['model'] ?? "");
      final fuelCtrl = TextEditingController(text: truckData['fuelType'] ?? "");
      final capacityCtrl = TextEditingController(text: truckData['capacity'] ?? "");

      if (!context.mounted) return;

      _showModal("Truck Details", [
        _buildInput("Truck ID", idCtrl),
        _buildInput("Plate Number", plateCtrl),
        _buildInput("Model", modelCtrl),
        _buildInput("Fuel Type", fuelCtrl),
        _buildInput("Capacity (e.g. 10 Tons)", capacityCtrl),
      ], "SAVE CHANGES", () async {
        if (plateCtrl.text.isEmpty || modelCtrl.text.isEmpty) {
          CustomNotification.showTopNotification(context, "Please fill required fields");
          return;
        }
        
        await ref.update({
          'plateNumber': plateCtrl.text,
          'model': modelCtrl.text,
          'fuelType': fuelCtrl.text,
          'capacity': capacityCtrl.text,
          'lastUpdatedBy': _user?.userId,
          'updatedAt': ServerValue.timestamp,
        });
        
        if (mounted) Navigator.pop(context);
        CustomNotification.showTopNotification(context, "Truck details updated successfully.", false);
      });
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _initializeMaintenanceIfNeeded(String truckId) async {
    final ref = _database.ref('trucks/$truckId');
    final snapshot = await ref.get();
    
    bool needsInit = true;
    if (snapshot.exists) {
      final data = snapshot.value as Map;
      if (data.containsKey('maintenance')) {
        needsInit = false;
      }
    }

    if (needsInit) {
      await ref.update({
        'odometerKm': 0.0,
        'maintenance': {
          'oilChange': {
            'intervalKm': 5000.0,
            'remainingKm': 5000.0,
            'lastServiceAt': null,
            'status': "NORMAL"
          },
          'tireRotation': {
            'intervalKm': 10000.0,
            'remainingKm': 10000.0,
            'lastServiceAt': null,
            'status': "NORMAL"
          },
          'fullInspection': {
            'intervalKm': 20000.0,
            'remainingKm': 20000.0,
            'lastServiceAt': null,
            'status': "NORMAL"
          }
        }
      });
    }
  }

  void _showMaintenanceSchedule() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final truckId = _user?.preferredTruck ?? "GT-001";
      await _initializeMaintenanceIfNeeded(truckId);

      if (!context.mounted) return;

      _showModal("Maintenance Schedule", [
        const Text("Upcoming truck service dates", style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 20),
        StreamBuilder(
          stream: _database.ref('trucks/$truckId/maintenance').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final Map data = snapshot.data!.snapshot.value as Map;
            
            return Column(
              children: [
                _buildMaintenanceItem("Next Oil Change", data['oilChange']),
                const SizedBox(height: 12),
                _buildMaintenanceItem("Tire Rotation", data['tireRotation']),
                const SizedBox(height: 12),
                _buildMaintenanceItem("Full Inspection", data['fullInspection']),
              ],
            );
          },
        )
      ], "DONE", () async => Navigator.pop(context));
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Widget _buildMaintenanceItem(String title, dynamic item) {
    if (item == null) return const SizedBox.shrink();
    
    double remaining = (item['remainingKm'] ?? 0.0).toDouble();
    if (remaining < 0) remaining = 0.0;
    
    String status = (item['status'] ?? "NORMAL").toString();
    
    Color statusColor = Colors.green;
    if (status == "DUE SOON") statusColor = Colors.orange;
    if (status == "OVERDUE") statusColor = Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.2))
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text("Remaining: ${remaining.toStringAsFixed(1)} km", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10)),
          )
        ],
      ),
    );
  }

  void _showReportIssue() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final descCtrl = TextEditingController();
      String urgency = "Medium";
      String issueType = "Engine";

      _showModal("Report Truck Issue", [
        const Text("Describe any mechanical or technical problems", style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          value: issueType,
          items: ["Engine", "Tires", "Brakes", "GPS", "Electrical", "Fuel", "Transmission", "Hydraulic System", "Body Damage", "Other"]
              .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => issueType = v!,
          decoration: _inputDecoration("Issue Type"),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: urgency,
          items: ["Low", "Medium", "High", "Critical"]
              .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => urgency = v!,
          decoration: _inputDecoration("Urgency Level"),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: descCtrl,
          maxLines: 4,
          decoration: _inputDecoration("Brief Description"),
        ),
      ], "Submit Report", () async {
        final description = descCtrl.text.trim();
        if (description.isEmpty) {
          CustomNotification.showTopNotification(context, "Please complete all required fields.");
          return;
        }

        try {
          Position pos = await Geolocator.getCurrentPosition();
          final truckId = _user?.preferredTruck ?? "GT-001";
          
          await _database.ref('truck_issues').push().set({
            'driverId': _user?.userId,
            'driverName': _user?.name,
            'truckId': truckId,
            'issueType': issueType,
            'description': description,
            'urgency': urgency,
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'createdAt': ServerValue.timestamp,
            'updatedAt': ServerValue.timestamp,
            'status': 'PENDING', // Changed from SUBMITTED to PENDING
            'isReadByDriver': false,
            'isReadByAdmin': false,
          });

          if (mounted) {
            Navigator.pop(context);
            CustomNotification.showTopNotification(context, "Truck issue reported successfully.", false);
          }
        } catch (e) {
          CustomNotification.showTopNotification(context, "Submission failed. Please try again.");
        }
      });
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showIssueHistory() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showModal("Issue History", [
        StreamBuilder(
          stream: _database.ref('truck_issues').orderByChild('driverId').equalTo(_user?.userId).onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No previous reports.")));
            }
            
            final Map data = snapshot.data!.snapshot.value as Map;
            final List issues = [];
            data.forEach((k, v) => issues.add({...v as Map, 'id': k}));
            issues.sort((a, b) => (b['createdAt'] ?? 0).compareTo(a['createdAt'] ?? 0));

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: issues.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final issue = issues[i];
                String status = (issue['status'] ?? "PENDING").toString().toUpperCase().replaceAll('_', ' ');
                Color statusColor = Colors.orange;
                if (status == "IN PROGRESS") statusColor = Colors.blue;
                if (status == "RESOLVED") statusColor = Colors.green;
                if (status == "REJECTED") statusColor = Colors.red;

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA), 
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade100)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (issue['issueType'] ?? "Issue").toString().toUpperCase(), 
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.grey, letterSpacing: 1.1)
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        issue['description'] ?? "", 
                        style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50), fontWeight: FontWeight.w600)
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch(issue['createdAt'] ?? 0)),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (issue['adminResponse'] != null && issue['adminResponse'].toString().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white, 
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200)
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("ADMIN RESPONSE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
                              const SizedBox(height: 6),
                              Text(
                                issue['adminResponse'], 
                                style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500, height: 1.4)
                              ),
                            ],
                          ),
                        )
                      ],
                    ],
                  ),
                );
              },
            );
          },
        )
      ], null, null);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  // --- OTHER MENU MODALS ---

  void _showEditProfileModal() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    
    try {
      _showModal("Edit Profile", [
        _buildInput("Full Legal Name", _nameController),
        _buildInput("Contact Number", _phoneController),
        _buildInput("Email Address", _emailController),
        _buildInput("Complete Address", _addressController),
      ], "SAVE CHANGES", () async {
        await _handleUpdateProfile();
      });
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showChangePasswordModal() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showModal("Change Password", [
        _buildInput("Current Password", _oldPasswordController, isPassword: true),
        _buildInput("New Password", _newPasswordController, isPassword: true),
        _buildInput("Confirm New Password", _confirmPasswordController, isPassword: true),
      ], "UPDATE PASSWORD", () async {
        await _handleUpdatePassword();
      });
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showNotificationPreferences() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showModal("Notification Preferences", [
        StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              children: [
                _buildToggle("Duty Alerts", _dutyAlerts, (v) async {
                  await _updateSettings('dutyAlerts', v);
                  setModalState(() {});
                }),
                _buildToggle("Collection Notifications", _collectionNotifications, (v) async {
                  await _updateSettings('collectionNotifications', v);
                  setModalState(() {});
                }),
                _buildToggle("Maintenance Notifications", _maintenanceNotifications, (v) async {
                  await _updateSettings('maintenanceNotifications', v);
                  setModalState(() {});
                }),
                _buildToggle("Emergency Alerts", _emergencyAlerts, (v) async {
                  await _updateSettings('emergencyAlerts', v);
                  setModalState(() {});
                }),
              ],
            );
          }
        ),
      ], null, null);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showDailyRoutes() async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      if (widget.currentSessionId == null) {
        _showModal("Today's Daily Routes", [const Center(child: Text("No active session tracked."))], null, null);
        return;
      }

      _showModal("Today's Daily Routes", [
        StreamBuilder(
          stream: _database.ref('collection_progress/${widget.currentSessionId}').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
            }
            final Map data = snapshot.data!.snapshot.value as Map;
            final List routes = [];
            data.forEach((k, v) => routes.add(v));
            routes.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
            
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: routes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = routes[i];
                bool completed = r['completed'] == true;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: completed ? Colors.green.shade50 : const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Icon(completed ? Icons.check_circle : Icons.location_on, color: completed ? Colors.green : Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(child: Text(r['name'] ?? "", style: TextStyle(fontWeight: FontWeight.w700, color: completed ? Colors.green.shade900 : Colors.black87))),
                    ],
                  ),
                );
              },
            );
          },
        )
      ], null, null);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showPerformanceStats() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      final truckId = _user?.preferredTruck ?? "GT-001";
      _showModal("Performance Stats", [
        StreamBuilder(
          stream: _database.ref('truck_locations/$truckId').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final Map data = snapshot.data!.snapshot.value as Map;
            return Column(
              children: [
                _buildInfoRow("Collection Efficiency", "${(data['efficiency'] ?? 0.0).toStringAsFixed(1)}%", valueColor: AppColors.statusGreen),
                const SizedBox(height: 16),
                _buildInfoRow("Average Speed", "${(data['avg_speed'] ?? 0.0).toStringAsFixed(1)} km/h"),
                const SizedBox(height: 16),
                _buildInfoRow("Distance Covered", "${(data['distance'] ?? 0.0).toStringAsFixed(2)} km"),
              ],
            );
          }
        ),
      ], null, null);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  void _showAlertHistory() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    try {
      _showModal("Alert History", [
        StreamBuilder(
          stream: _database.ref('notifications').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text("Error: ${snapshot.error}");
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: Text("No alerts found."));
            }
            final Map data = snapshot.data!.snapshot.value as Map;
            final List alerts = [];
            data.forEach((k, v) { if (v['truck_id'] == _user?.preferredTruck) alerts.add(v); });
            alerts.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = alerts[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a['title'] ?? "Alert", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(a['message'] ?? "", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                );
              },
            );
          },
        )
      ], null, null);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  // --- HANDLERS ---

  Future<void> _handleUpdateProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (name.isEmpty) return;

    try {
      final res = await _apiService.updateProfile(
        userId: _user!.userId,
        role: _user!.role,
        name: name,
        phone: phone,
        address: _addressController.text.trim(),
        email: _emailController.text.trim(),
      );

      if (res.data['success'] == true) {
        final updatedUser = res.data['user'];
        await SessionManager.saveUser(Map<String, dynamic>.from(updatedUser));
        _loadUser();
        if (mounted) Navigator.pop(context);
        CustomNotification.showTopNotification(context, "Profile updated successfully.", false);
      }
    } catch (e) {
      CustomNotification.showTopNotification(context, "Update failed: $e");
    }
  }

  Future<void> _handleUpdatePassword() async {
    final oldPass = _oldPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();
    if (newPass.length < 6) {
      CustomNotification.showTopNotification(context, "Password too short."); return;
    }
    if (newPass != confirmPass) {
      CustomNotification.showTopNotification(context, "Passwords do not match."); return;
    }
    try {
      final res = await _apiService.changePassword(_user!.userId, _user!.role, oldPass, newPass);
      if (res.data['success'] == true) {
        if (mounted) Navigator.pop(context);
        CustomNotification.showTopNotification(context, "Password changed successfully.", false);
      } else {
        CustomNotification.showTopNotification(context, res.data['message'] ?? "Update failed.");
      }
    } catch (e) { CustomNotification.showTopNotification(context, "Error: $e"); }
  }

  // --- UI UTILS ---

  void _showModal(String title, List<Widget> body, String? btnText, Future<void> Function()? onBtnTap) async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          bool isModalLoading = false;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 24),
                    ...body,
                    if (btnText != null) ...[
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: isModalLoading ? null : () async {
                          if (onBtnTap != null) {
                            setModalState(() => isModalLoading = true);
                            await onBtnTap();
                            if (mounted) setModalState(() => isModalLoading = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.tealText,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          elevation: 0
                        ),
                        child: isModalLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(btnText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Close", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, {bool isPassword = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)),
        decoration: _inputDecoration(label),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Switch(
            value: value, 
            onChanged: (v) { onChanged(v); setState(() {}); }, 
            activeColor: AppColors.tealText
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text("Are you sure you want to exit? Duty tracking will stop."),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("NO", style: TextStyle(fontWeight: FontWeight.w800))),
          TextButton(
            onPressed: () async {
              await SessionManager.logout();
              if (mounted) Navigator.pushReplacementNamed(context, '/');
            },
            child: const Text("YES", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
