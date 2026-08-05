import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
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
  final Map<String, CircleAnnotation> _accuracyCircles = {};
  final Map<String, CircleAnnotation> _blueDots = {};
  
  List<Map> _lastPoints = [];
  bool _hasInitialFocus = false;
  StreamSubscription? _truckSubscription;
  StreamSubscription? _routeSubscription;
  
  Map<dynamic, dynamic>? _lastTruckData;

  @override
  void initState() {
    super.initState();
    _listenToTrucks();
    _listenToRoute();
  }

  void _listenToTrucks() {
    _truckSubscription?.cancel();
    _truckSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        _lastTruckData = data;
        if (_pointAnnotationManager != null) {
          data.forEach((key, value) {
            _updateSingleTruckMarker(key.toString(), value as Map);
          });
        }
      }
    }, onError: (e) => debugPrint("Trucks Listener Error: $e"));
  }

  void _listenToRoute() {
    if (widget.currentSessionId == null) return;
    _routeSubscription?.cancel();
    _routeSubscription = _database.ref('driver_routes/${widget.currentSessionId}/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map> points = [];
        data.forEach((key, value) => points.add(value as Map));
        
        points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        
        if (mounted && points.length != _lastPoints.length) {
          _updateRoutePolyline(points);
          _lastPoints = points;
        }
      }
    }, onError: (e) => debugPrint("Route Listener Error: $e"));
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
  }

  void _onStyleLoaded(dynamic data) {
    mapboxMap?.location.updateSettings(LocationComponentSettings(
      enabled: true, pulsingEnabled: true, showAccuracyRing: true,
    ));

    Future.wait([
      mapboxMap!.annotations.createPointAnnotationManager(),
      mapboxMap!.annotations.createPolylineAnnotationManager(),
      mapboxMap!.annotations.createCircleAnnotationManager(),
    ]).then((managers) {
      if (!mounted) return;
      setState(() {
        _pointAnnotationManager = managers[0] as PointAnnotationManager;
        _polylineAnnotationManager = managers[1] as PolylineAnnotationManager;
        _circleAnnotationManager = managers[2] as CircleAnnotationManager;
      });

      if (_lastTruckData != null) {
        _lastTruckData!.forEach((key, value) {
          _updateSingleTruckMarker(key.toString(), value as Map);
        });
      }
      if (_lastPoints.isNotEmpty) {
        _updateRoutePolyline(_lastPoints);
      }
    }).catchError((e) => debugPrint("Annotation Manager Creation Error: $e"));
  }

  void _updateSingleTruckMarker(String id, Map data) {
    if (_pointAnnotationManager == null || _circleAnnotationManager == null) return;

    final double lat = (data['latitude'] ?? 0.0).toDouble();
    final double lng = (data['longitude'] ?? 0.0).toDouble();
    final double accuracy = (data['accuracy'] ?? 0.0).toDouble();
    final double heading = (data['heading'] ?? 0.0).toDouble();
    
    if (lat == 0.0 || lng == 0.0) return;

    final String truckId = (data['truck_id'] ?? id).toString();
    final String status = (data['status'] ?? "OFFLINE").toString().toUpperCase();
    final String driverName = data['driver_name'] ?? 'Driver';

    final position = Position(lng, lat);
    final point = Point(coordinates: position);

    if (widget.focusTruckId == truckId) {
      if (!_hasInitialFocus) {
        mapboxMap?.setCamera(CameraOptions(center: point, zoom: 16.5));
        _hasInitialFocus = true;
      } else {
        mapboxMap?.easeTo(CameraOptions(center: point), MapAnimationOptions(duration: 1200));
      }
      
      if (_blueDots.containsKey(id)) {
        final dot = _blueDots[id]!;
        dot.geometry = point;
        _circleAnnotationManager?.update(dot);
      } else {
        _circleAnnotationManager?.create(
          CircleAnnotationOptions(
            geometry: point, circleRadius: 8, circleColor: Colors.blue.value,
            circleStrokeWidth: 3, circleStrokeColor: Colors.white.value,
          ),
        ).then((dot) { if (dot != null) _blueDots[id] = dot; });
      }
    }

    if (_accuracyCircles.containsKey(id)) {
      final circle = _accuracyCircles[id]!;
      circle.geometry = point;
      circle.circleRadius = (accuracy > 0 && accuracy < 200) ? (accuracy / 2) : 20;
      _circleAnnotationManager?.update(circle);
    } else {
      _circleAnnotationManager?.create(
        CircleAnnotationOptions(
          geometry: point, circleRadius: (accuracy > 0 && accuracy < 200) ? (accuracy / 2) : 20,
          circleColor: Colors.blue.withOpacity(0.15).toARGB32(),
          circleStrokeWidth: 1.5, circleStrokeColor: Colors.blue.withOpacity(0.5).toARGB32(),
        ),
      ).then((circle) { if (circle != null) _accuracyCircles[id] = circle; });
    }

    int iconColor = status == "IDLE" ? Colors.yellow.toARGB32() : AppColors.statusGreen.toARGB32();
    if (status == "FULL") iconColor = Colors.orange.toARGB32();
    if (status == "FINISHED" || status == "OFFLINE") iconColor = Colors.grey.toARGB32();

    if (_truckMarkers.containsKey(id)) {
      final marker = _truckMarkers[id]!;
      marker.geometry = point;
      marker.textField = "$truckId ($status)\n$driverName";
      marker.textColor = iconColor;
      marker.iconRotate = heading;
      _pointAnnotationManager?.update(marker);
    } else {
      _pointAnnotationManager?.create(
        PointAnnotationOptions(
          geometry: point, textField: "$truckId ($status)\n$driverName",
          textOffset: [0, 2.5], textColor: iconColor, textSize: 11,
          iconImage: "marker-15", iconSize: 1.4, iconRotate: heading,
        ),
      ).then((marker) { if (marker != null) _truckMarkers[id] = marker; });
    }
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
    Color color = Colors.blue;
    if (colorName == "YELLOW") color = Colors.yellow;
    if (colorName == "GRAY") color = Colors.grey;

    _polylineAnnotationManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: segment),
        lineColor: color.toARGB32(),
        lineWidth: 6.5, lineOpacity: 0.9,
      ),
    );
  }

  @override
  void dispose() {
    _truckSubscription?.cancel();
    _routeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded,
            viewport: CameraViewportState(
              center: Point(coordinates: Position(121.1638, 13.9402)),
              zoom: 15.0,
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
            bottom: widget.isEmbedded ? 20 : 100, 
            right: 20,
            child: FloatingActionButton(
              mini: true, backgroundColor: Colors.white,
              child: Icon(_hasInitialFocus ? Icons.my_location : Icons.location_searching, color: Colors.teal),
              onPressed: () => setState(() => _hasInitialFocus = false),
            ),
          ),
        ],
      ),
    );
  }
}
