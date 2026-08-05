import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import 'driver_settings_screen.dart';
import 'driver_track_truck_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  UserData? _user;
  String _status = "OFFLINE";
  String _startTime = "--:--";
  double _distance = 0.0;
  int _visitedCount = 0;
  final int _totalPuroks = 12;
  int _selectedIndex = 0;

  StreamSubscription? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      if (mounted) setState(() {});
      _setupListeners();
    }
  }

  void _setupListeners() {
    final truckId = _user?.preferredTruck ?? "GT-001";
    _statusSubscription = _database.ref('truck_locations').child(truckId).onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
            _status = data['status']?.toString().toUpperCase() ?? "OFFLINE";
            _distance = (data['distance'] ?? 0.0).toDouble();
            _visitedCount = (data['visited_puroks'] ?? 0);
          });
        }
      }
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    final truckId = _user?.preferredTruck ?? "GT-001";
    String now = DateTime.now().toIso8601String();
    
    Map<String, dynamic> updates = {
      'status': newStatus.toLowerCase(),
      'updatedAt': now,
    };

    if (newStatus == "ACTIVE" && _startTime == "--:--") {
      String time = DateFormat('h:mm a').format(DateTime.now());
      updates['start_time'] = time;
      if (mounted) setState(() => _startTime = time);
    } else if (newStatus == "OFFLINE") {
      updates['start_time'] = "--:--";
      updates['distance'] = 0.0;
      updates['visited_puroks'] = 0;
      if (mounted) {
        setState(() {
          _startTime = "--:--";
          _distance = 0.0;
          _visitedCount = 0;
        });
      }
    }

    await _database.ref('truck_locations').child(truckId).update(updates);

    // TRIGGER NOTIFICATION IF FULL
    if (newStatus == "FULL") {
      await _database.ref('notifications').push().set({
        'type': 'TRUCK_FULL',
        'title': 'Truck Full: $truckId',
        'message': 'Truck $truckId has been marked as full by ${_user?.name ?? 'Driver'}',
        'truck_id': truckId,
        'timestamp': ServerValue.timestamp,
        'isRead': false,
      });
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Status updated to $newStatus")),
      );
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildMainDashboard(),
          DriverTrackTruckScreen(
            isEmbedded: true,
            onBack: () => setState(() => _selectedIndex = 0),
          ),
          DriverSettingsScreen(
            isEmbedded: true,
            onBack: () => setState(() => _selectedIndex = 0),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMainDashboard() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // 🚚 GRADIENT HEADER
          Container(
            width: double.infinity,
            height: 240,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE0F7FA),
                  Color(0xFFB2DFDB),
                  Color(0xFF80CBC4),
                ],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(44)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 20,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Active Duty", style: TextStyle(color: AppColors.textGray, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _user?.name ?? "Driver",
                          style: const TextStyle(color: AppColors.tealText, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildHeaderIconButton(Icons.notifications_none_rounded),
                        const SizedBox(width: 12),
                        _buildHeaderIconButton(Icons.logout_rounded, onTap: () => _showLogoutDialog(context)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.tealText.withAlpha(40),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "TRUCK: ${_user?.preferredTruck ?? 'GT-001'}",
                    style: const TextStyle(color: AppColors.tealText, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // 📊 TRIP METRICS
          Transform.translate(
            offset: const Offset(0, -32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: _buildStatCard("Start Time", _startTime, Icons.access_time_rounded, const Color(0xFF1976D2), const Color(0xFFE3F2FD))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard("Distance", "${_distance.toStringAsFixed(1)} km", Icons.route_rounded, const Color(0xFF9C27B0), const Color(0xFFF3E5F5))),
                ],
              ),
            ),
          ),

          // 📍 CURRENT STATUS CARD
          _buildSectionTitle("Operations Control"),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 20, offset: const Offset(0, 10))],
              border: Border.all(color: const Color(0xFFF5F5F5)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Vehicle Status", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                    _buildStatusBadge(),
                  ],
                ),
                const SizedBox(height: 32),
                _buildControlGrid(),
              ],
            ),
          ),

          // 📈 PROGRESS CARD
          _buildSectionTitle("Collection Progress"),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.analytics_rounded, color: Color(0xFF2E7D32), size: 22),
                    ),
                    const SizedBox(width: 16),
                    const Text("Route Overview", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 32),
                _buildProgressBar(),
                const SizedBox(height: 24),
                _buildSummaryRow("Puroks Visited", "$_visitedCount / $_totalPuroks"),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Color(0xFFF5F5F5))),
                _buildSummaryRow("Remaining", "${_totalPuroks - _visitedCount}"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- REFINED UI COMPONENTS ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(180),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.tealText, size: 24),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color accentColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w700)),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color statusColor = switch (_status) {
      'ACTIVE' => const Color(0xFF4CAF50),
      'FULL' => const Color(0xFFFF1744),
      'IDLE' => const Color(0xFFFFA000),
      _ => const Color(0xFF9E9E9E),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildControlGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildActionButton("START", Icons.play_arrow_rounded, const Color(0xFF4CAF50), () => _updateStatus("ACTIVE"))),
            const SizedBox(width: 16),
            Expanded(child: _buildActionButton("PAUSE", Icons.pause_rounded, const Color(0xFFFFA000), () => _updateStatus("IDLE"))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildActionButton("MARK FULL", Icons.warning_rounded, const Color(0xFFFF1744), () => _updateStatus("FULL"))),
            const SizedBox(width: 16),
            Expanded(child: _buildActionButton("FINISH", Icons.stop_rounded, const Color(0xFF1976D2), () => _updateStatus("OFFLINE"))),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withAlpha(20),
        foregroundColor: color,
        elevation: 0,
        minimumSize: const Size(0, 64),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: color.withAlpha(40)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    double progress = _visitedCount / _totalPuroks;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Coverage", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF757575))),
            Text("${(progress * 100).toInt()}%", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32))),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: const Color(0xFFF5F5F5),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF757575), fontSize: 14, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w900, fontSize: 14)),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 25, offset: Offset(0, -5))],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF00BFA5),
        unselectedItemColor: const Color(0xFF9E9E9E),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        elevation: 0,
        items: [
          _buildNavItem(Icons.dashboard_rounded, 'Duty', 0),
          _buildNavItem(Icons.map_rounded, 'Map', 1),
          _buildNavItem(Icons.settings_suggest_rounded, 'Config', 2),
        ],
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: isSelected ? BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(24)) : null,
        child: Icon(icon, size: 24),
      ),
      label: label,
    );
  }

  Widget _buildPlaceholderScreen() {
    return const Center(child: Text("Coming Soon", style: TextStyle(color: Colors.grey)));
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFFFF0F2), shape: BoxShape.circle), child: const Icon(Icons.logout_rounded, color: Color(0xFFFF1744), size: 32)),
              const SizedBox(height: 24),
              const Text("End Shift?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 16),
              const Text("Are you sure you want to end your current duty session?", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF757575), fontSize: 14, height: 1.5)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () async {
                  await _updateStatus("OFFLINE");
                  await SessionManager.logout();
                  if (!mounted) return;
                  Navigator.pushReplacementNamed(context, '/');
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                child: const Text("Sign Out", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w900))),
            ],
          ),
        ),
      ),
    );
  }
}
