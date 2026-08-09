import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/session_manager.dart';
import '../models/user.dart';
import '../utils/app_theme.dart';
import '../utils/system_logger.dart';
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
  DateTime? _startDateTime;
  double _distance = 0.0;
  int _completedCount = 0;
  final int _totalPuroks = 13;
  int _selectedIndex = 0;
  bool _isPuroksExpanded = false;

  final List<Map<String, dynamic>> _purokConfigs = [
    {"name": "Purok 1", "lat": 13.9450, "lng": 121.1650},
    {"name": "Purok 2", "lat": 13.9440, "lng": 121.1640},
    {"name": "Purok 3", "lat": 13.9430, "lng": 121.1630},
    {"name": "Purok 4", "lat": 13.9420, "lng": 121.1620},
    {"name": "Dos Riles", "lat": 13.9410, "lng": 121.1610},
    {"name": "Sentro", "lat": 13.9400, "lng": 121.1600},
    {"name": "San Isidro", "lat": 13.9390, "lng": 121.1590},
    {"name": "Paraiso", "lat": 13.9380, "lng": 121.1580},
    {"name": "Riverside", "lat": 13.9370, "lng": 121.1570},
    {"name": "Kalaw Street", "lat": 13.9360, "lng": 121.1560},
    {"name": "Home Subdivision", "lat": 13.9350, "lng": 121.1550},
    {"name": "Tanco Road / Ayala Highway", "lat": 13.9340, "lng": 121.1540},
    {"name": "Brixton Area", "lat": 13.9330, "lng": 121.1530},
  ];

  Map<String, dynamic> _purokStatus = {};

  // Tracking & Session
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  String? _sessionId;
  DateTime? _idleStartTime;
  DateTime? _lastGpsUpdateTime;
  Timer? _idleDetectionTimer;
  bool _isInitializing = true;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _purokStatusSubscription;

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
      _startTripSession(); 
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
            if (data['start_time'] != null) _startTime = data['start_time'];
          });
        }
      }
    });
  }

  void _setupPurokListener() {
    if (_sessionId == null) return;
    _purokStatusSubscription?.cancel();
    _purokStatusSubscription = _database.ref('collection_progress').child(_sessionId!).onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        int completed = 0;
        data.forEach((key, value) {
          if (value['completed'] == true) completed++;
        });
        if (mounted) {
          setState(() {
            _purokStatus = Map<String, dynamic>.from(data);
            _completedCount = completed;
          });
          final truckId = _user?.preferredTruck ?? "GT-001";
          _database.ref('truck_locations').child(truckId).update({
            'visited_puroks': completed,
            'efficiency': (completed / _totalPuroks) * 100,
          });
        }
      }
    });
  }

  // --- TRIP LOGIC ---

  Future<void> _startTripSession() async {
    setState(() => _isInitializing = true);
    
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isInitializing = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isInitializing = false);
        return;
      }
    }

    final truckId = _user?.preferredTruck ?? "GT-001";
    final driverId = _user?.userId ?? "Unknown";

    try {
      Position startPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      debugPrint("[DRIVER GPS] latitude = ${startPos.latitude}, longitude = ${startPos.longitude}, accuracy = ${startPos.accuracy}");

      _sessionId = _database.ref('driver_routes').push().key;
      _startDateTime = DateTime.now();
      String timeStr = DateFormat('h:mm a').format(_startDateTime!);

      await _database.ref('truck_locations').child(truckId).update({
        'status': 'ACTIVE',
        'isOnline': true,
        'driver_id': driverId,
        'driver_name': _user?.name ?? 'Driver',
        'start_time': timeStr,
        'server_start_time': ServerValue.timestamp,
        'latitude': startPos.latitude,
        'longitude': startPos.longitude,
        'distance': 0.0,
        'speed': 0.0,
        'avg_speed': 0.0,
        'efficiency': 0.0,
        'accuracy': startPos.accuracy,
        'lastSeen': ServerValue.timestamp,
        'updatedAt': DateTime.now().toIso8601String(),
        'current_session': _sessionId,
      });

      // Handle disconnect - automatically set to OFFLINE if driver app closes/crashes
      _database.ref('truck_locations').child(truckId).onDisconnect().update({
        'status': 'OFFLINE',
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      });

      await _database.ref('driver_routes').child(_sessionId!).set({
        'truck_id': truckId,
        'driver_id': driverId,
        'driver_name': _user?.name ?? 'Driver',
        'start_time': timeStr,
        'route_status': 'ACTIVE',
        'isOnline': true,
        'timestamp': ServerValue.timestamp,
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'maintenanceProcessed': false,
      });

      // Initialize Progress in Firebase
      Map<String, dynamic> initialProgress = {};
      for (int i = 0; i < _purokConfigs.length; i++) {
        final p = _purokConfigs[i];
        initialProgress[p['name'].replaceAll('/', '_')] = {
          'name': p['name'],
          'lat': p['lat'],
          'lng': p['lng'],
          'completed': false,
          'order': i,
        };
      }
      await _database.ref('collection_progress').child(_sessionId!).set(initialProgress);

      _appendRoutePoint(startPos, "ACTIVE", "BLUE");

      if (mounted) {
        setState(() {
          _status = "ACTIVE";
          _startTime = timeStr;
          _distance = 0.0;
          _currentPosition = startPos;
          _isInitializing = false;
          _lastGpsUpdateTime = DateTime.now();
        });
      }
      _setupPurokListener();
      _startTracking();
      _startIdleDetection();
    } catch (e) {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  void _startTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, 
        distanceFilter: 0,
      ),
    ).listen((pos) => _processNewPosition(pos));
  }

  void _processNewPosition(Position pos) {
    if (_sessionId == null || _status == "OFFLINE" || _status == "FINISHED") return;
    final truckId = _user?.preferredTruck ?? "GT-001";
    
    double traveled = 0;
    if (_currentPosition != null) {
      traveled = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, pos.latitude, pos.longitude) / 1000.0;
      if (Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, pos.latitude, pos.longitude) < 0.5) {
        traveled = 0;
      }
    }

    _lastGpsUpdateTime = DateTime.now();
    double speedKmH = (pos.speed * 3.6);

    if (mounted) {
      setState(() {
        _distance += traveled;
        _currentPosition = pos;
        if (speedKmH > 1.0 && _status == "IDLE") {
          _updateTripStatus("ACTIVE");
        }
      });
    }

    if (speedKmH > 1.0) _idleStartTime = null;

    _checkPurokProximity(pos);

    double avgSpeed = 0.0;
    if (_startDateTime != null) {
      final durationHrs = DateTime.now().difference(_startDateTime!).inSeconds / 3600.0;
      if (durationHrs > 0) {
        avgSpeed = _distance / durationHrs;
      }
    }

    _database.ref('truck_locations').child(truckId).update({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'distance': _distance,
      'speed': speedKmH,
      'avg_speed': avgSpeed,
      'heading': pos.heading,
      'accuracy': pos.accuracy,
      'isOnline': true,
      'lastSeen': ServerValue.timestamp,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    debugPrint("[DRIVER LIVE SHARE] truckId = $truckId, lat = ${pos.latitude}, lng = ${pos.longitude}, status = $_status");

    String trailColor = "BLUE";
    if (_status == "IDLE") trailColor = "YELLOW";
    if (_status == "FINISHED") trailColor = "GRAY";

    _appendRoutePoint(pos, _status, trailColor);
  }

  void _checkPurokProximity(Position pos) {
    if (_sessionId == null) return;
    
    for (var p in _purokConfigs) {
      String key = p['name'].replaceAll('/', '_');
      if (_purokStatus[key]?['completed'] == true) continue;

      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, p['lat'], p['lng']);
      
      if (dist <= 50) {
        _database.ref('collection_progress').child(_sessionId!).child(key).update({
          'completed': true,
          'completedAt': DateFormat('h:mm a').format(DateTime.now()),
          'timestamp': ServerValue.timestamp,
        });
        
        // Update current purok in truck_locations
        final truckId = _user?.preferredTruck ?? "GT-001";
        _database.ref('truck_locations').child(truckId).update({
          'current_purok': p['name'],
        });

        SystemLogger.logEvent("ROUTE_COMPLETED", "Entered ${p['name']}");
      }
    }
  }

  void _appendRoutePoint(Position pos, String status, String color) {
    if (_sessionId == null) return;
    _database.ref('driver_routes').child(_sessionId!).child('route').push().set({
      'lat': pos.latitude, 
      'lng': pos.longitude, 
      'status': status, 
      'color': color,
      'speed': pos.speed * 3.6,
      'heading': pos.heading,
      'accuracy': pos.accuracy,
      'timestamp': ServerValue.timestamp,
    });
  }

  void _startIdleDetection() {
    _idleDetectionTimer?.cancel();
    _idleDetectionTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_currentPosition == null || _status == "OFFLINE" || _status == "FINISHED" || _status == "IDLE") return;
      
      double speedKmH = _currentPosition!.speed * 3.6;
      bool isStationary = speedKmH < 1.0;
      bool poorAccuracy = _currentPosition!.accuracy > 60;
      bool signalLoss = _lastGpsUpdateTime != null && DateTime.now().difference(_lastGpsUpdateTime!).inSeconds > 45;

      if (isStationary || poorAccuracy || signalLoss) {
        if (_idleStartTime == null) {
          _idleStartTime = DateTime.now();
        } else if (DateTime.now().difference(_idleStartTime!).inMinutes >= 2) {
          _updateTripStatus("IDLE");
          if (signalLoss && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Weak GPS signal detected. Tracking temporarily paused."))
            );
          }
        }
      } else {
        _idleStartTime = null;
      }
    });
  }

  Future<void> _updateTripStatus(String newStatus) async {
    final truckId = _user?.preferredTruck ?? "GT-001";
    await _database.ref('truck_locations').child(truckId).update({
      'status': newStatus.toUpperCase(),
      'updatedAt': DateTime.now().toIso8601String(),
    });

    if (_sessionId != null) {
      await _database.ref('driver_routes').child(_sessionId!).update({
        'current_status': newStatus,
        'route_status': newStatus == 'FINISHED' ? 'COMPLETED' : newStatus,
      });
    }
    if (mounted) setState(() => _status = newStatus);
  }

  Future<void> _finishTrip() async {
    if (_sessionId == null) return;
    final truckId = _user?.preferredTruck ?? "GT-001";
    final finalDistance = _distance;

    // Use a transaction-like approach to prevent double processing
    final sessionRef = _database.ref('driver_routes').child(_sessionId!);
    final sessionSnap = await sessionRef.get();
    
    if (sessionSnap.exists) {
      final sessionData = Map<String, dynamic>.from(sessionSnap.value as Map);
      if (sessionData['maintenanceProcessed'] == true) {
        debugPrint("Deduction already processed for this session.");
        return;
      }
    }

    // 1. Mark session as completed and maintenance as processed
    await sessionRef.update({
      'route_status': 'COMPLETED',
      'end_time': DateFormat('h:mm a').format(DateTime.now()),
      'finish_lat': _currentPosition?.latitude,
      'finish_lng': _currentPosition?.longitude,
      'final_distance': finalDistance,
      'maintenanceProcessed': true,
    });

    // 2. Process Maintenance Deduction
    final truckRef = _database.ref('trucks/$truckId');
    final truckSnap = await truckRef.get();
    
    if (truckSnap.exists) {
      final data = Map<String, dynamic>.from(truckSnap.value as Map);
      double currentOdo = (data['odometerKm'] ?? 0.0).toDouble();
      Map maintenance = Map<String, dynamic>.from(data['maintenance'] ?? {});

      maintenance.forEach((key, value) {
        if (value is Map) {
          double remaining = (value['remainingKm'] ?? 0.0).toDouble();
          double interval = (value['intervalKm'] ?? 5000.0).toDouble();
          
          double newRemaining = remaining - finalDistance;
          if (newRemaining < 0) newRemaining = 0.0;
          value['remainingKm'] = newRemaining;
          
          double percent = (newRemaining / interval) * 100;
          if (newRemaining <= 0) {
            value['status'] = 'OVERDUE';
          } else if (percent <= 20) {
            value['status'] = 'DUE SOON';
          } else {
            value['status'] = 'NORMAL';
          }
        }
      });

      await truckRef.update({
        'odometerKm': currentOdo + finalDistance,
        'maintenance': maintenance,
        'lastTripProcessed': _sessionId,
      });
    }

    await _database.ref('truck_locations').child(truckId).update({
      'status': 'finished', 
      'current_session': null
    });

    _positionSubscription?.cancel(); 
    _idleDetectionTimer?.cancel();
    
    if (mounted) {
      setState(() { 
        _status = "FINISHED"; 
        _sessionId = null; 
        _startTime = "--:--"; 
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Trip Finished. ${finalDistance.toStringAsFixed(2)} km added to odometer."))
      );
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return IndexedStack(
            index: _selectedIndex,
            children: [
              _buildResponsiveDashboard(constraints),
              DriverTrackTruckScreen(
                isEmbedded: true, 
                currentSessionId: _sessionId, 
                focusTruckId: _user?.preferredTruck ?? "GT-001",
                onBack: () => setState(() => _selectedIndex = 0)
              ),
              DriverSettingsScreen(
                isEmbedded: true, 
                onBack: () => setState(() => _selectedIndex = 0),
                currentSessionId: _sessionId,
              ),
            ],
          );
        }
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildResponsiveDashboard(BoxConstraints constraints) {
    double width = constraints.maxWidth;
    double padding = width > 900 ? 40 : 20;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(width),
          Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTripInfoGrid(width),
                const SizedBox(height: 32),
                _buildOperationButtons(width),
                const SizedBox(height: 32),
                _buildOperationsGrid(width),
                const SizedBox(height: 32),
                _buildMapCard(width),
                const SizedBox(height: 32),
                _buildProgressTracker(width),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripInfoGrid(double width) {
    double cardWidth = (width - (width > 900 ? 80 : 40) - 16) / 2;
    return Row(
      children: [
        _buildMetricCard("Start Time", _startTime, Icons.access_time_filled, Colors.blue, cardWidth),
        const SizedBox(width: 16),
        _buildMetricCard("Distance", "${_distance.toStringAsFixed(2)} km", Icons.route, Colors.purple, cardWidth),
      ],
    );
  }

  Widget _buildOperationButtons(double width) {
    bool isWide = width > 600;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.black.withAlpha(5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Vehicle Controls", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildOpButton("START", Icons.play_arrow, AppColors.opStart, null, isWide),
              _buildOpButton("PAUSE", Icons.pause, AppColors.opPause, () => _updateTripStatus(_status == "IDLE" ? "ACTIVE" : "IDLE"), isWide),
              _buildOpButton("FULL", Icons.local_shipping, AppColors.opFull, () => _updateTripStatus("FULL"), isWide),
              _buildOpButton("DONE", Icons.check, AppColors.opDone, _showFinishConfirmation, isWide),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpButton(String label, IconData icon, Color color, VoidCallback? onTap, bool isWide) {
    bool isSelected = (_status == label);
    if (label == "PAUSE" && _status == "IDLE") isSelected = true;
    if (label == "START" && _status == "ACTIVE") isSelected = true;

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: isWide ? 120 : 70, height: 60,
            decoration: BoxDecoration(
              color: isSelected ? color : color.withAlpha(150), 
              borderRadius: BorderRadius.circular(15),
              boxShadow: isSelected ? [BoxShadow(color: color.withAlpha(80), blurRadius: 10)] : null,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isSelected ? color : Colors.grey)),
      ],
    );
  }

  Widget _buildHeader(double width) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(
        color: AppColors.tealText,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Driver Dashboard", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
              _buildHeaderIcon(Icons.logout, () => _showLogoutDialog(context)),
            ],
          ),
          const SizedBox(height: 12),
          Text(_user?.name ?? "Driver Name", style: TextStyle(color: Colors.white, fontSize: width > 600 ? 42 : 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text("Truck: ${_user?.preferredTruck ?? 'GT-001'}", style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(width: 16),
              _buildStatusIndicator(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    Color color = switch(_status) {
      "ACTIVE" => Colors.greenAccent,
      "IDLE" => Colors.yellowAccent,
      "FULL" => Colors.orangeAccent,
      "FINISHED" => Colors.blueAccent,
      _ => Colors.white70,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(_status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildOperationsGrid(double width) {
    int crossAxisCount = width > 900 ? 3 : 2;
    double cardWidth = (width - (width > 900 ? 80 : 40) - ((crossAxisCount - 1) * 16)) / crossAxisCount;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildMetricCard("Efficiency", "${((_completedCount / _totalPuroks) * 100).toStringAsFixed(1)}%", Icons.auto_awesome, Colors.green, cardWidth),
        _buildMetricCard("Progress", "$_completedCount / $_totalPuroks", Icons.checklist_rtl, Colors.orange, cardWidth),
        _buildMetricCard("Manual Alert", "Notify", Icons.notifications_active, Colors.blue, cardWidth, onTap: () => _showAreaSelection("Manual Alert", _sendManualAlert)),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, double width, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 15, offset: const Offset(0, 5))],
          border: Border.all(color: Colors.black.withAlpha(5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2C3E50)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildMapCard(double width) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.map_rounded, color: Colors.teal, size: 22),
                const SizedBox(width: 12),
                const Text("Live Route Tracking", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2C3E50))),
              ],
            ),
          ),
          Container(
            height: 400,
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: DriverTrackTruckScreen(
                key: const ValueKey("driver_map_tracking"), // Stabilize the map widget
                isEmbedded: true, 
                currentSessionId: _sessionId,
                focusTruckId: _user?.preferredTruck ?? "GT-001",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressTracker(double width) {
    List<Map<String, dynamic>> sortedPuroks = List.from(_purokConfigs);
    sortedPuroks.sort((a, b) => (a['order'] ?? 0).compareTo(b['order'] ?? 0));
    
    List<Map<String, dynamic>> visiblePuroks = _isPuroksExpanded ? sortedPuroks : sortedPuroks.take(3).toList();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Collection Progress Tracker", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2C3E50))),
              Text("${((_completedCount / _totalPuroks) * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.tealText, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 20),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visiblePuroks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _buildPurokStatusCard(visiblePuroks[index]['name']),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _isPuroksExpanded = !_isPuroksExpanded),
              child: Text(_isPuroksExpanded ? "Show Less" : "View All Puroks (${_totalPuroks})", style: const TextStyle(color: AppColors.tealText, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurokStatusCard(String name) {
    String key = name.replaceAll('/', '_');
    var statusData = _purokStatus[key] ?? {'completed': false};
    bool completed = statusData['completed'] ?? false;
    String completedAt = statusData['completedAt'] ?? "Pending";

    Color bgColor = completed ? Colors.green.shade50 : Colors.grey.shade100;
    Color iconColor = completed ? Colors.green : Colors.grey;
    IconData icon = completed ? Icons.check_circle : Icons.location_on;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20), border: completed ? Border.all(color: Colors.green, width: 1.5) : null),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 16),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF2C3E50)))),
          Text(completed ? "Done ($completedAt)" : "Pending", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: iconColor)),
        ],
      ),
    );
  }

  void _sendManualAlert(String area) async {
    if (_sessionId == null) return;
    final truckId = _user?.preferredTruck ?? "GT-001";
    String areaKey = area.replaceAll('/', '_');
    await _database.ref('notifications').push().set({'type': 'manual_alert', 'title': 'Garbage Truck Update', 'message': 'The garbage truck is now approaching $area.', 'area': area, 'truck_id': truckId, 'timestamp': ServerValue.timestamp, 'isRead': false});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Alert sent for $area")));
  }

  void _showAreaSelection(String title, Function(String) onSelect) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(height: MediaQuery.of(context).size.height * 0.8, decoration: const BoxDecoration(color: Color(0xFF424242), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))), Padding(padding: const EdgeInsets.all(24), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))), Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 8), itemCount: _purokConfigs.length, itemBuilder: (context, i) => ListTile(title: Text(_purokConfigs[i]['name'], style: const TextStyle(color: Colors.white, fontSize: 16)), contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), onTap: () { Navigator.pop(context); onSelect(_purokConfigs[i]['name']); })))])),);
  }

  Widget _buildHeaderIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withAlpha(40), shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)));
  }

  void _showFinishConfirmation() {
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text("Finish Trip?"), content: const Text("This will complete the current session."), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")), TextButton(onPressed: () { Navigator.pop(context); _finishTrip(); }, child: const Text("DONE"))]));
  }

  Future<void> _handleLogout() async {
    // 1. Stop all tracking immediately
    _positionSubscription?.cancel();
    _idleDetectionTimer?.cancel();
    _statusSubscription?.cancel();
    _purokStatusSubscription?.cancel();

    final truckId = _user?.preferredTruck ?? "GT-001";
    final driverId = _user?.userId ?? "Unknown";

    try {
      // 2. Update Firebase status to OFFLINE before signing out
      await _database.ref('truck_locations').child(truckId).update({
        'status': 'OFFLINE',
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // 3. Optional: End the session if it exists
      if (_sessionId != null) {
        await _database.ref('driver_routes').child(_sessionId!).update({
          'isOnline': false,
          'lastSeen': ServerValue.timestamp,
        });
      }

      await SystemLogger.logEvent("LOGOUT", "Driver $driverId logged out. Truck $truckId set to OFFLINE.");
    } catch (e) {
      debugPrint("Error during status update on logout: $e");
    }

    // 4. Clear session and navigate
    await SessionManager.logout();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text("Sign Out?"), 
        content: const Text("End duty and log out? This will set your status to OFFLINE."), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")), 
          TextButton(
            onPressed: () { 
              Navigator.pop(context); 
              _handleLogout(); 
            }, 
            child: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red))
          )
        ]
      )
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: AppColors.tealText,
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          if (i == 0) _loadUser();
          setState(() => _selectedIndex = i);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
