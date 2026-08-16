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
  final List<Map>? testRoute; // NEW: For web testing
  
  const DriverTrackTruckScreen({
    super.key, 
    this.isEmbedded = false, 
    this.onBack,
    this.currentSessionId,
    this.focusTruckId,
    this.manualPosition,
    this.isSimulation = false,
    this.testRoute,
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
  StreamSubscription? _truckSubscription;
  StreamSubscription? _routeSubscription;
  StreamSubscription? _localGpsSubscription;
  
  Map<dynamic, dynamic>? _lastTruckData;
  geo.Position? _lastLocalPos;

  final Position _balintawakCenter = Position(121.1623, 13.9413);

  bool _managersReady = false;
  bool _driverSourceCreated = false;
  bool _routeSourceCreated = false;
  bool _specialMarkersCreated = false;
  
  // LIVE DRIVER MARKERS (Annotations)
  CircleAnnotation? _liveDriverCircle;
  CircleAnnotation? _liveDriverHalo;
  PointAnnotation? _liveDriverLabel;

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
        if (mounted) setState(() { _lastLocalPos = widget.manualPosition; });
        _updateLocalDriverMarker(widget.manualPosition!);
        
        if (_isFollowLocked && mapboxMap != null) {
          mapboxMap?.setCamera(CameraOptions(
            center: Point(coordinates: Position(widget.manualPosition!.longitude, widget.manualPosition!.latitude)),
          ));
        }
      }
    }

    if (widget.testRoute != oldWidget.testRoute) {
      if (widget.testRoute != null) {
        debugPrint("[DRIVER MAP] TEST ROUTE ACTIVE: ${widget.testRoute!.length} points");
        _updateRoutePolyline(widget.testRoute!);
        
        // Generate fake special markers for test route
        final first = widget.testRoute!.first;
        final last = widget.testRoute!.last;
        _updateSpecialMarkers({
          'start_lat': first['lat'], 'start_lng': first['lng'],
          'finish_lat': last['status'] == 'FINISHED' ? last['lat'] : null,
          'finish_lng': last['status'] == 'FINISHED' ? last['lng'] : null,
        });

        // Also move live marker to end of test route
        final latestPos = geo.Position(
          latitude: (last['lat'] ?? 0.0).toDouble(), 
          longitude: (last['lng'] ?? 0.0).toDouble(),
          timestamp: DateTime.now(), accuracy: 5.0,
          altitude: 0, heading: 0, speed: 0,
          speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
        );
        _lastLocalPos = latestPos;
        _updateLocalDriverMarker(latestPos);
      } else if (widget.currentSessionId == null) {
        _clearRoute();
      } else {
        _listenToRoute();
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
      if (mounted) setState(() { _lastLocalPos = pos; });
      _updateLocalDriverMarker(pos);
    } catch (e) {}

    _localGpsSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.bestForNavigation, distanceFilter: 1),
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
        
        final String tid = (widget.focusTruckId ?? "GT-001").toUpperCase();
        if (_lastTruckData!.containsKey(tid)) {
          final myData = _lastTruckData![tid] as Map;
          final String newStatus = (myData['status'] ?? "ACTIVE").toString().toUpperCase();
          if (newStatus != _currentStatus) {
            if (mounted) setState(() => _currentStatus = newStatus);
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
      if (widget.testRoute != null) return; // Skip if test route is active
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        _lastSessionData = data;

        if (data['route'] != null) {
          final Map routeData = data['route'] as Map;
          final List<Map> points = [];
          routeData.forEach((key, value) => points.add(value as Map));
          
          points.sort((a, b) {
            final num tsA = a['timestamp'] ?? 0;
            final num tsB = b['timestamp'] ?? 0;
            return tsA.compareTo(tsB);
          });
          
          if (mounted && points.isNotEmpty) {
            if (points.length != _lastPoints.length) {
              _updateRoutePolyline(points);
            }
            
            final lastPoint = points.last;
            final double lat = (lastPoint['lat'] ?? 0.0).toDouble();
            final double lng = (lastPoint['lng'] ?? 0.0).toDouble();
            
            if (lat != 0 && lng != 0) {
              final latestPos = geo.Position(
                latitude: lat, longitude: lng,
                timestamp: DateTime.now(), accuracy: (lastPoint['accuracy'] ?? 0.0).toDouble(),
                altitude: 0, heading: (lastPoint['heading'] ?? 0.0).toDouble(),
                speed: (lastPoint['speed'] ?? 0.0).toDouble(),
                speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
              );
              
              _lastLocalPos = latestPos;
              _updateLocalDriverMarker(latestPos);
              
              if (_isFollowLocked && mapboxMap != null) {
                mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat))));
              }
            }
            _lastPoints = points;
          }
        }
        if (_managersReady) _updateSpecialMarkers(data);
      }
    });
  }

  void _onMapCreated(MapboxMap map) { mapboxMap = map; }

  void _onStyleLoaded(dynamic data) async {
    debugPrint("[DRIVER MAP] Style loaded. Initializing layers...");
    
    _driverSourceCreated = false;
    _routeSourceCreated = false;
    _specialMarkersCreated = false;

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
    
    _liveDriverCircle = null;
    _liveDriverHalo = null;
    _liveDriverLabel = null;

    setState(() => _managersReady = true);
    
    if (_lastLocalPos != null) _updateLocalDriverMarker(_lastLocalPos!);
    if (_lastTruckData != null) _lastTruckData!.forEach((k, v) => _updateSingleTruckMarker(k.toString(), v as Map));
    if (_lastPoints.isNotEmpty) _updateRoutePolyline(_lastPoints);
    if (_lastSessionData != null) _updateSpecialMarkers(_lastSessionData!);
  }

  Future<void> _updateLocalDriverMarker(geo.Position pos) async {
    if (mapboxMap == null) return;

    final String sourceId = "driver-live-location-source";
    final tid = (widget.focusTruckId ?? "GT-001").toUpperCase();
    
    final geojson = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature", 
          "geometry": {"type": "Point", "coordinates": [pos.longitude, pos.latitude]}, 
          "properties": {"name": "DRIVER", "truckId": tid, "status": _currentStatus}
        }
      ]
    };

    try {
      final style = mapboxMap!.style;
      bool sourceExists = await style.styleSourceExists(sourceId);
      
      if (!_driverSourceCreated || !sourceExists) {
        if (!sourceExists) {
          await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(geojson)));
        }

        // 1. HALO (Status Indicator)
        if (!(await style.styleLayerExists("driver-live-location-halo"))) {
          await style.addLayer(CircleLayer(
            id: "driver-live-location-halo", 
            sourceId: sourceId, 
            circleRadius: 18.0, 
            circleOpacity: 0.3,
            circleStrokeWidth: 2.0,
            circleSortKey: 3100.0
          ));
        }

        // 2. CENTER CIRCLE
        if (!(await style.styleLayerExists("driver-live-location-circle"))) {
          await style.addLayer(CircleLayer(
            id: "driver-live-location-circle", 
            sourceId: sourceId, 
            circleRadius: 8.0, 
            circleColor: Colors.green.toARGB32(), 
            circleStrokeWidth: 3.0, 
            circleStrokeColor: Colors.white.toARGB32(), 
            circleSortKey: 3200.0
          ));
        }

        // 3. LABEL
        if (!(await style.styleLayerExists("driver-live-location-label"))) {
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
            symbolSortKey: 3300.0,
            textAllowOverlap: true
          ));
        }

        final statusColorExpression = [
          "match", ["get", "status"],
          "IDLE", "#FFFF00",
          "FULL", "#FF1493",
          "FINISHED", "#000000",
          "#00FF00" 
        ];

        await style.setStyleLayerProperty("driver-live-location-halo", "circle-color", statusColorExpression);
        await style.setStyleLayerProperty("driver-live-location-halo", "circle-stroke-color", statusColorExpression);

        if (mounted) setState(() => _driverSourceCreated = true);
        debugPrint("[DRIVER MARKER] Source and Layers established at: ${pos.latitude}, ${pos.longitude}");
      } else {
        // FAST DATA UPDATE
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(geojson));
      }
    } catch (e) {
      debugPrint("[DRIVER MARKER] Style Update Error: $e");
    }
  }

  int _getStatusHaloColorInt() {
     switch(_currentStatus) {
       case "IDLE": return Colors.yellow.toARGB32();
       case "FULL": return Colors.pinkAccent.toARGB32();
       case "FINISHED": return Colors.black.toARGB32();
       default: return Colors.green.toARGB32();
     }
  }

  void _updateSpecialMarkers(Map data) async {
    if (mapboxMap == null) return;
    final String sourceId = "driver-special-markers-source";
    final List<Map<String, dynamic>> features = [];

    if (data['start_lat'] != null && data['start_lng'] != null) {
      features.add({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [data['start_lng'], data['start_lat']]},
        "properties": {"label": "START POINT", "type": "START"}
      });
    }
    if (data['finish_lat'] != null && data['finish_lng'] != null) {
      features.add({
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [data['finish_lng'], data['finish_lat']]},
        "properties": {"label": "🏁 FINISH", "type": "FINISH"}
      });
    }

    if (features.isEmpty) return;
    final geojson = {"type": "FeatureCollection", "features": features};

    try {
      final style = mapboxMap!.style;
      bool sourceExists = await style.styleSourceExists(sourceId);
      if (!_specialMarkersCreated || !sourceExists) {
        if (!sourceExists) await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(geojson)));
        
        if (!(await style.styleLayerExists("driver-special-circles"))) {
          await style.addLayer(CircleLayer(
            id: "driver-special-circles", sourceId: sourceId, 
            circleRadius: 6.0, circleStrokeWidth: 2.0, circleStrokeColor: Colors.white.toARGB32(),
          ));
          await style.setStyleLayerProperty("driver-special-circles", "circle-color", 
            ["match", ["get", "type"], "START", "#2196F3", "#000000"] // Blue for START, Black for FINISH
          );
        }
        if (!(await style.styleLayerExists("driver-special-labels"))) {
          await style.addLayer(SymbolLayer(
            id: "driver-special-labels", sourceId: sourceId, 
            textField: "{label}", textSize: 11.0, textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.0,
          ));
          await style.setStyleLayerProperty("driver-special-labels", "text-offset", 
            ["match", ["get", "type"], "START", ["literal", [0, 1.5]], ["literal", [0, -1.5]]]
          );
          await style.setStyleLayerProperty("driver-special-labels", "text-color", 
            ["match", ["get", "type"], "START", "#2196F3", "#000000"]
          );
        }
        if (mounted) setState(() => _specialMarkersCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(geojson));
      }
    } catch (e) {}
  }

  void _updateSingleTruckMarker(String id, Map data) {
    if (!_managersReady || _pointAnnotationManager == null) return;
    final String truckId = (data['truck_id'] ?? id).toString().toUpperCase();
    final String targetId = (widget.focusTruckId ?? "GT-001").toUpperCase();
    if (truckId == targetId) return; 

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
    
    points.sort((a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));

    final List<Map> smoothedPoints = [];
    if (points.isNotEmpty) {
      smoothedPoints.add(points.first);
      for (int i = 1; i < points.length; i++) {
        final prev = smoothedPoints.last;
        final curr = points[i];
        final double d = geo.Geolocator.distanceBetween(
          (prev['lat'] ?? 0.0).toDouble(), (prev['lng'] ?? 0.0).toDouble(),
          (curr['lat'] ?? 0.0).toDouble(), (curr['lng'] ?? 0.0).toDouble()
        );
        if (d > 4.0 || prev['status'] != curr['status'] || i == points.length - 1) smoothedPoints.add(curr);
      }
    }

    final String sourceId = "driver-route-source";
    final List<Map<String, dynamic>> segments = [];
    
    for (int i = 1; i < smoothedPoints.length; i++) {
      final prev = smoothedPoints[i - 1];
      final curr = smoothedPoints[i];
      final String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();
      final bool isGap = ((curr['timestamp'] ?? 0) as int) - ((prev['timestamp'] ?? 0) as int) > 60000;

      if (!isGap) {
        if (segments.isNotEmpty && segments.last['properties']['color'] == color) {
          final List coords = segments.last['geometry']['coordinates'];
          coords.add([(curr['lng'] ?? 0.0).toDouble(), (curr['lat'] ?? 0.0).toDouble()]);
        } else {
          segments.add({
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": [
                [(prev['lng'] ?? 0.0).toDouble(), (prev['lat'] ?? 0.0).toDouble()],
                [(curr['lng'] ?? 0.0).toDouble(), (curr['lat'] ?? 0.0).toDouble()]
              ]
            },
            "properties": {"color": color, "isGap": false}
          });
        }
      }
    }

    final featureCollection = {"type": "FeatureCollection", "features": segments};
    
    try {
      final style = mapboxMap!.style;
      bool sourceCreated = await style.styleSourceExists(sourceId);
      if (!sourceCreated) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        try { await style.removeStyleLayer("driver-route-layer"); } catch(_) {}
        await style.addLayer(LineLayer(
          id: "driver-route-layer", sourceId: sourceId, 
          lineColor: Colors.green.toARGB32(), lineWidth: 10.0, lineOpacity: 1.0, 
          lineCap: LineCap.ROUND, lineJoin: LineJoin.ROUND
        ));
        await style.setStyleLayerProperty("driver-route-layer", "line-color", [
          "match", ["get", "color"],
          "GREEN", "#00FF00", "YELLOW", "#FFFF00", "PINK", "#FF1493", "BLACK", "#000000", "BLUE", "#0000FF", "#00FF00"
        ]);
      } else { 
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection)); 
      }
    } catch (e) {}
  }

  void _clearRoute() async {
    if (mapboxMap == null) return;
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
            viewport: CameraViewportState(center: Point(coordinates: _balintawakCenter), zoom: 14.5)
          ),
          Positioned(top: 60, right: 20, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("GPS: ${_lastLocalPos != null ? 'LOCKED' : 'SEARCHING...'}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            if (_lastLocalPos != null) ...[
              Text("LATEST: ${_lastLocalPos!.latitude.toStringAsFixed(6)}, ${_lastLocalPos!.longitude.toStringAsFixed(6)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 9)), 
              Text("ACC: ${_lastLocalPos!.accuracy.toStringAsFixed(1)}m", style: const TextStyle(color: Colors.white70, fontSize: 8))
            ],
            Text("MAP: ${mapboxMap != null ? 'READY' : 'LOADING...'}", style: const TextStyle(color: Colors.white, fontSize: 10)),
            Text("STATUS: $_currentStatus", style: TextStyle(color: _getStatusColor(_currentStatus), fontSize: 10, fontWeight: FontWeight.w900)),
          ]))),
          if (!widget.isEmbedded) Positioned(top: 50, left: 20, child: FloatingActionButton(mini: true, backgroundColor: Colors.white, child: const Icon(Icons.arrow_back, color: Colors.black), onPressed: widget.onBack ?? () => Navigator.pop(context))),
          
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
