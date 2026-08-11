import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import '../utils/system_logger.dart';
import '../utils/responsive.dart';
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
  int _completedCount = 0;
  final int _totalPuroks = 13;
  int _selectedIndex = 0;
  bool _isPuroksExpanded = false;

  final List<Map<String, dynamic>> _puroks = [
    {"name": "Purok 1"}, {"name": "Purok 2"}, {"name": "Purok 3"}, {"name": "Purok 4"}, {"name": "Dos Riles"}, {"name": "Sentro"}, {"name": "San Isidro"}, {"name": "Paraiso"}, {"name": "Riverside"}, {"name": "Kalaw Street"}, {"name": "Home Subdivision"}, {"name": "Tanco Road / Ayala Highway"}, {"name": "Brixton Area"},
  ];

  Map<String, dynamic> _purokStatus = {};
  String? _sessionId;
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
        final data = event.snapshot.value as Map;
        if (mounted) setState(() {
          _status = data['status']?.toString().toUpperCase() ?? "OFFLINE";
          _distance = (data['distance'] ?? 0.0).toDouble();
          if (data['start_time'] != null) _startTime = data['start_time'];
          _sessionId = data['current_session']?.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(builder: (context, constraints) {
        return IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeTab(constraints),
            DriverTrackTruckScreen(isEmbedded: true, currentSessionId: _sessionId, focusTruckId: _user?.preferredTruck ?? "GT-001", onBack: () => setState(() => _selectedIndex = 0)),
            DriverSettingsScreen(isEmbedded: true, onBack: () => setState(() => _selectedIndex = 0), currentSessionId: _sessionId),
          ],
        );
      }),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab(BoxConstraints constraints) {
    double width = constraints.maxWidth;
    bool isMobile = width < 600;

    return SingleChildScrollView(
      child: Column(children: [
        _buildHeader(width),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _buildMetricCard("Start Time", _startTime, Icons.access_time_filled, Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard("Distance", "${_distance.toStringAsFixed(2)} km", Icons.route, Colors.purple)),
            ]),
            const SizedBox(height: 32),
            _buildVehicleControls(isMobile),
            const SizedBox(height: 32),
            _buildProgressTracker(),
            const SizedBox(height: 40),
          ]),
        ),
      ]),
    );
  }

  Widget _buildHeader(double width) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(color: AppColors.tealText, borderRadius: BorderRadius.vertical(bottom: Radius.circular(40))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Driver Dashboard", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: () {}),
        ]),
        const SizedBox(height: 12),
        Text(_user?.name ?? "Driver Name", style: TextStyle(color: Colors.white, fontSize: width > 600 ? 42 : 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Row(children: [
          Text("Truck: ${_user?.preferredTruck ?? 'GT-001'}", style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          _buildStatusIndicator(),
        ]),
      ]),
    );
  }

  Widget _buildStatusIndicator() {
    Color color = _status == "ACTIVE" ? Colors.greenAccent : Colors.yellowAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(_status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 24), const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildVehicleControls(bool isMobile) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(30)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Vehicle Controls", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _buildOpButton("START", Icons.play_arrow, Colors.green),
          _buildOpButton("PAUSE", Icons.pause, Colors.orange),
          _buildOpButton("FULL", Icons.local_shipping, Colors.pink),
          _buildOpButton("DONE", Icons.check, Colors.blue),
        ]),
      ]),
    );
  }

  Widget _buildOpButton(String label, IconData icon, Color color) {
    return Column(children: [
      Container(width: 60, height: 60, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildProgressTracker() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Collection Progress", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text("${((_completedCount / _totalPuroks) * 100).toInt()}%", style: const TextStyle(color: AppColors.tealText, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 20),
        ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _isPuroksExpanded ? _puroks.length : 3, itemBuilder: (context, i) => ListTile(title: Text(_puroks[i]['name']), leading: const Icon(Icons.location_on))),
        TextButton(onPressed: () => setState(() => _isPuroksExpanded = !_isPuroksExpanded), child: Text(_isPuroksExpanded ? "Show Less" : "View All")),
      ]),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex, selectedItemColor: AppColors.tealText,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
      onTap: (i) => setState(() => _selectedIndex = i),
    );
  }
}
