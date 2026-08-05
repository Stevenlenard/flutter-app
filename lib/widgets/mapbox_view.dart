import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:firebase_database/firebase_database.dart';
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
  final Map<String, PointAnnotation> _truckAnnotations = {};
  final Map<String, CircleAnnotation> _accuracyCircles = {};
  final Map<String, StreamSubscription> _routeSubscriptions = {};

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MapWidget(
        key: const ValueKey("mapbox_map"),
        onMapCreated: (map) => _map = map,
        onStyleLoadedListener: (data) async {
           if (_map == null) return;
           _pointAnnotationManager = await _map!.annotations.createPointAnnotationManager();
           _circleAnnotationManager = await _map!.annotations.createCircleAnnotationManager();
           _polylineAnnotationManager = await _map!.annotations.createPolylineAnnotationManager();
           _setupFirebaseSync();
        },
        viewport: CameraViewportState(
          center: Point(coordinates: Position(121.1638, 13.9402)),
          zoom: widget.mode == 'dashboard' ? 12.0 : 14.0,
        ),
      ),
    );
  }

  void _setupFirebaseSync() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map<dynamic, dynamic> trucks = event.snapshot.value as Map<dynamic, dynamic>;
        _updateTruckMarkers(trucks);
      }
    });
  }

  void _updateTruckMarkers(Map<dynamic, dynamic> trucksData) async {
    if (_pointAnnotationManager == null || _circleAnnotationManager == null) return;

    for (var entry in trucksData.entries) {
      final id = entry.key.toString();
      final data = entry.value as Map<dynamic, dynamic>;
      
      final lat = (data['latitude'] ?? 0.0).toDouble();
      final lng = (data['longitude'] ?? 0.0).toDouble();
      final accuracy = (data['accuracy'] ?? 0.0).toDouble();
      final status = (data['status'] ?? 'active').toString().toUpperCase();
      final driverName = data['driver_name'] ?? 'Unknown';
      final currentSession = data['current_session']?.toString();

      if (lat == 0.0 || lng == 0.0) continue;

      final point = Point(coordinates: Position(lng, lat));

      // 1. Update Marker
      int color = status == "IDLE" ? Colors.yellow.toARGB32() : AppColors.statusGreen.toARGB32();

      if (_truckAnnotations.containsKey(id)) {
        final annotation = _truckAnnotations[id]!;
        annotation.geometry = point;
        annotation.textField = "$id\n$driverName\n($status)";
        annotation.textColor = color;
        _pointAnnotationManager!.update(annotation);
      } else {
        final annotation = await _pointAnnotationManager!.create(
          PointAnnotationOptions(
            geometry: point,
            textField: "$id\n$driverName\n($status)",
            textSize: 10,
            textColor: color,
            iconImage: "marker-15",
          ),
        );
        _truckAnnotations[id] = annotation;
      }

      // 2. Update Accuracy Circle
      if (_accuracyCircles.containsKey(id)) {
        final circle = _accuracyCircles[id]!;
        circle.geometry = point;
        circle.circleRadius = accuracy > 0 ? (accuracy / 4) : 10;
        _circleAnnotationManager!.update(circle);
      } else {
        final circle = await _circleAnnotationManager!.create(
          CircleAnnotationOptions(
            geometry: point,
            circleRadius: accuracy > 0 ? (accuracy / 4) : 10,
            circleColor: Colors.blue.withOpacity(0.1).toARGB32(),
            circleStrokeWidth: 1.0,
            circleStrokeColor: Colors.blue.withOpacity(0.3).toARGB32(),
          ),
        );
        _accuracyCircles[id] = circle;
      }

      // 3. Live Route Listening for Admin
      if (currentSession != null && !_routeSubscriptions.containsKey(id)) {
        _setupRouteSubscription(id, currentSession);
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
    
    // For simplicity in Admin view, we redraw the active routes. 
    // Optimization: In a production app, we would cache segments per truckId.
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

  @override
  void dispose() {
    _routeSubscriptions.forEach((key, sub) => sub.cancel());
    super.dispose();
  }
}
