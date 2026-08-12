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
    
    if (widget.manualPosition != null && widget.manualPosition != oldWidget.manualPosition) {
      setState(() {
        _lastLocalPos = widget.manualPosition;
      });
      _updateLocalDriverMarker(widget.manualPosition!);
      
      if (mapboxMap != null) {
        mapboxMap?.setCamera(CameraOptions(
          center: Point(coordinates: Position(widget.manualPosition!.longitude, widget.manualPosition!.latitude)),
          zoom: 16.5,
        ));
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
      locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.bestForNavigation, distanceFilter: 0),
    ).listen((pos) {
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
      _addMarkerIfMissing("SESSION_START", Position(data['start_lng'], data['start_lat']), "START", Colors.green);
    }
    if (data['finish_lat'] != null && data['finish_lng'] != null) {
      _addMarkerIfMissing("SESSION_FINISH", Position(data['finish_lng'], data['finish_lat']), "🏁 FINISH", Colors.blue);
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
    if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
    if (_lastTruckData != null) _lastTruckData!.forEach((k, v) => _updateSingleTruckMarker(k.toString(), v as Map));
    if (_lastPoints.isNotEmpty) _updateRoutePolyline(_lastPoints);
  }

  Future<void> _updateLocalDriverMarker(geo.Position pos) async {
    if (mapboxMap == null || pos.latitude == 0 || pos.longitude == 0) return;
    final String sourceId = "driver-live-location-source";
    final tid = (widget.focusTruckId ?? "GT-001").toUpperCase();
    final feature = {"type": "Feature", "geometry": {"type": "Point", "coordinates": [pos.longitude, pos.latitude]}, "properties": {"name": "DRIVER", "truckId": tid}};
    try {
      final style = mapboxMap!.style;
      if (!_driverSourceCreated) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(feature)));
        await style.addLayer(CircleLayer(id: "driver-live-location-circle", sourceId: sourceId, circleRadius: 8.0, circleColor: Colors.green.toARGB32(), circleOpacity: 1.0, circleStrokeWidth: 3.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 3000.0));
        await style.addLayer(SymbolLayer(id: "driver-live-location-label", sourceId: sourceId, textField: "DRIVER\n$tid", textSize: 14.0, textColor: Colors.green.toARGB32(), textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.0, textAnchor: TextAnchor.BOTTOM, textOffset: [0, -1.0], symbolSortKey: 3000.0, textAllowOverlap: true, iconAllowOverlap: true));
        if (mounted) setState(() => _driverSourceCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(feature));
      }
      if (!_hasInitialGpsFocus) {
        await mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(pos.longitude, pos.latitude)), zoom: 16.5));
        _hasInitialGpsFocus = true;
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
    final String sourceId = "driver-route-source";
    final List<Map<String, dynamic>> segments = [];
    List<List<double>> currentSegmentCoords = [];
    String currentColor = (points.first['color'] ?? 'GREEN').toString().toUpperCase();
    int lastTimestamp = (points.first['timestamp'] ?? 0) as int;
    for (var i = 0; i < points.length; i++) {
      final p = points[i]; final color = (p['color'] ?? 'GREEN').toString().toUpperCase();
      final lng = (p['lng'] ?? 0.0).toDouble(); final lat = (p['lat'] ?? 0.0).toDouble();
      final timestamp = (p['timestamp'] ?? 0) as int;
      bool isGap = i > 0 && (timestamp - lastTimestamp) > 45000;
      if (isGap || color != currentColor) {
        if (currentSegmentCoords.length >= 2) segments.add({"type": "Feature", "geometry": {"type": "LineString", "coordinates": List.from(currentSegmentCoords)}, "properties": {"color": currentColor, "isGap": false}});
        if (isGap && currentSegmentCoords.isNotEmpty) segments.add({"type": "Feature", "geometry": {"type": "LineString", "coordinates": [currentSegmentCoords.last, [lng, lat]]}, "properties": {"color": "YELLOW", "isGap": true}});
        currentSegmentCoords = [[lng, lat]]; currentColor = color;
      } else { currentSegmentCoords.add([lng, lat]); }
      lastTimestamp = timestamp;
    }
    if (currentSegmentCoords.length >= 2) segments.add({"type": "Feature", "geometry": {"type": "LineString", "coordinates": currentSegmentCoords}, "properties": {"color": currentColor, "isGap": false}});
    final featureCollection = {"type": "FeatureCollection", "features": segments};
    try {
      final style = mapboxMap!.style;
      if (!_routeSourceCreated) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        await style.addLayer(LineLayer(id: "driver-route-layer", sourceId: sourceId, lineColor: Colors.green.toARGB32(), lineWidth: 8.0, lineOpacity: 0.8, lineCap: LineCap.ROUND, lineJoin: LineJoin.ROUND));
        await style.setStyleLayerProperty("driver-route-layer", "line-color", ["match", ["get", "color"], "YELLOW", Colors.yellow.toARGB32(), "MAGENTA", Colors.pinkAccent.toARGB32(), "GRAY", Colors.grey.toARGB32(), "BLUE", Colors.blue.toARGB32(), Colors.green.toARGB32()]);
        await style.addLayer(LineLayer(id: "driver-route-gap-layer", sourceId: sourceId, filter: ["==", ["get", "isGap"], true], lineColor: Colors.yellow.toARGB32(), lineWidth: 3.0, lineOpacity: 0.5, lineDasharray: [2.0, 2.0]));
        if (mounted) setState(() => _routeSourceCreated = true);
      } else { await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection)); }
    } catch (e) {}
  }

  void _clearRoute() async {
    if (mapboxMap == null || !_routeSourceCreated) return;
    try { await mapboxMap!.style.setStyleSourceProperty("driver-route-source", "data", jsonEncode({"type": "FeatureCollection", "features": []})); } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5)),
          Positioned(top: 60, right: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("GPS: ${_lastLocalPos != null ? 'LOCKED' : 'SEARCHING...'}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            if (_lastLocalPos != null) ...[Text("LAT: ${_lastLocalPos!.latitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.green, fontSize: 9)), Text("LNG: ${_lastLocalPos!.longitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.green, fontSize: 9)), Text("ACC: ${_lastLocalPos!.accuracy.toStringAsFixed(1)}m", style: const TextStyle(color: Colors.white70, fontSize: 8))],
            Text("MAP: ${mapboxMap != null ? 'READY' : 'LOADING...'}", style: const TextStyle(color: Colors.white, fontSize: 10)),
          ]))),
          if (!widget.isEmbedded) Positioned(top: 50, left: 20, child: FloatingActionButton(mini: true, backgroundColor: Colors.white, child: const Icon(Icons.arrow_back, color: Colors.black), onPressed: widget.onBack ?? () => Navigator.pop(context))),
          Positioned(bottom: 20, right: 20, child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton(mini: true, backgroundColor: Colors.white, heroTag: "my_loc", child: const Icon(Icons.my_location, color: Colors.green), onPressed: () { if (_lastLocalPos != null) mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(_lastLocalPos!.longitude, _lastLocalPos!.latitude)), zoom: 17.5)); }),
            const SizedBox(height: 12),
            FloatingActionButton(mini: true, backgroundColor: Colors.white, heroTag: "recenter", child: const Icon(Icons.map_outlined, color: Colors.teal), onPressed: () { mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5)); }),
          ])),
        ],
      ),
    );
  }
}
