import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import 'resident_track_truck_screen.dart';
import 'resident_complaints_screen.dart';
import 'resident_settings_screen.dart';
import '../widgets/mapbox_view.dart';

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  UserData? _user;
  int _activeTrucks = 0;
  int _totalTrucks = 0;
  int _unreadNotificationsCount = 0;
  int _selectedIndex = 0;
  String _etaText = "--";

  StreamSubscription? _truckSubscription;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _todayTripSubscription;
  StreamSubscription? _totalTruckSubscription;

  String _actualStartTime = "Not started";
  String _predictedEndTime = "";

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _truckSubscription?.cancel();
    _notificationSubscription?.cancel();
    _todayTripSubscription?.cancel();
    _totalTruckSubscription?.cancel();
    super.dispose();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      _setupListeners();
      _listenToTodayTrip();
    }
    if (mounted) setState(() {});
  }

  void _listenToTodayTrip() {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _todayTripSubscription?.cancel();
    _todayTripSubscription = _database.ref('driver_routes').orderByChild('date').equalTo(todayStr).onValue.listen((event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          final Map data = event.snapshot.value as Map; Map? relevantTrip;
          data.forEach((key, value) { if (relevantTrip == null || value['route_status'] == 'ACTIVE') { relevantTrip = value; } });
          if (relevantTrip != null) {
            final String? startTimeStr = relevantTrip!['start_time'];
            final String status = relevantTrip!['route_status'] ?? "";
            if (mounted) {
              setState(() {
                if (startTimeStr != null) {
                  _actualStartTime = startTimeStr;
                  if (status == 'COMPLETED' || status == 'FINISHED') _predictedEndTime = relevantTrip!['end_time'] ?? "";
                  else _predictedEndTime = "Calculating..."; 
                } else { _actualStartTime = "Waiting for driver"; _predictedEndTime = ""; }
              });
            }
          }
        }
      });
  }

  void _setupListeners() {
    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        int active = 0;
        data.forEach((key, value) {
          final val = value as Map;
          final status = (val['status'] ?? '').toString().toUpperCase();
          if (val['isOnline'] == true && (status == 'ACTIVE' || status == 'COLLECTING' || status == 'IDLE')) active++;
        });
        if (mounted) setState(() { _activeTrucks = active; _etaText = active > 0 ? "Approaching" : "No active collection"; });
      }
    });

    _totalTruckSubscription?.cancel();
    _totalTruckSubscription = _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        if (mounted) setState(() => _totalTrucks = data.length);
      }
    });

    _notificationSubscription?.cancel();
    _notificationSubscription = _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map; int unread = 0;
        data.forEach((key, value) {
          final val = value as Map;
          if (val['isRead'] == false) {
             final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
             if (targetPurok == '' || targetPurok == _user?.purok) unread++;
          }
        });
        if (mounted) setState(() => _unreadNotificationsCount = unread);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          ResidentTrackTruckScreen(isEmbedded: true, onBack: () => setState(() => _selectedIndex = 0)),
          ResidentComplaintsScreen(isEmbedded: true, onBack: () => setState(() => _selectedIndex = 0)),
          ResidentSettingsScreen(isEmbedded: true, onBack: () => setState(() => _selectedIndex = 0), onProfileUpdate: _loadUser),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab() {
    return LayoutBuilder(builder: (context, constraints) {
      double width = constraints.maxWidth;
      bool isMobile = width < 600;

      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF00796B), Color(0xFF009688), Color(0xFF4DB6AC)]), borderRadius: BorderRadius.vertical(bottom: Radius.circular(44))),
            padding: EdgeInsets.fromLTRB(28, isMobile ? 48 : 64, 28, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Welcome Back 👋", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(_user?.name ?? "Resident", style: TextStyle(color: Colors.white, fontSize: isMobile ? 28 : 32, fontWeight: FontWeight.w900, letterSpacing: -0.8), overflow: TextOverflow.ellipsis),
                  Row(children: [const Icon(Icons.location_on_rounded, color: Colors.white70, size: 14), const SizedBox(width: 4), Text(_user?.purok ?? "Area", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold))]),
                ])),
                _buildHeaderIconButton(Icons.notifications_none_rounded, badgeCount: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null, onTap: () => _showNotificationsModal(context)),
              ]),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -32),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
              Expanded(child: _buildStatCard("Active Trucks", "$_activeTrucks / $_totalTrucks", Icons.local_shipping_outlined, const Color(0xFF00BFA5), const Color(0xFFE8F5E9))),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard("Estimated Time", _etaText, Icons.access_time_rounded, const Color(0xFFFFA000), const Color(0xFFFFF8E1))),
            ])),
          ),
          _buildSectionTitle("Real-time Overview"),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 20, offset: const Offset(0, 10))]),
            child: Column(children: [
              ListTile(title: const Text("Live Tracking", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), subtitle: const Text("Real-time truck locations", style: TextStyle(fontSize: 12)), trailing: TextButton(onPressed: () => setState(() => _selectedIndex = 1), child: const Text("Full Map"))),
              Container(height: 200, width: double.infinity, margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: MapboxView(mode: 'dashboard', onTap: () => setState(() => _selectedIndex = 1)))),
            ]),
          ),
          _buildSectionTitle("Quick Actions"),
          if (width > 700) Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Wrap(spacing: 12, runSpacing: 12, children: [
            _buildActionCard("Track Trucks", "Real-time location", Icons.local_shipping_rounded, const Color(0xFF1E88E5), const Color(0xFFE3F2FD), () => setState(() => _selectedIndex = 1), width: (width - 52) / 2),
            _buildActionCard("File Complaint", "Report issues", Icons.feedback_outlined, const Color(0xFFFF1744), const Color(0xFFFFF0F2), () => Navigator.pushNamed(context, '/file_complaint'), width: (width - 52) / 2),
          ])) else Column(children: [
            _buildActionCard("Track Trucks", "Real-time location", Icons.local_shipping_rounded, const Color(0xFF1E88E5), const Color(0xFFE3F2FD), () => setState(() => _selectedIndex = 1)),
            _buildActionCard("File Complaint", "Report issues", Icons.feedback_outlined, const Color(0xFFFF1744), const Color(0xFFFFF0F2), () => Navigator.pushNamed(context, '/file_complaint')),
          ]),
          const SizedBox(height: 40),
        ]),
      );
    });
  }

  Widget _buildSectionTitle(String title) { return Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 8), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))))); }

  Widget _buildHeaderIconButton(IconData icon, {int? badgeCount, VoidCallback? onTap}) {
    return GestureDetector(onTap: onTap, child: Stack(children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.white, size: 24)),
      if (badgeCount != null) Positioned(right: 6, top: 6, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFFFF4081), shape: BoxShape.circle), child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
    ]));
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color accentColor, Color bgColor) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(28)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: accentColor, size: 22), const SizedBox(height: 24),
      Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w700)),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
    ]));
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color iconColor, Color bgColor, VoidCallback onTap, {double? width}) {
    return Container(width: width, margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(24), child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [
      Container(width: 52, height: 52, decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: iconColor, size: 26)),
      const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF757575)))]))
    ]))));
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex, selectedItemColor: const Color(0xFF00BFA5), unselectedItemColor: const Color(0xFF9E9E9E), type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.location_on_rounded), label: 'Track'),
        BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Complaints'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_suggest_rounded), label: 'Settings'),
      ],
      onTap: (index) => setState(() => _selectedIndex = index),
    );
  }

  void _showNotificationsModal(BuildContext context) {
    showDialog(context: context, builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Container(constraints: const BoxConstraints(maxWidth: 500), padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [Icon(Icons.notifications_active_outlined, color: Color(0xFF00BFA5), size: 28), SizedBox(width: 12), Expanded(child: Text("Notifications", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 24),
        Flexible(child: StreamBuilder(stream: _database.ref('notifications').onValue, builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.snapshot.exists) {
            final Map data = snapshot.data!.snapshot.value as Map; final List list = [];
            data.forEach((k, v) { 
              final val = v as Map;
              final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
              if (targetPurok == '' || targetPurok == _user?.purok) list.add(val);
            });
            if (list.isEmpty) return const Center(child: Text("No notifications"));
            return ListView.separated(shrinkWrap: true, itemCount: list.length, separatorBuilder: (c, i) => const Divider(), itemBuilder: (c, i) => ListTile(title: Text(list[i]['title'] ?? 'Alert'), subtitle: Text(list[i]['message'] ?? '')));
          }
          return const Center(child: Text("No notifications"));
        })),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE")),
      ])),
    ));
  }
}
