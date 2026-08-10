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
  
  const DriverTrackTruckScreen({
    super.key, 
    this.isEmbedded = false, 
    this.onBack,
    this.currentSessionId,
    this.focusTruckId,
  });

  @override
  State<DriverTrackTruckScreen> createState() => _DriverTrackTruckScreenState();
}

class _DriverTrackTruckScreenState extends State<DriverTrackTruckScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  CircleAnnotationManager? _circleAnnotationManager;
  
  final Map<String, PointAnnotation> _truckMarkers = {};
  
  List<Map> _lastPoints = [];
  bool _hasInitialGpsFocus = false;
  StreamSubscription? _truckSubscription;
  StreamSubscription? _routeSubscription;
  StreamSubscription? _localGpsSubscription;
  
  Map<dynamic, dynamic>? _lastTruckData;
  geo.Position? _lastLocalPos;

  // Barangay Balintawak Center
  final Position _balintawakCenter = Position(121.1623, 13.9413);

  bool _managersReady = false;
  bool _driverSourceCreated = false;

  @override
  void initState() {
    super.initState();
    debugPrint("### ACTIVE DRIVER MAP IMPLEMENTATION LOADED ###");
    _checkPermissionAndStartGps();
    _listenToTrucks();
    _listenToRoute();
  }

  @override
  void dispose() {
    _truckSubscription?.cancel();
    _routeSubscription?.cancel();
    _localGpsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndStartGps() async {
    debugPrint("[DRIVER GPS] Checking permissions...");
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    
    if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
      debugPrint("[DRIVER GPS] Permissions not granted.");
      return;
    }

    try {
      geo.Position pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      _lastLocalPos = pos;
      if (mounted) {
        _updateLocalDriverMarker(pos);
      }
    } catch (e) {
      debugPrint("[DRIVER GPS] Error getting current position: $e");
    }

    _localGpsSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      debugPrint("[DRIVER GPS] Stream Update: ${pos.latitude}, ${pos.longitude}");
      if (mounted) {
        setState(() {
          _lastLocalPos = pos;
        });
      }
      _updateLocalDriverMarker(pos);
    }, onError: (e) => debugPrint("[DRIVER GPS] Stream Error: $e"));
  }

  void _listenToTrucks() {
    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        _lastTruckData = event.snapshot.value as Map;
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
        
        // 1. UPDATE ROUTE TRAIL
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

        // 2. UPDATE SPECIAL MARKERS (START / FINISH)
        if (_managersReady) {
          _updateSpecialMarkers(data);
        }
      }
    });
  }

  void _updateSpecialMarkers(Map data) async {
    if (_pointAnnotationManager == null) return;

    // We can use unique tags or IDs to manage these special markers
    // For simplicity, let's just clear and redraw them if session changed or on update
    // But better to keep them if they are already there.
    
    // START MARKER
    if (data['start_lat'] != null && data['start_lng'] != null) {
      final pos = Position(data['start_lng'], data['start_lat']);
      _addMarkerIfMissing("SESSION_START", pos, "START", Colors.green);
    }

    // FINISH MARKER
    if (data['finish_lat'] != null && data['finish_lng'] != null) {
      final pos = Position(data['finish_lng'], data['finish_lat']);
      _addMarkerIfMissing("SESSION_FINISH", pos, "🏁 FINISH", Colors.blue);
    }
  }

  final Map<String, PointAnnotation> _specialMarkers = {};

  Future<void> _addMarkerIfMissing(String id, Position pos, String label, Color color) async {
    if (_specialMarkers.containsKey(id)) {
      // Just update position if needed, but Start/Finish usually stationary
      return;
    }

    final marker = await _pointAnnotationManager?.create(PointAnnotationOptions(
      geometry: Point(coordinates: pos),
      textField: label,
      textOffset: [0, -1.5],
      textColor: color.toARGB32(),
      textSize: 12.0,
      textHaloColor: Colors.white.toARGB32(),
      textHaloWidth: 2.0,
      iconSize: 0,
    ));

    if (marker != null) {
      _specialMarkers[id] = marker;
      
      // Optionally add a circle annotation at the same spot for a real "marker" look
      _circleAnnotationManager?.create(CircleAnnotationOptions(
        geometry: Point(coordinates: pos),
        circleRadius: 6.0,
        circleColor: color.toARGB32(),
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.toARGB32(),
      ));
    }
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
    debugPrint("[MAPBOX] mapCreated = true");
  }

  void _onStyleLoaded(dynamic data) async {
    debugPrint("[MAPBOX] Style loaded.");
    
    // 1. DISABLE BLUE PUCK
    try {
      await mapboxMap?.location.updateSettings(LocationComponentSettings(
        enabled: false,
        pulsingEnabled: false,
      ));
    } catch (e) {}

    // 2. SET DEFAULT VIEW (Balintawak)
    await mapboxMap?.setCamera(CameraOptions(
      center: Point(coordinates: _balintawakCenter),
      zoom: 14.5,
    ));

    // 3. INITIALIZE MANAGERS
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      _pointAnnotationManager = await mapboxMap!.annotations.createPointAnnotationManager();
      _polylineAnnotationManager = await mapboxMap!.annotations.createPolylineAnnotationManager();
      _circleAnnotationManager = await mapboxMap!.annotations.createCircleAnnotationManager();
    } catch (e) {
      debugPrint("[MAPBOX] Error creating managers: $e");
    }

    if (!mounted) return;
    
    _truckMarkers.clear();
    setState(() => _managersReady = true);

    // 4. IMMEDIATE REDRAW WITH REAL GPS
    if (_lastLocalPos != null) {
      _updateLocalDriverMarker(_lastLocalPos!);
    } else {
      geo.Geolocator.getCurrentPosition(desiredAccuracy: geo.LocationAccuracy.high).then((pos) {
        if (mounted) {
          setState(() => _lastLocalPos = pos);
          _updateLocalDriverMarker(pos);
        }
      }).catchError((e) => debugPrint("[DRIVER MAP] diagnostic pos failed: $e"));
    }

    // 5. REDRAW OTHER TRUCKS
    if (_lastTruckData != null) {
      _lastTruckData!.forEach((key, value) {
        _updateSingleTruckMarker(key.toString(), value as Map);
      });
    }
    if (_lastPoints.isNotEmpty) {
      _updateRoutePolyline(_lastPoints);
    }
  }

  Future<void> _updateLocalDriverMarker(geo.Position pos) async {
    debugPrint("[DRIVER GPS] Attempting to update REAL marker at ${pos.latitude}, ${pos.longitude}");

    if (mapboxMap == null) {
      debugPrint("[DRIVER GPS] Map not ready yet.");
      return;
    }

    if (pos.latitude == 0 || pos.longitude == 0) return;

    final String sourceId = "driver-live-location-source";
    final String circleLayerId = "driver-live-location-circle";
    final String labelLayerId = "driver-live-location-label";
    final String tid = (widget.focusTruckId ?? "GT-001").toUpperCase();

    final feature = {
      "type": "Feature",
      "geometry": {
        "type": "Point",
        "coordinates": [pos.longitude, pos.latitude]
      },
      "properties": {
        "name": "DRIVER",
        "truckId": tid
      }
    };

    try {
      if (!_driverSourceCreated) {
        // 1. CREATE SOURCE
        await mapboxMap?.style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(feature)));

        // 2. CREATE CIRCLE LAYER
        await mapboxMap?.style.addLayer(CircleLayer(
          id: circleLayerId,
          sourceId: sourceId,
          circleRadius: 8.0, // Reduced from 18.0 to match Resident size
          circleColor: Colors.green.toARGB32(),
          circleOpacity: 1.0,
          circleStrokeWidth: 3.0, // Reduced from 5.0
          circleStrokeColor: Colors.white.toARGB32(),
          circleSortKey: 3000.0,
        ));

        // 3. CREATE LABEL LAYER
        await mapboxMap?.style.addLayer(SymbolLayer(
          id: labelLayerId,
          sourceId: sourceId,
          textField: "DRIVER\n$tid", // Removed \n🟢 to let CircleLayer handle the marker
          textSize: 14.0, // Slightly reduced for better proportions
          textColor: Colors.green.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2.0,
          textAnchor: TextAnchor.BOTTOM,
          textOffset: [0, -1.0], // Adjusted offset for smaller circle
          symbolSortKey: 3000.0,
          textAllowOverlap: true,
          iconAllowOverlap: true,
        ));

        if (mounted) setState(() => _driverSourceCreated = true);
        debugPrint("[DRIVER GPS] Source and Layers CREATED for $tid at ${pos.latitude}, ${pos.longitude}");
      } else {
        // UPDATE SOURCE DATA
        try {
          await mapboxMap?.style.setStyleSourceProperty(sourceId, "data", jsonEncode(feature));
          debugPrint("[DRIVER GPS] Source property UPDATED for $tid to ${pos.latitude}, ${pos.longitude}");
        } catch (e) {
          await mapboxMap?.style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(feature)));
          debugPrint("[DRIVER GPS] Source re-added as fallback for $tid");
        }
      }

      // 4. AUTO-CAMERA (ONCE)
      if (!_hasInitialGpsFocus) {
        await mapboxMap?.setCamera(CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: 16.5,
        ));
        _hasInitialGpsFocus = true;
        debugPrint("[MAPBOX] Camera centered on driver at ${pos.latitude}, ${pos.longitude}");
      }

    } catch (e) {
      debugPrint("[DRIVER GPS] GeoJSON Render Error: $e");
    }
  }

  void _updateSingleTruckMarker(String id, Map data) {
    if (!_managersReady || _pointAnnotationManager == null) return;
    
    final String truckId = (data['truck_id'] ?? id).toString();
    if (widget.focusTruckId == truckId) return; 

    final double lat = (data['latitude'] ?? 0.0).toDouble();
    final double lng = (data['longitude'] ?? 0.0).toDouble();
    if (lat == 0.0 || lng == 0.0) return;

    final position = Position(lng, lat);
    final point = Point(coordinates: position);
    final String status = (data['status'] ?? "OFFLINE").toString().toUpperCase();
    final int color = status == "IDLE" ? Colors.orange.toARGB32() : Colors.green.toARGB32();

    if (_truckMarkers.containsKey(id)) {
      final marker = _truckMarkers[id]!;
      marker.geometry = point;
      marker.textField = "$truckId ($status)";
      marker.textColor = color;
      _pointAnnotationManager?.update(marker);
    } else {
      _pointAnnotationManager?.create(PointAnnotationOptions(
        geometry: point, textField: "$truckId ($status)",
        textOffset: [0, 3.0], textColor: color, textSize: 11, iconSize: 0,
      )).then((m) { if (m != null) _truckMarkers[id] = m; });
    }
  }

  void _updateRoutePolyline(List<Map> points) {
    if (!_managersReady || _polylineAnnotationManager == null || points.length < 2) return;
    _polylineAnnotationManager?.deleteAll();
    List<Position> currentSegment = [];
    String currentColor = (points.first['color'] ?? 'GREEN').toString().toUpperCase();
    int lastTimestamp = (points.first['timestamp'] ?? 0) as int;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final color = (p['color'] ?? 'GREEN').toString().toUpperCase();
      final pos = Position((p['lng'] ?? 0.0).toDouble(), (p['lat'] ?? 0.0).toDouble());
      final timestamp = (p['timestamp'] ?? 0) as int;

      // DETECT GPS GAP (e.g., > 45 seconds)
      bool isGap = i > 0 && (timestamp - lastTimestamp) > 45000;

      if (isGap) {
        // End current segment
        if (currentSegment.length >= 2) _drawSegment(currentSegment, currentColor);
        
        // Draw DASHED GAP between last point and current point
        if (currentSegment.isNotEmpty) {
          _drawSegment([currentSegment.last, pos], "YELLOW", isDashed: true);
        }
        
        currentSegment = [pos];
        currentColor = color;
      } else if (color != currentColor) {
        if (currentSegment.length >= 2) _drawSegment(currentSegment, currentColor);
        currentSegment = [currentSegment.isNotEmpty ? currentSegment.last : pos, pos];
        currentColor = color;
      } else {
        currentSegment.add(pos);
      }
      
      lastTimestamp = timestamp;
    }
    if (currentSegment.length >= 2) _drawSegment(currentSegment, currentColor);
  }

  void _drawSegment(List<Position> segment, String colorName, {bool isDashed = false}) {
    Color color = Colors.green;
    if (colorName == "YELLOW") color = Colors.yellow;
    if (colorName == "MAGENTA") color = Colors.pinkAccent;
    if (colorName == "GRAY") color = Colors.grey;
    if (colorName == "BLUE") color = Colors.blue;

    _polylineAnnotationManager?.create(PolylineAnnotationOptions(
      geometry: LineString(coordinates: segment),
      lineColor: color.toARGB32(), 
      lineWidth: isDashed ? 3.0 : 8.0, 
      lineOpacity: isDashed ? 0.5 : 0.8,
      lineJoin: LineJoin.ROUND,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated, 
            onStyleLoadedListener: _onStyleLoaded,
            viewport: CameraViewportState(
              center: Point(coordinates: Position(121.1623, 13.9413)), 
              zoom: 14.5
            ),
          ),
          // GPS STATUS OVERLAY (DEBUG)
          Positioned(
            top: 60, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("GPS: ${_lastLocalPos != null ? 'LOCKED' : 'SEARCHING...'}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  if (_lastLocalPos != null) ...[
                    Text("LAT: ${_lastLocalPos!.latitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.green, fontSize: 9)),
                    Text("LNG: ${_lastLocalPos!.longitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.green, fontSize: 9)),
                    Text("ACC: ${_lastLocalPos!.accuracy.toStringAsFixed(1)}m", style: const TextStyle(color: Colors.white70, fontSize: 8)),
                  ],
                  Text("MAP: ${mapboxMap != null ? 'READY' : 'LOADING...'}", style: const TextStyle(color: Colors.white, fontSize: 10)),
                  Text("DRIVER: ${_driverSourceCreated ? 'VISIBLE' : 'HIDDEN'}", style: TextStyle(color: _driverSourceCreated ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _checkPermissionAndStartGps,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.5), borderRadius: BorderRadius.circular(4)),
                      child: const Text("RE-LOCK GPS", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // MAP LEGEND
          Positioned(
            bottom: 20, left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem(Colors.green, "Active / Normal"),
                  _buildLegendItem(Colors.yellow, "Idle / Signal Issue"),
                  _buildLegendItem(Colors.pinkAccent, "Truck Full"),
                  _buildLegendItem(Colors.blue, "Start / Finish"),
                ],
              ),
            ),
          ),
          if (!widget.isEmbedded)
            Positioned(
              top: 50, left: 20,
              child: FloatingActionButton(
                mini: true, backgroundColor: Colors.white,
                child: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: widget.onBack ?? () => Navigator.pop(context),
              ),
            ),
          Positioned(
            bottom: 20, right: 20, 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  mini: true, backgroundColor: Colors.white,
                  heroTag: "my_loc",
                  child: const Icon(Icons.my_location, color: Colors.green),
                  onPressed: () {
                    if (_lastLocalPos != null) {
                      final p = Point(coordinates: Position(_lastLocalPos!.longitude, _lastLocalPos!.latitude));
                      mapboxMap?.setCamera(CameraOptions(
                        center: p,
                        zoom: 17.5,
                      ));
                    }
                  }
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  mini: true, backgroundColor: Colors.white,
                  heroTag: "recenter",
                  child: const Icon(Icons.map_outlined, color: Colors.teal),
                  onPressed: () {
                    mapboxMap?.setCamera(CameraOptions(
                      center: Point(coordinates: Position(121.1623, 13.9413)),
                      zoom: 14.5,
                    ));
                  }
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
}
