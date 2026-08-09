import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/app_theme.dart';

class MapboxView extends StatefulWidget {
  final String mode; // 'dashboard' or 'full'
  final String? selectedTruckId;
  final VoidCallback? onTap;

  const MapboxView({super.key, required this.mode, this.selectedTruckId, this.onTap});

  @override
  State<MapboxView> createState() => _MapboxViewState();
}

class _MapboxViewState extends State<MapboxView> {
  MapboxMap? _map;
  PointAnnotationManager? _pointAnnotationManager;
  CircleAnnotationManager? _circleAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final Map<String, StreamSubscription> _routeSubscriptions = {};
  geo.Position? _residentPosition;

  bool _truckLayersCreated = false;
  bool _managersReady = false;

  final Position _balintawakCenter = Position(121.1623, 13.9413);

  @override
  void initState() {
    super.initState();
    _getResidentLocation();
  }

  @override
  void dispose() {
    _routeSubscriptions.forEach((key, sub) => sub.cancel());
    super.dispose();
  }

  Future<void> _getResidentLocation() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.always || permission == geo.LocationPermission.whileInUse) {
      geo.Position pos = await geo.Geolocator.getCurrentPosition();
      if (mounted) setState(() => _residentPosition = pos);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MapWidget(
        key: const ValueKey("mapbox_map"),
        onMapCreated: (map) => _map = map,
        onStyleLoadedListener: (data) async {
           if (_map == null) return;
           _map!.location.updateSettings(LocationComponentSettings(
             enabled: true,
             pulsingEnabled: true,
           ));
           
           _polylineAnnotationManager = await _map!.annotations.createPolylineAnnotationManager();
           
           if (mounted) setState(() => _managersReady = true);
           _setupFirebaseSync();
        },
        viewport: CameraViewportState(
          center: Point(coordinates: Position(121.1623, 13.9413)), // STRICTLY Balintawak Center
          zoom: widget.mode == 'dashboard' ? 14.5 : 15.5,
        ),
      ),
    );
  }

  void _setupFirebaseSync() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        final Map<String, Map<dynamic, dynamic>> uniqueTrucks = {};

        data.forEach((key, value) {
          final val = value as Map;
          final String status = (val['status'] ?? '').toString().toUpperCase();
          final bool isOnline = val['isOnline'] == true;
          final String truckId = (val['truck_id'] ?? key.toString()).toUpperCase().trim();

          bool isFresh = true;
          if (val['lastSeen'] != null) {
            final int lastSeen = (val['lastSeen'] as int);
            final int now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastSeen > 300000) isFresh = false;
          }

          if (isOnline && isFresh && (status == 'ACTIVE' || status == 'COLLECTING' || status == 'IDLE' || status == 'FULL')) {
            if (!uniqueTrucks.containsKey(truckId)) {
              uniqueTrucks[truckId] = val;
            } else {
              final existing = uniqueTrucks[truckId]!;
              final existingTime = DateTime.tryParse(existing['updatedAt'] ?? '') ?? DateTime(2000);
              final newTime = DateTime.tryParse(val['updatedAt'] ?? '') ?? DateTime(2000);
              if (newTime.isAfter(existingTime)) uniqueTrucks[truckId] = val;
            }
          }
        });

        _updateTruckMarkers(uniqueTrucks);
        debugPrint("[DASHBOARD MAP] Received ${uniqueTrucks.length} active trucks from Firebase.");
      }
    });
  }

  void _updateTruckMarkers(Map<String, Map<dynamic, dynamic>> trucksData) async {
    if (!_managersReady || _map == null) return;

    final String sourceId = "trucks-live-location-source";
    final String circleLayerId = "trucks-live-location-circle";
    final String labelLayerId = "trucks-live-location-label";

    final featureCollection = {
      "type": "FeatureCollection",
      "features": trucksData.entries.map((entry) {
        final truckId = entry.key;
        final data = entry.value;
        final double lat = (data['latitude'] ?? 0.0).toDouble();
        final double lng = (data['longitude'] ?? 0.0).toDouble();
        
        // 1. COLLISION DETECTION: Check distance to Resident
        List<double> translate = [0.0, 0.0];
        if (_residentPosition != null) {
          double dist = geo.Geolocator.distanceBetween(lat, lng, _residentPosition!.latitude, _residentPosition!.longitude);
          // If within 15 meters, apply a visual offset (translate)
          if (dist < 15.0) {
            translate = [0.0, -25.0]; // Move Driver marker 25 pixels UP in screen space
          }
        }

        return {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat]
          },
          "properties": {
            "truckId": truckId,
            "label": "DRIVER\n$truckId",
            "translate": translate
          }
        };
      }).toList()
    };

    try {
      if (!_truckLayersCreated) {
        await _map?.style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        
        await _map?.style.addLayer(CircleLayer(
          id: circleLayerId,
          sourceId: sourceId,
          circleRadius: 8.0,
          circleColor: Colors.green.toARGB32(),
          circleStrokeWidth: 3.0,
          circleStrokeColor: Colors.white.toARGB32(),
          circleSortKey: 2000.0,
          circleTranslate: ["get", "translate"], // DYNAMIC OFFSET
        ));

        await _map?.style.addLayer(SymbolLayer(
          id: labelLayerId,
          sourceId: sourceId,
          textField: "{label}",
          textSize: 11.0,
          textColor: Colors.green.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2.0,
          textAnchor: TextAnchor.BOTTOM,
          textOffset: [0, -1.2],
          symbolSortKey: 2000.0,
          textAllowOverlap: true,
          iconAllowOverlap: true,
          textTranslate: ["get", "translate"], // DYNAMIC OFFSET
        ));

        if (mounted) setState(() => _truckLayersCreated = true);
      } else {
        try {
          await _map?.style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection));
        } catch (e) {
          await _map?.style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        }
      }
      
      // Setup route subs for any new trucks
      for (var entry in trucksData.entries) {
        final tid = entry.key;
        final sid = entry.value['current_session']?.toString();
        if (sid != null && !_routeSubscriptions.containsKey(tid)) {
          _setupRouteSubscription(tid, sid);
        }
      }

    } catch (e) {
      debugPrint("[DASHBOARD MAP] Error: $e");
    }
    
    _adjustCamera(trucksData.values.toList());
  }

  void _adjustCamera(List<Map<dynamic, dynamic>> trucks) {
    if (_map == null || trucks.isEmpty) return;
    if (trucks.length == 1) {
      final double lat = (trucks.first['latitude'] ?? 0.0).toDouble();
      final double lng = (trucks.first['longitude'] ?? 0.0).toDouble();
      if (lat != 0 && lng != 0) {
        _map?.setCamera(CameraOptions(
          center: Point(coordinates: Position(lng, lat)),
          zoom: widget.mode == 'dashboard' ? 14.0 : 15.0,
        ));
      }
    }
  }

  void _setupRouteSubscription(String truckId, String sessionId) {
    _routeSubscriptions[truckId]?.cancel();
    _routeSubscriptions[truckId] = _database.ref('driver_routes/$sessionId/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map> points = [];
        data.forEach((key, value) => points.add(value as Map));
        points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        
        _updateRoutePolyline(points);
      }
    });
  }

  void _updateRoutePolyline(List<Map> points) {
    if (_polylineAnnotationManager == null || points.length < 2) return;
    
    _polylineAnnotationManager?.deleteAll();
    
    List<Position> currentSegment = [];
    String currentColor = (points.first['color'] ?? 'BLUE').toString().toUpperCase();
    
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final color = (p['color'] ?? 'BLUE').toString().toUpperCase();
      final lat = (p['lat'] ?? 0.0).toDouble();
      final lng = (p['lng'] ?? 0.0).toDouble();
      final pos = Position(lng, lat);
      
      if (color != currentColor) {
        if (currentSegment.length >= 2) _drawSegment(currentSegment, currentColor);
        currentSegment = [currentSegment.isNotEmpty ? currentSegment.last : pos, pos];
        currentColor = color;
      } else {
        currentSegment.add(pos);
      }
    }
    if (currentSegment.length >= 2) _drawSegment(currentSegment, currentColor);
  }

  void _drawSegment(List<Position> segment, String colorName) {
    Color color = colorName == "YELLOW" ? Colors.yellow : Colors.blue;
    _polylineAnnotationManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: segment),
        lineColor: color.toARGB32(),
        lineWidth: 4.0,
        lineOpacity: 0.8,
      ),
    );
  }
}
