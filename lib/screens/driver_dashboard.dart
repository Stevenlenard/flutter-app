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
  DateTime? _startDateTime;
  double _distance = 0.0;
  int _completedCount = 0;
  final int _totalPuroks = 13;
  int _selectedIndex = 0;
  bool _isPuroksExpanded = false;
  int _unreadNotifications = 0;
  bool _isSimulationMode = false;
  Timer? _simulationTimer;
  bool _isDebugPanelExpanded = false; // Collapsible Debug Panel

  // DEVELOPER TEST OVERRIDE
  String _testStatusOverride = "AUTO"; // AUTO, FORCE ACTIVE, FORCE IDLE, FORCE FULL

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
  DateTime? _lastGpsUpdateTime;
  Timer? _idleDetectionTimer;
  bool _isInitializing = true;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _purokStatusSubscription;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _routePointsSubscription;

  List<Map> _tripRoutePoints = [];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _positionSubscription?.cancel();
    _idleDetectionTimer?.cancel();
    _statusSubscription?.cancel();
    _purokStatusSubscription?.cancel();
    _notificationSubscription?.cancel();
    _routePointsSubscription?.cancel();
    super.dispose();
  }

  void _loadUser() async {
    _user = await SessionManager.getUser();
    if (_user != null) {
      if (mounted) setState(() {});
      _setupListeners();
      
      // Check if there's already an active session in truck_locations
      final truckId = _user?.preferredTruck ?? "GT-001";
      final snapshot = await _database.ref('truck_locations/$truckId/current_session').get();
      
      if (snapshot.exists && snapshot.value != null) {
        _sessionId = snapshot.value.toString();
        debugPrint("[SESSION] Resuming existing session: $_sessionId");
        _setupPurokListener();
        _setupRoutePointsListener();
        _startTracking();
        _startIdleDetection();
        
        // Ensure we are marked as Online/Active when returning to dashboard
        _database.ref('truck_locations').child(truckId).update({
          'isOnline': true,
          'status': 'ACTIVE',
          'lastSeen': ServerValue.timestamp,
        });
      } else {
        debugPrint("[SESSION] No active session found. Starting new trip...");
        _startTripSession(); 
      }
    }
  }

  void _setupListeners() {
    final truckId = _user?.preferredTruck ?? "GT-001";
    _statusSubscription?.cancel();
    _statusSubscription = _database.ref('truck_locations').child(truckId).onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        if (mounted) {
          setState(() {
            _status = data['status']?.toString().toUpperCase() ?? "OFFLINE";
            _distance = (data['distance'] ?? 0.0).toDouble();
            if (data['start_time'] != null) _startTime = data['start_time'];
          });
        }
      }
    });

    _notificationSubscription?.cancel();
    _notificationSubscription = _database.ref('notifications').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        int unread = 0;
        data.forEach((k, v) {
          if (v['isRead'] == false && v['truck_id'] == _user?.preferredTruck) unread++;
        });
        if (mounted) setState(() => _unreadNotifications = unread);
      }
    });

    // --- NEW: CONNECTION RECOVERY LOGIC ---
    _database.ref('.info/connected').onValue.listen((event) {
      final bool isConnected = event.snapshot.value == true;
      if (isConnected && _sessionId != null && _user != null) {
        debugPrint("[CONNECTION] Reconnected. Restoring active status...");
        // If we have an active session, ensure we are ACTIVE and Online
        _database.ref('truck_locations').child(_user?.preferredTruck ?? "GT-001").update({
           'isOnline': true,
           'status': (_status.contains("LOST") || _status == "OFFLINE") ? "ACTIVE" : _status,
           'updatedAt': DateTime.now().toIso8601String(),
        });
        if (mounted) setState(() {
           if (_status.contains("LOST") || _status == "OFFLINE") _status = "ACTIVE";
        });
      } else if (!isConnected && _status != "OFFLINE") {
        debugPrint("[CONNECTION] Lost. Setting local status to IDLE.");
        if (mounted) setState(() => _status = "IDLE (LOST)");
      }
    });
  }

  void _setupRoutePointsListener() {
    if (_sessionId == null) return;
    _routePointsSubscription?.cancel();
    _routePointsSubscription = _database.ref('driver_routes/$_sessionId/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map> list = [];
        data.forEach((k, v) => list.add(v as Map));
        list.sort((a, b) => (a['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
        if (mounted) setState(() => _tripRoutePoints = list);
      }
    });
  }

  void _setupPurokListener() {
    if (_sessionId == null) return;
    _purokStatusSubscription?.cancel();
    _purokStatusSubscription = _database.ref('collection_progress').child(_sessionId!).onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
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
      Position startPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.bestForNavigation);

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
        'start_lat': startPos.latitude,
        'start_lng': startPos.longitude,
        'start_accuracy': startPos.accuracy,
      });

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

      // CRITICAL: First route point must be EXACTLY the start point
      _appendRoutePoint(startPos, "ACTIVE", "GREEN");

      if (mounted) {
        setState(() {
          _status = "ACTIVE";
          _startTime = timeStr;
          _distance = 0.0;
          _currentPosition = startPos;
          _isInitializing = false;
          _lastGpsUpdateTime = DateTime.now();
          _completedCount = 0; // Reset count locally
          _purokStatus = {}; // Clear previous trip progress
          _autoNotifiedPuroks.clear(); 
          _approachNotifiedPuroks.clear();
        });
      }
      _setupPurokListener();
      _setupRoutePointsListener();
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
        distanceFilter: 0, // 0 for max sensitivity during tests
      ),
    ).listen((pos) => _processNewPosition(pos));
  }

  void _processNewPosition(Position pos) {
    if (_sessionId == null || _status == "OFFLINE" || _status == "FINISHED") return;
    
    // STRICT GPS FILTER FOR PRODUCTION WALKING TEST
    // Reject extremely poor accuracy readings (e.g., 20000m)
    if (pos.accuracy > 50 && !_isSimulationMode) {
      debugPrint("[GPS FILTER] Rejected point due to poor accuracy: ${pos.accuracy}m");
      return;
    }

    final truckId = _user?.preferredTruck ?? "GT-001";
    
    double traveled = 0;
    bool movedSignificantly = false;

    if (_currentPosition != null) {
      // Calculate real distance walked/traveled between consecutive points
      traveled = Geolocator.distanceBetween(
        _currentPosition!.latitude, 
        _currentPosition!.longitude, 
        pos.latitude, 
        pos.longitude
      ) / 1000.0; // convert to km
      
      // Filter out micro-jitter (less than 2 meters)
      if (traveled >= 0.002) {
        movedSignificantly = true;
      } else {
        traveled = 0;
      }
    } else {
      // First point after start session
      movedSignificantly = true;
    }

    _lastGpsUpdateTime = DateTime.now();
    double speedKmH = (pos.speed * 3.6);

    // 1. GPS NOISE FILTERING
    bool isAccurate = pos.accuracy < 50.0; // Slightly more lenient (50m)
    bool movedFarEnough = traveled > 0.0025; // Must move at least 2.5 meters for smoothing

    // Debug raw vs accepted
    debugPrint("[GPS MASTER] RAW: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)} | ACC: ${pos.accuracy.toStringAsFixed(1)}m | SPEED: ${speedKmH.toStringAsFixed(1)}km/h");

    if (!isAccurate && !_isSimulationMode) {
      debugPrint("[GPS REJECTED] Poor Accuracy: ${pos.accuracy.toStringAsFixed(1)}m");
      return;
    }

    if (mounted) {
      setState(() {
        if (movedFarEnough || _currentPosition == null || _isSimulationMode) {
          _distance += traveled;
          _currentPosition = pos;
          debugPrint("[GPS ACCEPTED] LAT: ${pos.latitude}, LNG: ${pos.longitude} | Dist: ${traveled * 1000}m | Accuracy: ${pos.accuracy}m");
        } else {
          debugPrint("[GPS FILTERED] Moved only ${traveled * 1000}m (Threshold: 2.5m)");
        }
        
        // Auto-status logic (Only if not overridden)
        if (_testStatusOverride == "AUTO") {
          if (speedKmH > 1.2 && _status == "IDLE") {
            _updateTripStatus("ACTIVE");
          }
        }
      });
    }

    _checkPurokProximity(pos);

    double avgSpeed = 0.0;
    if (_startDateTime != null) {
      final durationHrs = DateTime.now().difference(_startDateTime!).inSeconds / 3600.0;
      if (durationHrs > 0) avgSpeed = _distance / durationHrs;
    }

    // Determine Status for this specific point (respecting override)
    String effectiveStatus = _getEffectiveRouteStatus();
    String trailColor = _getTrailColorForStatus(effectiveStatus);

    _database.ref('truck_locations').child(truckId).update({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'distance': _distance,
      'speed': speedKmH,
      'avg_speed': avgSpeed,
      'heading': pos.heading,
      'accuracy': pos.accuracy,
      'status': effectiveStatus, 
      'isOnline': true,
      'lastSeen': ServerValue.timestamp,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    if (movedFarEnough || _tripRoutePoints.isEmpty || _isSimulationMode) {
      _appendRoutePoint(pos, effectiveStatus, trailColor);
    }
  }

  String _getEffectiveRouteStatus() {
    if (_testStatusOverride != "AUTO") {
      return _testStatusOverride.replaceFirst("FORCE ", "");
    }
    // Normalize status for route points
    if (_status.contains("IDLE")) return "IDLE";
    if (_status.contains("FULL")) return "FULL";
    if (_status.contains("FINISHED")) return "FINISHED";
    return "ACTIVE";
  }

  String _getTrailColorForStatus(String status) {
    switch (status.toUpperCase()) {
      case "IDLE": return "YELLOW";
      case "FULL": return "PINK";
      case "FINISHED": return "BLACK";
      default: return "GREEN";
    }
  }

  void _checkPurokProximity(Position pos) {
    if (_sessionId == null) return;
    
    // STRICTER GPS PROXIMITY: Only trigger if accuracy is good
    if (pos.accuracy > 50 && !_isSimulationMode) {
      debugPrint("[PROXIMITY] Skipping due to poor accuracy: ${pos.accuracy}");
      return;
    }

    for (var p in _purokConfigs) {
      String key = p['name'].replaceAll('/', '_');
      
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, p['lat'], p['lng']);

      // --- NEW: APPROACH DETECTION (300 meters) ---
      if (dist <= 300 && dist > 50) {
        _handleApproachNotification(p['name'], dist);
      }
      
      // Already completed in this session? Skip completion logic.
      if (_purokStatus[key]?['completed'] == true) continue;
      
      // Logic: Must be within 50 meters AND moving slowly (or simulation)
      bool speedValid = _isSimulationMode || (pos.speed * 3.6) < 15.0; 

      if (dist <= 50 && speedValid) {
        _database.ref('collection_progress').child(_sessionId!).child(key).update({
          'completed': true,
          'completedAt': DateFormat('h:mm a').format(DateTime.now()),
          'timestamp': ServerValue.timestamp,
          'completionSource': _isSimulationMode ? 'SIMULATION' : 'GPS_PROXIMITY',
          'accuracyAtTrigger': pos.accuracy,
          'distanceToCenter': dist,
        });
        
        _database.ref('truck_locations').child(_user?.preferredTruck ?? "GT-001").update({'current_purok': p['name']});
        
        // --- NEW: Automatic Approach/Arrival Notifications ---
        _handleAutoNotifications(p['name'], dist);
        
        debugPrint("[PROXIMITY] Triggered for ${p['name']} at dist: ${dist.toStringAsFixed(1)}m");
      }
    }
  }

  final Set<String> _autoNotifiedPuroks = {};

  void _handleAutoNotifications(String areaName, double distance) async {
    if (_autoNotifiedPuroks.contains(areaName)) return;
    
    final truckId = _user?.preferredTruck ?? "GT-001";
    
    // 1. Send "Arrived" notification to Firebase
    await _database.ref('notifications').push().set({
      'type': 'auto_arrival',
      'title': 'Garbage Truck Arrived',
      'message': 'The garbage truck ($truckId) has arrived in $areaName.',
      'purok': areaName,
      'truck_id': truckId,
      'timestamp': ServerValue.timestamp,
      'isRead': false
    });
    
    _autoNotifiedPuroks.add(areaName);
    debugPrint("[AUTO-NOTIFY] Sent arrival alert for $areaName");
  }

  final Set<String> _approachNotifiedPuroks = {};

  void _handleApproachNotification(String areaName, double distance) async {
    if (_approachNotifiedPuroks.contains(areaName)) return;
    
    final truckId = _user?.preferredTruck ?? "GT-001";
    
    // Calculate simple ETA (Assume 15 km/h for arrival)
    double speedMps = 15 / 3.6; 
    int etaMinutes = (distance / speedMps / 60).ceil();
    if (etaMinutes < 1) etaMinutes = 1;

    await _database.ref('notifications').push().set({
      'type': 'auto_approach',
      'title': 'Garbage Truck Approaching',
      'message': 'Truck $truckId is on the way to $areaName. Estimated arrival: $etaMinutes min.',
      'purok': areaName,
      'truck_id': truckId,
      'timestamp': ServerValue.timestamp,
      'isRead': false
    });
    
    _approachNotifiedPuroks.add(areaName);
    debugPrint("[AUTO-NOTIFY] Sent approach alert for $areaName (ETA: $etaMinutes)");
  }

  void _appendRoutePoint(Position pos, String status, String color) {
    if (_sessionId == null) return;
    // Use local timestamp for immediate consistent sorting in map views
    final int ts = DateTime.now().millisecondsSinceEpoch;
    _database.ref('driver_routes').child(_sessionId!).child('route').push().set({
      'lat': pos.latitude, 'lng': pos.longitude, 'status': status, 'color': color,
      'speed': pos.speed * 3.6, 'heading': pos.heading, 'accuracy': pos.accuracy, 
      'timestamp': ts,
    });
  }

  void _startIdleDetection() {
    _idleDetectionTimer?.cancel();
    _idleDetectionTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_currentPosition == null || _status == "OFFLINE" || _status == "FINISHED" || _status == "IDLE") return;
      if (_lastGpsUpdateTime != null && DateTime.now().difference(_lastGpsUpdateTime!).inMinutes >= 2) {
        _updateTripStatus("IDLE");
      }
    });
  }

  Future<void> _updateTripStatus(String newStatus) async {
    final truckId = _user?.preferredTruck ?? "GT-001";
    await _database.ref('truck_locations').child(truckId).update({
      'status': newStatus.toUpperCase(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    if (mounted) setState(() => _status = newStatus);
  }

  bool _isFinishing = false; // Added to prevent multiple finish calls

  Future<void> _finishTrip() async {
    if (_sessionId == null || _isFinishing) return;
    
    setState(() => _isFinishing = true);
    final String sessionToFinalize = _sessionId!;
    final truckId = _user?.preferredTruck ?? "GT-001";
    
    try {
      await _database.ref('driver_routes').child(sessionToFinalize).update({
        'route_status': 'COMPLETED',
        'end_time': DateFormat('h:mm a').format(DateTime.now()),
        'finish_lat': _currentPosition?.latitude,
        'finish_lng': _currentPosition?.longitude,
        'final_distance': _distance,
      });

      // Add final black segment point
      if (_currentPosition != null) {
        _appendRoutePoint(_currentPosition!, "FINISHED", "BLACK");
      }

      await _database.ref('truck_locations').child(truckId).update({'status': 'finished', 'current_session': null});
      _positionSubscription?.cancel();
      if (mounted) {
        setState(() { 
          _status = "FINISHED"; 
          _sessionId = null; 
          _startTime = "--:--"; 
          _isFinishing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trip Finished successfully.")));
      }
    } catch (e) {
      if (mounted) setState(() => _isFinishing = false);
      debugPrint("Finish Trip Error: $e");
    }
  }

  void _handleSimulationToggle() {
    if (_isSimulationMode) {
      setState(() {
        _isSimulationMode = false;
        _simulationTimer?.cancel();
        _startTracking();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Simulation stopped. Returning to Real GPS.")));
    } else {
      _showAreaSelection("Select Simulation Location", (area) {
        setState(() => _isSimulationMode = true);
        _startSimulationAt(area);
      });
    }
  }

  void _startSimulationAt(String areaName) {
    _positionSubscription?.cancel();
    _simulationTimer?.cancel();
    
    // 1. Find the Purok in our config
    final config = _purokConfigs.firstWhere(
      (p) => p['name'] == areaName,
      orElse: () => _purokConfigs.first,
    );

    debugPrint("[SIMULATION] Starting at ${config['name']} (${config['lat']}, ${config['lng']})");

    void sendSimulatedUpdate(Map<String, dynamic> targetPurok) {
      final pos = Position(
        latitude: targetPurok['lat'], 
        longitude: targetPurok['lng'], 
        timestamp: DateTime.now(), 
        accuracy: 5.0, // High accuracy for simulation
        altitude: 0, heading: 0, speed: 15.0,
        speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
      );
      
      // Update local state for Map to pick up
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }

      // This will update truck_locations and trigger proximity checks
      _processNewPosition(pos);
    }

    // Move to the selected Purok instantly
    sendSimulatedUpdate(config);
  }

  void _sendManualAlert(String area) async {
    if (_sessionId == null) return;
    final truckId = _user?.preferredTruck ?? "GT-001";
    
    try {
      // 1. Send Notification (Target specific Purok residents)
      await _database.ref('notifications').push().set({
        'type': 'manual_alert', 
        'title': 'Garbage Truck Update',
        'message': 'The garbage truck is now approaching $area.',
        'purok': area, // FILTERED BY PUROK
        'truck_id': truckId, 
        'timestamp': ServerValue.timestamp, 
        'isRead': false
      });

      // 2. Mark ONLY selected Purok as Completed in the current session
      String key = area.replaceAll('/', '_');
      await _database.ref('collection_progress').child(_sessionId!).child(key).update({
        'completed': true,
        'completedAt': DateFormat('h:mm a').format(DateTime.now()),
        'timestamp': ServerValue.timestamp,
        'completionSource': 'MANUAL_ALERT',
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Alert sent and $area marked as visited.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send alert: $e")));
    }
  }

  Future<void> _handleLogout() async {
    _positionSubscription?.cancel();
    final truckId = _user?.preferredTruck ?? "GT-001";
    await _database.ref('truck_locations').child(truckId).update({'status': 'OFFLINE', 'isOnline': false, 'lastSeen': ServerValue.timestamp});
    await SessionManager.logout();
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, constraints) {
            return IndexedStack(
              index: _selectedIndex,
              children: [
                _buildResponsiveDashboard(constraints),
                DriverTrackTruckScreen(
                  isEmbedded: true, 
                  currentSessionId: _sessionId, 
                  focusTruckId: _user?.preferredTruck ?? "GT-001", 
                  onBack: () => setState(() => _selectedIndex = 0),
                  isSimulation: _isSimulationMode,
                  manualPosition: _currentPosition, // ALWAYS pass current position from the main tracking service
                ),
                DriverSettingsScreen(isEmbedded: true, onBack: () => setState(() => _selectedIndex = 0), currentSessionId: _sessionId),
              ],
            );
          }),
          // COLLAPSIBLE DEBUG OVERLAY & WALK TEST PANEL
          Positioned(
            top: 100, left: 10,
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isDebugPanelExpanded = !_isDebugPanelExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("DEBUG PANEL", style: TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                          Icon(_isDebugPanelExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white70, size: 14),
                        ],
                      ),
                    ),
                  ),
                  if (_isDebugPanelExpanded) ...[
                    const Divider(color: Colors.white24, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("TRIP: ${_sessionId ?? 'none'}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                          Text("CURRENT STATUS: $_status", style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                          Text("EFFECTIVE ROUTE STATUS: ${_getEffectiveRouteStatus()}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          if (_startDateTime != null)
                            Text("START: ${_tripRoutePoints.isNotEmpty ? _tripRoutePoints.first['lat'] : '...' }, ${_tripRoutePoints.isNotEmpty ? _tripRoutePoints.first['lng'] : '...'}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                          Text("GPS: ${_currentPosition != null ? 'LOCKED' : 'SEARCHING'}", style: TextStyle(color: _currentPosition != null ? Colors.greenAccent : Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          if (_currentPosition != null) ...[
                            Text("LAT: ${_currentPosition!.latitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                            Text("LNG: ${_currentPosition!.longitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                            Text("ACCURACY: ${_currentPosition!.accuracy.toStringAsFixed(1)}m", style: TextStyle(color: _currentPosition!.accuracy < 20 ? Colors.greenAccent : Colors.orangeAccent, fontSize: 8)),
                          ],
                          const SizedBox(height: 4),
                          Text("ROUTE POINTS: ${_tripRoutePoints.length}", style: const TextStyle(color: Colors.white, fontSize: 8)),
                          _buildDebugCounter("ACTIVE POINTS", "ACTIVE"),
                          _buildDebugCounter("IDLE POINTS", "IDLE"),
                          _buildDebugCounter("FULL POINTS", "FULL"),
                          const SizedBox(height: 4),
                          Text("DISTANCE: ${_distance.toStringAsFixed(3)} km", style: const TextStyle(color: Colors.white, fontSize: 9)),
                          Text("MAP ROUTE: ${_sessionId != null ? 'VISIBLE' : 'HIDDEN'}", style: const TextStyle(color: Colors.white, fontSize: 8)),
                          const SizedBox(height: 8),
                          const Text("FORCE STATUS COLOR:", style: TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          _buildOverrideButtons(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildDebugCounter(String label, String status) {
    int count = _tripRoutePoints.where((p) => (p['status'] ?? '').toString().toUpperCase() == status).length;
    Color color = Colors.white70;
    if (status == "ACTIVE") color = Colors.greenAccent;
    if (status == "IDLE") color = Colors.yellowAccent;
    if (status == "FULL") color = Colors.pinkAccent;
    return Text("$label: $count", style: TextStyle(color: color, fontSize: 7));
  }

  Widget _buildResponsiveDashboard(BoxConstraints constraints) {
    double width = constraints.maxWidth;
    return SingleChildScrollView(
      child: Column(children: [
        _buildHeader(width),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              Expanded(child: _buildMetricCard("Start Time", _startTime, Icons.access_time_filled, Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard("Distance", "${_distance.toStringAsFixed(2)} km", Icons.route, Colors.purple)),
            ]),
            const SizedBox(height: 24),
            _buildVehicleControls(),
            const SizedBox(height: 24),
            _buildActionsGrid(width),
            const SizedBox(height: 24),
            _buildMapCard(width),
            const SizedBox(height: 24),
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
          Row(children: [
            _buildHeaderIcon(Icons.notifications_none_rounded, badge: _unreadNotifications > 0 ? "$_unreadNotifications" : null, onTap: () => _showAlertHistory()),
            const SizedBox(width: 12),
            _buildHeaderIcon(Icons.logout, onTap: () => _showLogoutDialog(context)),
          ]),
        ]),
        const SizedBox(height: 12),
        Text(_user?.name ?? "Driver Name", style: TextStyle(color: Colors.white, fontSize: width > 600 ? 42 : 32, fontWeight: FontWeight.w900)),
        Row(children: [
          Text("Truck: ${_user?.preferredTruck ?? 'GT-001'}", style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(width: 16),
          _buildStatusIndicator(),
        ]),
      ]),
    );
  }

  Widget _buildHeaderIcon(IconData icon, {String? badge, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Stack(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)),
        if (badge != null) Positioned(right: 0, top: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 8)))),
      ]),
    );
  }

  Color _buildStatusIndicatorColor() {
    switch(_status) {
      case "ACTIVE": return Colors.greenAccent;
      case "IDLE": return Colors.yellowAccent;
      case "FULL": return Colors.orangeAccent;
      default: return Colors.white70;
    }
  }

  Widget _buildStatusIndicator() {
    Color color = _buildStatusIndicatorColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
      child: Text(_status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 15)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w700)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _buildVehicleControls() {
    return Container(
      padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(30)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Vehicle Controls", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _buildOpButton("START", Icons.play_arrow, Colors.teal, () => _updateTripStatus("ACTIVE")),
          _buildOpButton("PAUSE", Icons.pause, Colors.orange, () => _updateTripStatus("IDLE")),
          _buildOpButton("FULL", Icons.local_shipping, Colors.pink, () => _updateTripStatus("FULL")),
          _buildOpButton("DONE", Icons.check, Colors.blue, _showFinishConfirmation),
        ]),
      ]),
    );
  }

  Widget _buildOpButton(String label, IconData icon, Color color, VoidCallback onTap) {
    bool isSelected = _status == label;
    return Column(children: [
      InkWell(onTap: onTap, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: isSelected ? color : color.withOpacity(0.5), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white))),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isSelected ? color : Colors.grey)),
    ]);
  }

  Widget _buildActionsGrid(double width) {
    return GridView.count(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: width > 600 ? 3 : 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.3,
      children: [
        _buildActionCard("Manual Alert", Icons.notifications_active, Colors.blue, () => _showAreaSelection("Manual Alert", _sendManualAlert)),
        _buildActionCard(_isSimulationMode ? "Real GPS" : "Simulation", Icons.directions_run, _isSimulationMode ? Colors.orange : Colors.purple, _handleSimulationToggle),
        _buildActionCard("Progress: $_completedCount / $_totalPuroks", Icons.checklist_rtl, Colors.green, () => setState(() => _selectedIndex = 0)),
      ],
    );
  }

  Widget _buildActionCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
      ]),
    ));
  }

  Widget _buildMapCard(double width) {
    return Container(
      height: 400, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30), 
        child: DriverTrackTruckScreen(
          isEmbedded: true, 
          currentSessionId: _sessionId, 
          focusTruckId: _user?.preferredTruck ?? "GT-001",
          isSimulation: _isSimulationMode,
          manualPosition: _currentPosition, // Pass current position for real-time dashboard tracking
        )
      ),
    );
  }

  Widget _buildProgressTracker() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 20)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Collection Progress", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text("${((_completedCount / _totalPuroks) * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.tealText, fontSize: 18)),
        ]),
        const SizedBox(height: 20),
        ListView.separated(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: _isPuroksExpanded ? _purokConfigs.length : 3,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final p = _purokConfigs[i];
            final String key = p['name'].replaceAll('/', '_');
            final statusData = _purokStatus[key] ?? {'completed': false};
            bool done = statusData['completed'] == true;
            String source = statusData['completionSource'] ?? "";
            
            return Container(
              padding: const EdgeInsets.all(16), 
              decoration: BoxDecoration(
                color: done ? Colors.green.shade50 : Colors.grey.shade50, 
                borderRadius: BorderRadius.circular(16),
                border: done ? Border.all(color: Colors.green.withOpacity(0.3)) : null,
              ),
              child: Row(children: [
                Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? Colors.green : Colors.grey), 
                const SizedBox(width: 12), 
                Expanded(child: Text(p['name'], style: TextStyle(fontWeight: FontWeight.w700, color: done ? Colors.green.shade900 : Colors.black87))),
                if (done && source.isNotEmpty)
                  Text(source, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
              ]),
            );
          },
        ),
        Center(child: TextButton(onPressed: () => setState(() => _isPuroksExpanded = !_isPuroksExpanded), child: Text(_isPuroksExpanded ? "Show Less" : "View All Puroks"))),
      ]),
    );
  }

  void _showAreaSelection(String title, Function(String) onSelect) {
    showModalBottomSheet(context: context, builder: (context) => Container(padding: const EdgeInsets.all(24), child: Column(children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Expanded(child: ListView.builder(itemCount: _purokConfigs.length, itemBuilder: (context, i) => ListTile(title: Text(_purokConfigs[i]['name']), onTap: () { Navigator.pop(context); onSelect(_purokConfigs[i]['name']); })))])),);
  }

  void _showFinishConfirmation() {
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text("Finish Trip?"), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")), TextButton(onPressed: () { Navigator.pop(context); _finishTrip(); }, child: const Text("FINISH"))]));
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text("Logout?"), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")), TextButton(onPressed: () { Navigator.pop(context); _handleLogout(); }, child: const Text("LOGOUT", style: TextStyle(color: Colors.red)))]));
  }

  void _showAlertHistory() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: AppColors.tealText, size: 28),
                  SizedBox(width: 12),
                  Expanded(child: Text("Alert History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
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
                        if (val['truck_id'] == _user?.preferredTruck) {
                          list.add({...val, 'id': k});
                        }
                      });
                      
                      if (list.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No alerts found.")));
                      
                      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                      
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (c, i) => const Divider(),
                        itemBuilder: (c, i) {
                          final item = list[i];
                          return ListTile(
                            title: Text(item['title'] ?? 'Alert', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(item['message'] ?? ''),
                            onTap: () => _database.ref('notifications/${item['id']}').update({'isRead': true}),
                          );
                        },
                      );
                    }
                    return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No alerts yet.")));
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

  Widget _buildOverrideButtons() {
    return Column(
      children: [
        _buildOverrideOption("AUTO", Colors.white),
        _buildOverrideOption("FORCE ACTIVE", Colors.greenAccent),
        _buildOverrideOption("FORCE IDLE", Colors.yellowAccent),
        _buildOverrideOption("FORCE FULL", Colors.pinkAccent),
      ],
    );
  }

  Widget _buildOverrideOption(String label, Color color) {
    bool isSelected = _testStatusOverride == label;
    return InkWell(
      onTap: () => setState(() => _testStatusOverride = label),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? color : Colors.white10),
        ),
        child: Text(
          label, 
          style: TextStyle(color: isSelected ? color : Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(currentIndex: _selectedIndex, selectedItemColor: AppColors.tealText, items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'), BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'), BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings')], onTap: (i) => setState(() => _selectedIndex = i));
  }
}
