import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/app_theme.dart';

class DriverTrackTruckScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  final String? currentSessionId;
  final String? focusTruckId;
  final geo.Position? manualPosition;
  final bool isSimulation;
  
  const DriverTrackTruckScreen({
    super.key, 
    this.isEmbedded = false, 
    this.onBack,
    this.currentSessionId,
    this.focusTruckId,
    this.manualPosition,
    this.isSimulation = false,
  });

  @override
  State<DriverTrackTruckScreen> createState() => _DriverTrackTruckScreenState();
}

class _DriverTrackTruckScreenState extends State<DriverTrackTruckScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  
  PointAnnotationManager? _pointAnnotationManager;
  CircleAnnotationManager? _circleAnnotationManager;
  
  final Map<String, PointAnnotation> _truckMarkers = {};
  
  List<Map> _lastPoints = [];
  bool _hasInitialGpsFocus = false;
  StreamSubscription? _truckSubscription;
  StreamSubscription? _routeSubscription;
  StreamSubscription? _localGpsSubscription;
  
  Map<dynamic, dynamic>? _lastTruckData;
  geo.Position? _lastLocalPos;

  final Position _balintawakCenter = Position(121.1623, 13.9413);

  bool _managersReady = false;
  bool _driverSourceCreated = false;
  bool _routeSourceCreated = false;

  // NEW: Session Meta Persistence
  Map? _lastSessionData;

  // NEW: Follow Mode State
  bool _isFollowLocked = true;
  String _currentStatus = "ACTIVE";

  @override
  void initState() {
    super.initState();
    if (widget.manualPosition != null) {
      _lastLocalPos = widget.manualPosition;
    }
    _checkPermissionAndStartGps();
    _listenToTrucks();
    _listenToRoute();
  }

  @override
  void didUpdateWidget(covariant DriverTrackTruckScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.manualPosition != null) {
      final bool hasChanged = oldWidget.manualPosition == null || 
                              widget.manualPosition!.latitude != oldWidget.manualPosition!.latitude ||
                              widget.manualPosition!.longitude != oldWidget.manualPosition!.longitude;
      
      if (hasChanged) {
        debugPrint("[DRIVER MAP] Manual position updated: ${widget.manualPosition!.latitude}, ${widget.manualPosition!.longitude}");
        setState(() {
          _lastLocalPos = widget.manualPosition;
        });
        _updateLocalDriverMarker(widget.manualPosition!);
        
        // Auto-follow logic
        if (_isFollowLocked && mapboxMap != null) {
          mapboxMap?.setCamera(CameraOptions(
            center: Point(coordinates: Position(widget.manualPosition!.longitude, widget.manualPosition!.latitude)),
          ));
        }
      }
    }

    if (widget.currentSessionId != oldWidget.currentSessionId) {
      if (widget.currentSessionId == null) {
        _routeSubscription?.cancel();
        _clearRoute();
        _lastPoints = [];
      } else {
        _listenToRoute();
      }
    }
  }

  @override
  void dispose() {
    _truckSubscription?.cancel();
    _routeSubscription?.cancel();
    _localGpsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndStartGps() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
      return;
    }

    try {
      geo.Position pos = await geo.Geolocator.getCurrentPosition(desiredAccuracy: geo.LocationAccuracy.high);
      _lastLocalPos = pos;
      if (mounted) _updateLocalDriverMarker(pos);
    } catch (e) {}

    _localGpsSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.bestForNavigation, distanceFilter: 2),
    ).listen((pos) {
      if (widget.manualPosition != null) return; // Prioritize manual position from dashboard
      if (widget.isSimulation) return;
      if (mounted) setState(() { _lastLocalPos = pos; });
      _updateLocalDriverMarker(pos);
    });
  }

  void _listenToTrucks() {
    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _lastTruckData = event.snapshot.value as Map;
        
        // --- NEW: Dynamic Status Halo Sync ---
        final String tid = (widget.focusTruckId ?? "GT-001").toUpperCase();
        if (_lastTruckData!.containsKey(tid)) {
          final myData = _lastTruckData![tid] as Map;
          final String newStatus = (myData['status'] ?? "ACTIVE").toString().toUpperCase();
          if (newStatus != _currentStatus) {
            setState(() => _currentStatus = newStatus);
            if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
          }
        }

        if (_managersReady) {
          _lastTruckData!.forEach((key, value) {
            _updateSingleTruckMarker(key.toString(), value as Map);
          });
        }
      }
    });
  }

  void _listenToRoute() {
    if (widget.currentSessionId == null) return;
    _routeSubscription?.cancel();
    _routeSubscription = _database.ref('driver_routes/${widget.currentSessionId}').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        _lastSessionData = data;

        if (data['route'] != null) {
          final Map routeData = data['route'] as Map;
          final List<Map> points = [];
          routeData.forEach((key, value) => points.add(value as Map));
          points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
          if (mounted && points.length != _lastPoints.length) {
            _updateRoutePolyline(points);
            _lastPoints = points;
          }
        }
        if (_managersReady) _updateSpecialMarkers(data);
      }
    });
  }

  void _updateSpecialMarkers(Map data) async {
    if (_pointAnnotationManager == null) return;
    if (data['start_lat'] != null && data['start_lng'] != null) {
      _addMarkerIfMissing("SESSION_START", Position(data['start_lng'], data['start_lat']), "START", Colors.blue);
    }
    if (data['finish_lat'] != null && data['finish_lng'] != null) {
      _addMarkerIfMissing("SESSION_FINISH", Position(data['finish_lng'], data['finish_lat']), "🏁 FINISH", Colors.black);
    }
  }

  final Map<String, PointAnnotation> _specialMarkers = {};

  Future<void> _addMarkerIfMissing(String id, Position pos, String label, Color color) async {
    if (_specialMarkers.containsKey(id)) return;
    final marker = await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: Point(coordinates: pos), textField: label, textOffset: [0, -1.5],
      textColor: color.toARGB32(), textSize: 12.0, textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.0, iconSize: 0,
    ));
    if (marker != null) {
      _specialMarkers[id] = marker;
      _circleAnnotationManager?.create(CircleAnnotationOptions(
        geometry: Point(coordinates: pos), circleRadius: 6.0, circleColor: color.toARGB32(), circleStrokeWidth: 2.0, circleStrokeColor: Colors.white.toARGB32(),
      ));
    }
  }

  void _onMapCreated(MapboxMap map) { mapboxMap = map; }

  void _onStyleLoaded(dynamic data) async {
    debugPrint("[DRIVER MAP] Style loaded. Re-initializing layers...");
    
    // CRITICAL: Reset creation flags so layers are re-added to new style
    _driverSourceCreated = false;
    _routeSourceCreated = false;
    _specialMarkers.clear(); // Clear local cache to force redraw

    try {
      await mapboxMap?.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
    } catch (e) {}
    await mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: 14.5));
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      _pointAnnotationManager = await mapboxMap!.annotations.createPointAnnotationManager();
      _circleAnnotationManager = await mapboxMap!.annotations.createCircleAnnotationManager();
    } catch (e) {}
    if (!mounted) return;
    _truckMarkers.clear();
    setState(() => _managersReady = true);
    
    // Restore elements
    if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
    if (_lastTruckData != null) _lastTruckData!.forEach((k, v) => _updateSingleTruckMarker(k.toString(), v as Map));
    if (_lastPoints.isNotEmpty) _updateRoutePolyline(_lastPoints);
    if (_lastSessionData != null) _updateSpecialMarkers(_lastSessionData!);
  }

  Future<void> _updateLocalDriverMarker(geo.Position pos) async {
    final String sourceId = "driver-live-location-source";
    final tid = (widget.focusTruckId ?? "GT-001").toUpperCase();
    final feature = {
      "type": "Feature", 
      "geometry": {"type": "Point", "coordinates": [pos.longitude, pos.latitude]}, 
      "properties": {"name": "DRIVER", "truckId": tid, "status": _currentStatus}
    };

    try {
      final style = mapboxMap!.style;
      if (!_driverSourceCreated) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(feature)));

        // 1. STATUS HALO (Large, semi-transparent)
        await style.addLayer(CircleLayer(
          id: "driver-live-location-halo", 
          sourceId: sourceId, 
          circleRadius: 18.0, 
          circleOpacity: 0.3,
          circleStrokeWidth: 2.0,
          circleSortKey: 2900.0
        ));

        // 2. DRIVER CORE (Identity)
        await style.addLayer(CircleLayer(
          id: "driver-live-location-circle", 
          sourceId: sourceId, 
          circleRadius: 8.0, 
          circleColor: Colors.green.toARGB32(), 
          circleOpacity: 1.0, 
          circleStrokeWidth: 3.0, 
          circleStrokeColor: Colors.white.toARGB32(), 
          circleSortKey: 3000.0
        ));

        await style.addLayer(SymbolLayer(
          id: "driver-live-location-label", 
          sourceId: sourceId, 
          textField: "DRIVER\n$tid", 
          textSize: 14.0, 
          textColor: Colors.green.toARGB32(), 
          textHaloColor: Colors.white.toARGB32(), 
          textHaloWidth: 2.0, 
          textAnchor: TextAnchor.BOTTOM, 
          textOffset: [0, -1.5], 
          symbolSortKey: 3000.0, 
          textAllowOverlap: true, 
          iconAllowOverlap: true
        ));

        // Apply expressions via style properties for compatibility
        final statusColorExpression = [
          "match", ["get", "status"],
          "IDLE", Colors.yellow.toARGB32(),
          "FULL", Colors.pinkAccent.toARGB32(),
          "FINISHED", Colors.black.toARGB32(),
          Colors.green.toARGB32() // ACTIVE
        ];

        await style.setStyleLayerProperty("driver-live-location-halo", "circle-color", statusColorExpression);
        await style.setStyleLayerProperty("driver-live-location-halo", "circle-stroke-color", statusColorExpression);

        if (mounted) setState(() => _driverSourceCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(feature));
      }

      if (_isFollowLocked && !_hasInitialGpsFocus) {
        await mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(pos.longitude, pos.latitude)), zoom: 16.5));
        _hasInitialGpsFocus = true;
      } else if (_isFollowLocked) {
        await mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(pos.longitude, pos.latitude))));
      }
    } catch (e) {}
  }

  void _updateSingleTruckMarker(String id, Map data) {
    if (!_managersReady || _pointAnnotationManager == null) return;
    final String truckId = (data['truck_id'] ?? id).toString();
    if (widget.focusTruckId == truckId) return; 
    final double lat = (data['latitude'] ?? 0.0).toDouble();
    final double lng = (data['longitude'] ?? 0.0).toDouble();
    if (lat == 0.0 || lng == 0.0) return;
    final point = Point(coordinates: Position(lng, lat));
    final String status = (data['status'] ?? "OFFLINE").toString().toUpperCase();
    final int color = status == "IDLE" ? Colors.orange.toARGB32() : Colors.green.toARGB32();
    if (_truckMarkers.containsKey(id)) {
      final marker = _truckMarkers[id]!;
      marker.geometry = point; marker.textField = "$truckId ($status)"; marker.textColor = color;
      _pointAnnotationManager?.update(marker);
    } else {
      _pointAnnotationManager?.create(PointAnnotationOptions(geometry: point, textField: "$truckId ($status)", textOffset: [0, 3.0], textColor: color, textSize: 11, iconSize: 0)).then((m) { if (m != null) _truckMarkers[id] = m; });
    }
  }

  void _updateRoutePolyline(List<Map> points) async {
    if (mapboxMap == null || points.length < 2) { if (points.isEmpty) _clearRoute(); return; }
    
    // 1. Numerical sort by timestamp
    points.sort((a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));

    // 2. Filter / Simplify points to reduce zigzagging
    final List<Map> filteredPoints = [];
    if (points.isNotEmpty) {
      filteredPoints.add(points.first);
      for (int i = 1; i < points.length; i++) {
        final prev = filteredPoints.last;
        final curr = points[i];
        
        final double dist = geo.Geolocator.distanceBetween(
          (prev['lat'] ?? 0.0).toDouble(), (prev['lng'] ?? 0.0).toDouble(),
          (curr['lat'] ?? 0.0).toDouble(), (curr['lng'] ?? 0.0).toDouble()
        );
        
        // Thresholds: accuracy < 40m, movement > 3m (Friendly for walking tests)
        final double accuracy = (curr['accuracy'] ?? 100.0).toDouble();
        if (accuracy < 40.0 && (dist > 3.0 || i == points.length - 1)) {
          filteredPoints.add(curr);
        }
      }
    }

    final String sourceId = "driver-route-source";
    final List<Map<String, dynamic>> segments = [];
    
    // EDGE-BASED SEGMENTATION: Connect points directly to avoid gaps
    for (int i = 1; i < filteredPoints.length; i++) {
      final prev = filteredPoints[i - 1];
      final curr = filteredPoints[i];
      
      final double prevLng = (prev['lng'] ?? 0.0).toDouble();
      final double prevLat = (prev['lat'] ?? 0.0).toDouble();
      final double currLng = (curr['lng'] ?? 0.0).toDouble();
      final double currLat = (curr['lat'] ?? 0.0).toDouble();
      final int prevTs = (prev['timestamp'] ?? 0) as int;
      final int currTs = (curr['timestamp'] ?? 0) as int;
      
      final String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();
      bool isGap = (currTs - prevTs) > 60000;

      if (!isGap) {
        if (segments.isNotEmpty && segments.last['properties']['color'] == color) {
          final List coords = segments.last['geometry']['coordinates'];
          if (coords.isEmpty || coords.last[0] != currLng || coords.last[1] != currLat) {
            coords.add([currLng, currLat]);
          }
        } else {
          // Start NEW segment beginning exactly where the previous one ended
          segments.add({
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": [[prevLng, prevLat], [currLng, currLat]]
            },
            "properties": {"color": color, "isGap": false}
          });
        }
      }
    }

    final featureCollection = {"type": "FeatureCollection", "features": segments};
    
    try {
      final style = mapboxMap!.style;
      if (!_routeSourceCreated) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        
        try { await style.removeStyleLayer("route-layer"); } catch(_) {}
        try { await style.removeStyleLayer("active-route-layer"); } catch(_) {}

        await style.addLayer(LineLayer(
          id: "driver-route-layer", 
          sourceId: sourceId, 
          lineColor: Colors.green.toARGB32(), 
          lineWidth: 10.0, // Thicker line for easier viewing
          lineOpacity: 1.0, 
          lineCap: LineCap.ROUND, 
          lineJoin: LineJoin.ROUND
        ));
        
        await style.setStyleLayerProperty("driver-route-layer", "line-color", [
          "match", ["get", "color"],
          "GREEN", "#00FF00",
          "YELLOW", "#FFFF00",
          "PINK", "#FF1493",
          "BLACK", "#000000",
          "BLUE", "#0000FF",
          "#00FF00"
        ]);

        if (mounted) setState(() => _routeSourceCreated = true);
      } else { 
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection)); 
      }
    } catch (e) {}
  }

  void _clearRoute() async {
    if (mapboxMap == null || !_routeSourceCreated) return;
    try { await mapboxMap!.style.setStyleSourceProperty("driver-route-source", "data", jsonEncode({"type": "FeatureCollection", "features": []})); } catch (e) {}
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated, 
            onStyleLoadedListener: _onStyleLoaded, 
            onCameraChangeListener: (e) {
              // Note: isGesture is not available in this version of the SDK.
              // Follow mode will remain active unless manually toggled via button.
            },
            viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5)
          ),
          Positioned(top: 60, right: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("GPS: ${_lastLocalPos != null ? 'LOCKED' : 'SEARCHING...'}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            if (_lastLocalPos != null) ...[Text("LAT: ${_lastLocalPos!.latitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.green, fontSize: 9)), Text("LNG: ${_lastLocalPos!.longitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.green, fontSize: 9)), Text("ACC: ${_lastLocalPos!.accuracy.toStringAsFixed(1)}m", style: const TextStyle(color: Colors.white70, fontSize: 8))],
            Text("MAP: ${mapboxMap != null ? 'READY' : 'LOADING...'}", style: const TextStyle(color: Colors.white, fontSize: 10)),
            Text("STATUS: $_currentStatus", style: TextStyle(color: _getStatusColor(_currentStatus), fontSize: 10, fontWeight: FontWeight.w900)),
          ]))),
          if (!widget.isEmbedded) Positioned(top: 50, left: 20, child: FloatingActionButton(mini: true, backgroundColor: Colors.white, child: const Icon(Icons.arrow_back, color: Colors.black), onPressed: widget.onBack ?? () => Navigator.pop(context))),
          
          // MAP CONTROLS (Right side)
          Positioned(bottom: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton(
              mini: true, backgroundColor: _isFollowLocked ? Colors.teal : Colors.white,
              heroTag: "follow_lock",
              child: Icon(_isFollowLocked ? Icons.gps_fixed : Icons.gps_not_fixed, color: _isFollowLocked ? Colors.white : Colors.teal),
              onPressed: () {
                setState(() => _isFollowLocked = !_isFollowLocked);
                if (_isFollowLocked && _lastLocalPos != null) {
                  mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(_lastLocalPos!.longitude, _lastLocalPos!.latitude)), zoom: 16.5));
                }
              }
            ),
            const SizedBox(height: 12),
            FloatingActionButton(mini: true, backgroundColor: Colors.white, heroTag: "recenter", child: const Icon(Icons.map_outlined, color: Colors.teal), onPressed: () { mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5)); }),
          ])),

          // MAP LEGEND (Left side)
          Positioned(
            bottom: 20, left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem(Colors.green, "Active / Normal"),
                  _buildLegendItem(Colors.yellow, "Idle / Signal Issue"),
                  _buildLegendItem(Colors.pinkAccent, "Truck Full"),
                  _buildLegendItem(Colors.black, "Finish"),
                  _buildLegendItem(Colors.blue, "Start Point"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "IDLE": return Colors.yellow;
      case "FULL": return Colors.pinkAccent;
      case "FINISHED": return Colors.blue;
      default: return Colors.greenAccent;
    }
  }
}
