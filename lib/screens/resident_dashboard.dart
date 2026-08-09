import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
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
  int _userRating = 0;
  bool _hasRated = false;
  String _etaText = "--";
  String _scheduleFrequency = "Daily";
  String _scheduleTimeWindow = "8:00 AM – 12:00 PM";
  final TextEditingController _ratingCommentController = TextEditingController();

  final Map<String, Map<String, double>> _purokCoordinates = {
    "Purok 1": {"lat": 13.9450, "lng": 121.1650},
    "Purok 2": {"lat": 13.9440, "lng": 121.1640},
    "Purok 3": {"lat": 13.9430, "lng": 121.1630},
    "Purok 4": {"lat": 13.9420, "lng": 121.1620},
    "Dos Riles": {"lat": 13.9410, "lng": 121.1610},
    "Sentro": {"lat": 13.9400, "lng": 121.1600},
    "San Isidro": {"lat": 13.9390, "lng": 121.1590},
    "Paraiso": {"lat": 13.9380, "lng": 121.1580},
    "Riverside": {"lat": 13.9370, "lng": 121.1570},
    "Kalaw Street": {"lat": 13.9360, "lng": 121.1560},
    "Home Subdivision": {"lat": 13.9350, "lng": 121.1550},
    "Tanco Road / Ayala Highway": {"lat": 13.9340, "lng": 121.1540},
    "Brixton Area": {"lat": 13.9330, "lng": 121.1530},
  };

  StreamSubscription? _truckSubscription;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _scheduleSubscription;
  StreamSubscription? _todayTripSubscription;
  StreamSubscription? _totalTruckSubscription;

  String? _todayTripId;
  String _actualStartTime = "Not started";
  String _predictedEndTime = "";
  double _historicalAvgDurationMinutes = 210.0; // Default 3.5 hours

  @override
  void initState() {
    super.initState();
    _loadUser();
    _calculateHistoricalAverage();
  }

  @override
  void dispose() {
    _ratingCommentController.dispose();
    _truckSubscription?.cancel();
    _notificationSubscription?.cancel();
    _scheduleSubscription?.cancel();
    _todayTripSubscription?.cancel();
    _totalTruckSubscription?.cancel();
    super.dispose();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      _setupListeners();
      _checkRatingStatus();
      _listenToTodayTrip();
    }
    if (mounted) setState(() {});
  }

  Future<void> _calculateHistoricalAverage() async {
    try {
      final snapshot = await _database.ref('driver_routes').get();
      if (snapshot.exists) {
        final Map data = snapshot.value as Map;
        List<int> durations = [];
        
        data.forEach((key, value) {
          if (value['route_status'] == 'COMPLETED' || value['route_status'] == 'FINISHED') {
             final String? start = value['start_time'];
             final String? end = value['end_time'];
             if (start != null && end != null) {
                try {
                  final DateFormat format = DateFormat('h:mm a');
                  final DateTime startTime = format.parse(start);
                  final DateTime endTime = format.parse(end);
                  int diff = endTime.difference(startTime).inMinutes;
                  if (diff > 0 && diff < 600) { // Valid duration < 10h
                    durations.add(diff);
                  }
                } catch (e) {}
             }
          }
        });
        
        if (durations.isNotEmpty) {
          _historicalAvgDurationMinutes = durations.reduce((a, b) => a + b) / durations.length;
        }
      }
    } catch (e) {}
  }

  void _listenToTodayTrip() {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _todayTripSubscription?.cancel();
    _todayTripSubscription = _database.ref('driver_routes')
      .orderByChild('date')
      .equalTo(todayStr)
      .onValue.listen((event) {
        if (event.snapshot.exists && event.snapshot.value != null) {
          final Map data = event.snapshot.value as Map;
          Map? relevantTrip;
          
          data.forEach((key, value) {
            if (relevantTrip == null || value['route_status'] == 'ACTIVE') {
              relevantTrip = value;
              relevantTrip!['id'] = key;
            }
          });

          if (relevantTrip != null) {
            _todayTripId = relevantTrip!['id'];
            final String? startTimeStr = relevantTrip!['start_time'];
            final String status = relevantTrip!['route_status'] ?? "";
            
            if (mounted) {
              setState(() {
                if (startTimeStr != null) {
                  _actualStartTime = startTimeStr;
                  if (status == 'COMPLETED' || status == 'FINISHED') {
                    _predictedEndTime = relevantTrip!['end_time'] ?? "";
                  } else {
                    try {
                      final DateFormat format = DateFormat('h:mm a');
                      DateTime startDateTime = format.parse(startTimeStr);
                      final now = DateTime.now();
                      DateTime pred = DateTime(now.year, now.month, now.day, startDateTime.hour, startDateTime.minute)
                          .add(Duration(minutes: _historicalAvgDurationMinutes.round()));
                      _predictedEndTime = format.format(pred);
                    } catch (e) {
                      _predictedEndTime = "";
                    }
                  }
                } else {
                  _actualStartTime = "Waiting for driver";
                  _predictedEndTime = "";
                }
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _actualStartTime = "Not started";
              _predictedEndTime = "";
            });
          }
        }
      });
  }

  void _checkRatingStatus() async {
    if (_user == null) return;
    final snapshot = await _database.ref('user_ratings/${_user!.userId}').get();
    if (snapshot.exists) {
      if (mounted) setState(() => _hasRated = true);
    }
  }

  void _setupListeners() {
    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final dynamic data = event.snapshot.value;
        Map<dynamic, dynamic> dataMap = {};
        if (data is Map) {
          dataMap = data;
        } else if (data is List) {
          for (int i = 0; i < data.length; i++) {
            if (data[i] != null) dataMap[i.toString()] = data[i];
          }
        }

        final Map<String, Map<dynamic, dynamic>> activeTrucksMap = {};
        
        dataMap.forEach((key, value) {
          final val = value as Map;
          final status = (val['status'] ?? '').toString().toUpperCase();
          final bool isOnline = val['isOnline'] == true;
          final String rawTruckId = (val['truck_id'] ?? key.toString());
          final String truckId = rawTruckId.toUpperCase().trim();

          bool isFresh = true;
          if (val['lastSeen'] != null) {
            final int lastSeen = int.tryParse(val['lastSeen'].toString()) ?? 0;
            final int now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastSeen > 300000) isFresh = false;
          }

          if (isOnline && isFresh && (status == 'ACTIVE' || status == 'COLLECTING' || status == 'IDLE' || status == 'FULL')) {
            if (!activeTrucksMap.containsKey(truckId)) {
              activeTrucksMap[truckId] = val;
            } else {
              final existing = activeTrucksMap[truckId]!;
              final existingTime = DateTime.tryParse(existing['updatedAt'] ?? '') ?? DateTime(2000);
              final newTime = DateTime.tryParse(val['updatedAt'] ?? '') ?? DateTime(2000);
              if (newTime.isAfter(existingTime)) activeTrucksMap[truckId] = val;
            }
          }
        });

        if (mounted) {
          setState(() {
            _activeTrucks = activeTrucksMap.length;
            _calculateBestETA(activeTrucksMap.values.map((v) => v as Map).toList());
          });
          debugPrint("[TRUCK COUNT DEBUG] Active count from truck_locations: $_activeTrucks");
        }
      } else {
        if (mounted) setState(() => _activeTrucks = 0);
      }
    });

    // Listen to 'trucks' node for total registered trucks
    _totalTruckSubscription?.cancel();
    _totalTruckSubscription = _database.ref('trucks').onValue.listen((event) {
      if (event.snapshot.exists) {
        final dynamic data = event.snapshot.value;
        int count = 0;
        if (data is Map) {
          count = data.length;
        } else if (data is List) {
          count = data.where((e) => e != null).length;
        }
        if (mounted) {
          setState(() => _totalTrucks = count);
          debugPrint("[TRUCK COUNT DEBUG] Total registered trucks from 'trucks' node: $_totalTrucks");
        }
      } else {
        // Fallback: use truck_locations to count total unique trucks ever seen
        _database.ref('truck_locations').get().then((snap) {
          if (snap.exists) {
            final Map data = snap.value as Map;
            final Set<String> uniqueIds = {};
            data.forEach((k, v) {
              final val = v as Map;
              uniqueIds.add((val['truck_id'] ?? k.toString()).toUpperCase().trim());
            });
            if (mounted) setState(() => _totalTrucks = uniqueIds.length);
          }
        });
      }
    });

    _notificationSubscription?.cancel();
    _notificationSubscription = _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        int unread = 0;
        data.forEach((key, value) {
          final val = value as Map;
          if (val['isRead'] == false) {
             final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
             final String? resId = val['residentId']?.toString();
             if (targetPurok == '' || targetPurok == _user?.purok || resId == _user?.userId) {
               unread++;
             }
          }
        });
        if (mounted) {
          setState(() => _unreadNotificationsCount = unread);
        }
      } else {
        if (mounted) setState(() => _unreadNotificationsCount = 0);
      }
    });

    if (_user?.purok != null) {
      _scheduleSubscription?.cancel();
      _scheduleSubscription = _database.ref('collection_schedules/${_user!.purok}').onValue.listen((event) {
        if (event.snapshot.exists) {
          final Map data = event.snapshot.value as Map;
          if (mounted) {
            setState(() {
              _scheduleFrequency = data['frequency'] ?? "Daily";
            });
          }
        }
      });
    }
  }

  Future<void> _markAsRead(String id) async {
    await _database.ref('notifications/$id').update({'isRead': true});
  }

  Future<void> _markAllAsRead() async {
    final snapshot = await _database.ref('notifications').get();
    if (snapshot.exists) {
      final Map data = snapshot.value as Map;
      final updates = <String, dynamic>{};
      data.forEach((k, v) {
        final val = v as Map;
        final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
        final String? resId = val['residentId']?.toString();
        if (val['isRead'] == false && (targetPurok == '' || targetPurok == _user?.purok || resId == _user?.userId)) {
          updates['notifications/$k/isRead'] = true;
        }
      });
      if (updates.isNotEmpty) {
        await _database.ref().update(updates);
      }
    }
  }

  void _calculateBestETA(List<Map> activeTrucks) {
    if (_user == null || _user!.purok == null || activeTrucks.isEmpty) {
      if (mounted) setState(() => _etaText = "No active collection");
      return;
    }

    final myPurok = _purokCoordinates[_user!.purok];
    if (myPurok == null) {
      if (mounted) setState(() => _etaText = "--");
      return;
    }

    double bestTimeMinutes = double.infinity;
    String statusNote = "";

    for (var truck in activeTrucks) {
      final double truckLat = (truck['latitude'] ?? 0.0).toDouble();
      final double truckLng = (truck['longitude'] ?? 0.0).toDouble();
      final double truckSpeed = (truck['speed'] ?? 0.0).toDouble();
      final String truckStatus = (truck['status'] ?? '').toString().toUpperCase();

      if (truckLat == 0 || truckLng == 0) continue;

      double distForEta = (truck['distance'] ?? 0.0).toDouble();
      if (distForEta <= 0) distForEta = 2.5;

      double speedForCalc = truckSpeed > 5 ? truckSpeed : 15.0;
      double timeHours = distForEta / speedForCalc;
      double timeMinutes = timeHours * 60;

      if (truckStatus == 'IDLE') {
        timeMinutes += 5;
        statusNote = " (Delayed)";
      }

      if (timeMinutes < bestTimeMinutes) {
        bestTimeMinutes = timeMinutes;
      }
    }

    if (bestTimeMinutes == double.infinity) {
      if (mounted) setState(() => _etaText = "No active collection");
    } else {
      final arrivalTime = DateTime.now().add(Duration(minutes: bestTimeMinutes.round()));
      final timeStr = DateFormat('h:mm a').format(arrivalTime);
      
      if (mounted) {
        setState(() {
          if (bestTimeMinutes < 1) {
            _etaText = "Arriving now";
          } else {
            _etaText = "$timeStr (${bestTimeMinutes.round()} mins)$statusNote";
          }
        });
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning 👋";
    if (hour < 17) return "Good afternoon 👋";
    return "Good evening 👋";
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 220,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00796B), Color(0xFF009688), Color(0xFF4DB6AC)],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(44)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 5))],
                ),
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_getGreeting(), style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                _user?.name ?? "Resident",
                                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.8),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, color: Colors.white70, size: 14),
                                  const SizedBox(width: 4),
                                  Text(_user?.purok ?? "Area", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _buildHeaderIconButton(
                              Icons.notifications_none_rounded,
                              badgeCount: _unreadNotificationsCount > 0 ? _unreadNotificationsCount : null,
                              onTap: () => _showNotificationsModal(context),
                            ),
                            const SizedBox(width: 12),
                            _buildHeaderIconButton(Icons.power_settings_new_rounded, onTap: () => _showLogoutDialog(context)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: _buildStatCard("Active Trucks", "$_activeTrucks / $_totalTrucks", Icons.local_shipping_outlined, const Color(0xFF00BFA5), const Color(0xFFE8F5E9), isLive: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard("Estimated Time", _etaText, Icons.access_time_rounded, const Color(0xFFFFA000), const Color(0xFFFFF8E1))),
                    ],
                  ),
                ),
              ),
              _buildSectionTitle("Real-time Overview"),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 20, offset: const Offset(0, 10))],
                  border: Border.all(color: const Color(0xFFF5F5F5)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Live Tracking", style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A), fontSize: 17)),
                              Text("Real-time truck locations", style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
                            ],
                          ),
                          TextButton(
                            onPressed: () => setState(() => _selectedIndex = 1),
                            child: const Text("Full Map", style: TextStyle(color: Color(0xFF00BFA5), fontWeight: FontWeight.w800, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 200,
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20), 
                        color: const Color(0xFFF5F5F5),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: MapboxView(
                          mode: 'dashboard',
                          onTap: () => setState(() => _selectedIndex = 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSectionTitle("Quick Actions"),
              _buildActionCard("Track Trucks", "Real-time GPS location", Icons.local_shipping_rounded, const Color(0xFF1E88E5), const Color(0xFFE3F2FD), () => setState(() => _selectedIndex = 1)),
              _buildActionCard("File Complaint", "Report collection issues", Icons.feedback_outlined, const Color(0xFFFF1744), const Color(0xFFFFF0F2), () => Navigator.pushNamed(context, '/file_complaint')),
              if (!_hasRated)
                _buildActionCard("Service Quality", "Rate your experience", Icons.star_outline_rounded, const Color(0xFF9C27B0), const Color(0xFFF3E5F5), () => _showRateServiceModal(context)),
              _buildSectionTitle("Collection Schedule"),
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
                    _buildScheduleRow("Frequency", _scheduleFrequency, isBadge: true),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Color(0xFFF5F5F5))),
                    _buildScheduleRow("Time Window", _actualStartTime == "Not started" || _actualStartTime == "Waiting for driver" 
                    ? _actualStartTime 
                    : (_predictedEndTime.isNotEmpty ? "$_actualStartTime – $_predictedEndTime" : _actualStartTime)),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Color(0xFFF5F5F5))),
                    _buildScheduleRow("Your Area", _user?.purok ?? "Pending", isPurok: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
      ),
    );
  }

  Widget _buildHeaderIconButton(IconData icon, {int? badgeCount, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          if (badgeCount != null)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Color(0xFFFF4081), shape: BoxShape.circle),
                child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color accentColor, Color bgColor, {bool isLive = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF00BFA5), borderRadius: BorderRadius.circular(12)),
                  child: const Text("Live", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w700)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        ],
      ),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color iconColor, Color bgColor, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1D1D1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleRow(String label, String value, {bool isBadge = false, bool isPurok = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF757575), fontSize: 14, fontWeight: FontWeight.w600)),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(20)),
            child: Text(value, style: const TextStyle(color: Color(0xFF00796B), fontSize: 13, fontWeight: FontWeight.w900)),
          )
        else if (isPurok)
          Row(
            children: [
              const Icon(Icons.explore_outlined, color: Color(0xFF00796B), size: 16),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(color: Color(0xFF00796B), fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          )
        else
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.location_on_rounded), label: 'Track'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_rounded), label: 'Complaints'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_suggest_rounded), label: 'Settings'),
        ],
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }

  void _showNotificationsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: Color(0xFF00BFA5), size: 28),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("Notifications", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  TextButton(onPressed: () => _markAllAsRead(), child: const Text("Mark all as read")),
                ],
              ),
              const SizedBox(height: 24),
              Flexible(
                child: StreamBuilder(
                  stream: _database.ref('notifications').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.snapshot.exists) {
                      final Map data = snapshot.data!.snapshot.value as Map;
                      final List list = [];
                      data.forEach((k, v) {
                        final val = v as Map;
                        final String targetPurok = (val['purok'] ?? val['area'] ?? '').toString();
                        final String? resId = val['residentId']?.toString();
                        if (targetPurok == '' || targetPurok == _user?.purok || resId == _user?.userId) {
                          list.add({...val, 'id': k});
                        }
                      });
                      
                      if (list.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No notifications yet.")));
                      
                      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                      
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 12),
                        itemBuilder: (c, i) {
                          final item = list[i];
                          return InkWell(
                            onTap: () => _markAsRead(item['id']),
                            borderRadius: BorderRadius.circular(16),
                            child: _buildNotificationItem(item),
                          );
                        },
                      );
                    }
                    return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No notifications yet.")));
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(Map item) {
    final bool isRead = item['isRead'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : const Color(0xFFF0F9F8),
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: isRead ? const Color(0xFFF5F5F5) : const Color(0xFF00BFA5).withOpacity(0.1))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(item['title'] ?? 'Alert', style: TextStyle(fontWeight: FontWeight.w900, color: isRead ? Colors.black87 : const Color(0xFF00796B)))),
              if (!isRead) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00BFA5), shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 4),
          Text(item['message'] ?? '', style: TextStyle(fontSize: 12, color: isRead ? const Color(0xFF757575) : Colors.black87)),
          const SizedBox(height: 8),
          Text(
            item['timestamp'] != null ? DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(item['timestamp'])) : '',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showRateServiceModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Rate our Service", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 12),
                  const Text("Your feedback helps us optimize the collection frequency in your area.", style: TextStyle(fontSize: 14, color: Color(0xFF757575), height: 1.5)),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < _userRating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: index < _userRating ? const Color(0xFFFFC107) : Colors.grey[300],
                          size: 44,
                        ),
                        onPressed: () => setModalState(() => _userRating = index + 1),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF0F0F0))),
                    child: TextField(
                      controller: _ratingCommentController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Tell us more... (Optional)",
                        hintStyle: TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Color(0xFF757575), fontWeight: FontWeight.w900)))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (_userRating == 0) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a rating star")));
                              return;
                            }
                            await _database.ref('user_ratings/${_user!.userId}').set({
                              'rating': _userRating,
                              'comment': _ratingCommentController.text.trim(),
                              'userName': _user!.name,
                              'purok': _user!.purok,
                              'timestamp': ServerValue.timestamp,
                            });
                            if (mounted) {
                              setState(() => _hasRated = true);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thank you for your feedback!"), backgroundColor: Color(0xFF00BFA5)));
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFA5), minimumSize: const Size(0, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          child: const Text("SUBMIT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Sign Out?"),
        content: const Text("Are you sure you want to end your current session?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await SessionManager.logout();
              if (mounted) Navigator.pushReplacementNamed(context, '/');
            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
