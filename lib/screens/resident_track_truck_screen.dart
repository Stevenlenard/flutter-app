import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size, Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbox show Visibility;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/prediction_engine.dart';
import '../utils/app_theme.dart';

class ResidentTrackTruckScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const ResidentTrackTruckScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<ResidentTrackTruckScreen> createState() => _ResidentTrackTruckScreenState();
}

class _ResidentTrackTruckScreenState extends State<ResidentTrackTruckScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  List<Map<dynamic, dynamic>> _trucks = [];
  final Set<String> _comparingTrucks = {};
  geo.Position? _residentPosition;
  
  final Map<String, StreamSubscription> _routeSubscriptions = {};
  final Map<String, Position?> _sessionStartPoints = {}; 
  final Map<String, List<Map>> _lastRoutePoints = {}; 

  bool _managersReady = false;
  bool _truckLayersCreated = false;
  
  final Position _balintawakCenter = Position(121.1623, 13.9413);

  @override
  void initState() {
    super.initState();
    _listenToTrucks();
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
    
    geo.Geolocator.getPositionStream().listen((pos) {
      if (mounted) {
        setState(() => _residentPosition = pos);
        _updateTruckMarkers();
      }
    });
    
    geo.Position startPos = await geo.Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() => _residentPosition = startPos);
    }
  }

  void _listenToTrucks() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        final Map<String, Map<dynamic, dynamic>> uniqueTrucks = {};

        data.forEach((key, value) {
          final val = value as Map;
          final String status = (val['status'] ?? '').toString().toUpperCase();
          final bool isOnline = val['isOnline'] == true;
          final String rawTruckId = (val['truck_id'] ?? key.toString());
          final String truckId = rawTruckId.toUpperCase().trim();

          bool isFresh = true;
          if (val['lastSeen'] != null) {
            final int lastSeen = (val['lastSeen'] as int);
            final int now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastSeen > 300000) isFresh = false;
          }

          if (isOnline && isFresh && (status == 'ACTIVE' || status == 'COLLECTING' || status == 'IDLE' || status == 'FULL')) {
            if (!uniqueTrucks.containsKey(truckId)) {
              uniqueTrucks[truckId] = {...val, 'id': key.toString(), 'truck_id': truckId};
            } else {
              final existing = uniqueTrucks[truckId]!;
              final existingTime = DateTime.tryParse(existing['updatedAt'] ?? '') ?? DateTime(2000);
              final newTime = DateTime.tryParse(val['updatedAt'] ?? '') ?? DateTime(2000);
              if (newTime.isAfter(existingTime.add(const Duration(seconds: 1)))) {
                uniqueTrucks[truckId] = {...val, 'id': key.toString(), 'truck_id': truckId};
              }
            }
          }
        });

        final List<Map<dynamic, dynamic>> list = uniqueTrucks.values.toList();

        if (mounted) {
          setState(() => _trucks = list);
          _updateTruckMarkers();
          
          final activeTruckIds = list.map((t) => t['truck_id'] as String).toSet();
          final trucksToClear = _routeSubscriptions.keys.where((id) => !activeTruckIds.contains(id)).toList();
          
          for (var id in trucksToClear) {
            _routeSubscriptions[id]?.cancel();
            _routeSubscriptions.remove(id);
            _clearTruckRoute(id);
          }

          for (var t in list) {
            final String tid = t['truck_id'];
            final String? sid = t['current_session'];
            if (sid != null) {
              if (!_routeSubscriptions.containsKey(tid)) _setupRouteSubscription(tid, sid);
            } else {
              _routeSubscriptions[tid]?.cancel();
              _routeSubscriptions.remove(tid);
              _clearTruckRoute(tid);
            }
          }
        }
      } else {
        if (mounted) setState(() => _trucks = []);
      }
    });
  }

  void _setupRouteSubscription(String truckId, String sessionId) {
    _routeSubscriptions[truckId]?.cancel();
    _routeSubscriptions[truckId] = _database.ref('driver_routes/$sessionId/route').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        final List<Map> points = [];
        data.forEach((key, value) => points.add(value as Map));
        points.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
        
        _lastRoutePoints[truckId] = points;

        if (_comparingTrucks.contains(truckId)) {
          _updateRoutePolyline(truckId, points);
        }
      }
    });

    _database.ref('driver_routes/$sessionId').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        if (data['start_lat'] != null && data['start_lng'] != null) {
          if (mounted) {
            setState(() => _sessionStartPoints[truckId] = Position(data['start_lng'], data['start_lat']));
            _updateTruckMarkers();
          }
        }
      }
    });
  }

  void _clearTruckRoute(String truckId) async {
     if (mapboxMap == null) return;
     try {
       final style = mapboxMap!.style;
       final String sourceId = "route-source-$truckId";
       if (await style.styleSourceExists(sourceId)) {
         await style.setStyleSourceProperty(sourceId, "data", jsonEncode({"type": "FeatureCollection", "features": []}));
       }
     } catch (_) {}
     if (mounted) {
       setState(() => _sessionStartPoints.remove(truckId));
       _updateTruckMarkers();
     }
  }

  void _updateRoutePolyline(String truckId, List<Map> points) async {
    if (mapboxMap == null || points.length < 2) return;
    
    points.sort((a, b) => (a['timestamp'] as num).compareTo(b['timestamp'] as num));

    final String sourceId = "route-source-$truckId";
    final List<Map<String, dynamic>> segments = [];

    // EDGE-BASED SEGMENTATION: Connect points directly to avoid gaps
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      
      final double prevLng = (prev['lng'] ?? 0.0).toDouble();
      final double prevLat = (prev['lat'] ?? 0.0).toDouble();
      final double currLng = (curr['lng'] ?? 0.0).toDouble();
      final double currLat = (curr['lat'] ?? 0.0).toDouble();
      final int prevTs = (prev['timestamp'] ?? 0) as int;
      final int currTs = (curr['timestamp'] ?? 0) as int;

      final String color = (curr['color'] ?? 'GREEN').toString().toUpperCase();
      final bool isGap = (currTs - prevTs) > 60000;

      if (!isGap) {
        if (segments.isNotEmpty && segments.last['properties']['color'] == color) {
          final List coords = segments.last['geometry']['coordinates'];
          if (coords.isEmpty || coords.last[0] != currLng || coords.last[1] != currLat) {
            coords.add([currLng, currLat]);
          }
        } else {
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
      if (!(await style.styleSourceExists(sourceId))) {
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));
        await style.addLayer(LineLayer(
          id: "route-layer-$truckId",
          sourceId: sourceId,
          lineColor: Colors.green.toARGB32(),
          lineWidth: 8.0,
          lineOpacity: 0.9,
          lineCap: LineCap.ROUND,
          lineJoin: LineJoin.ROUND,
        ));
        
        await style.setStyleLayerProperty("route-layer-$truckId", "line-color", [
          "match", ["get", "color"],
          "GREEN", "#00FF00",
          "YELLOW", "#FFFF00",
          "PINK", "#FF1493",
          "BLACK", "#000000",
          "BLUE", "#0000FF",
          "#00FF00"
        ]);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection));
      }
    } catch (e) {
      debugPrint("[RESIDENT MAP] Route Error: $e");
    }
  }

  void _recenterToBalintawak() {
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: _balintawakCenter), zoom: 14.5));
  }

  void _recenterToResident() {
    if (_residentPosition == null) return;
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(_residentPosition!.longitude, _residentPosition!.latitude)), zoom: 16.5));
  }

  void _focusOnTruck(Map<dynamic, dynamic> truck) {
    final double lat = (truck['latitude'] ?? 0.0).toDouble();
    final double lng = (truck['longitude'] ?? 0.0).toDouble();
    if (lat == 0 || lng == 0) return;
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat)), zoom: 17.5));
  }

  void _onMapCreated(MapboxMap map) { mapboxMap = map; }

  void _onStyleLoaded(dynamic data) async {
    mapboxMap?.location.updateSettings(LocationComponentSettings(enabled: false, pulsingEnabled: false));
    _pointAnnotationManager = await mapboxMap!.annotations.createPointAnnotationManager();
    if (mounted) setState(() => _managersReady = true);
    _updateTruckMarkers();
    _recenterToBalintawak();
  }

  bool _isUpdatingMarkers = false;

  void _updateTruckMarkers() async {
    if (mapboxMap == null || _isUpdatingMarkers) return;
    _isUpdatingMarkers = true;
    final String sourceId = "trucks-live-location-source";
    final String circleLayerId = "trucks-live-location-circle";
    final String labelLayerId = "trucks-live-location-label";

    final List<Map<String, dynamic>> features = _trucks
        .where((t) => (t['latitude'] ?? 0) != 0 && (t['longitude'] ?? 0) != 0)
        .map((truck) {
      final double lat = (truck['latitude'] ?? 0.0).toDouble();
      final double lng = (truck['longitude'] ?? 0.0).toDouble();
      final String tid = truck['truck_id'].toString();
      return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lng, lat]},
        "properties": {"type": "TRUCK", "truckId": tid, "label": "DRIVER\n$tid"}
      };
    }).toList();

    for (var entry in _sessionStartPoints.entries) {
      if (entry.value != null && _comparingTrucks.contains(entry.key)) {
        features.add({
          "type": "Feature",
          "geometry": {"type": "Point", "coordinates": [entry.value!.lng, entry.value!.lat]},
          "properties": {"type": "SESSION_START", "label": "START / ${entry.key}"}
        });
      }
    }

    final residentFeature = _residentPosition == null ? null : {
      "type": "Feature",
      "geometry": {"type": "Point", "coordinates": [_residentPosition!.longitude, _residentPosition!.latitude]},
      "properties": {"label": "YOU / RESIDENT"}
    };

    try {
      final style = mapboxMap!.style;
      bool layersExist = await style.styleLayerExists(circleLayerId);
      if (!_truckLayersCreated || !layersExist) {
        try { await style.removeStyleLayer(circleLayerId); } catch (_) {}
        try { await style.removeStyleLayer(labelLayerId); } catch (_) {}
        try { await style.removeStyleLayer("resident-marker-circle"); } catch (_) {}
        try { await style.removeStyleLayer("resident-marker-label"); } catch (_) {}
        try { await style.removeStyleLayer("session-start-circle"); } catch (_) {}
        try { await style.removeStyleLayer("session-start-label"); } catch (_) {}
        try { await style.removeStyleSource(sourceId); } catch (_) {}
        try { await style.removeStyleSource("resident-marker-source"); } catch (_) {}

        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode({"type": "FeatureCollection", "features": features})));
        await style.addSource(GeoJsonSource(id: "resident-marker-source", data: jsonEncode({"type": "FeatureCollection", "features": residentFeature != null ? [residentFeature] : []})));

        await style.addLayer(CircleLayer(id: "resident-marker-circle", sourceId: "resident-marker-source", circleRadius: 7.0, circleColor: Colors.blue.toARGB32(), circleStrokeWidth: 3.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 2000.0));
        await style.addLayer(SymbolLayer(id: "resident-marker-label", sourceId: "resident-marker-source", textField: "{label}", textSize: 10.0, textColor: Colors.blue.toARGB32(), textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.0, textAnchor: TextAnchor.TOP, textOffset: [0, 1.2], symbolSortKey: 2000.0));

        await style.addLayer(CircleLayer(id: circleLayerId, sourceId: sourceId, circleRadius: 9.0, circleColor: Colors.green.toARGB32(), circleStrokeWidth: 3.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 3000.0, filter: ["==", ["get", "type"], "TRUCK"]));
        await style.addLayer(CircleLayer(id: "session-start-circle", sourceId: sourceId, circleRadius: 7.0, circleColor: Colors.green.shade800.toARGB32(), circleStrokeWidth: 2.0, circleStrokeColor: Colors.white.toARGB32(), circleSortKey: 2500.0, filter: ["==", ["get", "type"], "SESSION_START"]));

        await style.addLayer(SymbolLayer(id: labelLayerId, sourceId: sourceId, textField: "{label}", textSize: 13.0, textColor: Colors.green.toARGB32(), textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.0, textAnchor: TextAnchor.BOTTOM, textOffset: [0, -1.2], symbolSortKey: 3000.0, textAllowOverlap: true, iconAllowOverlap: true, filter: ["==", ["get", "type"], "TRUCK"]));
        await style.addLayer(SymbolLayer(id: "session-start-label", sourceId: sourceId, textField: "{label}", textSize: 10.0, textColor: Colors.green.shade800.toARGB32(), textHaloColor: Colors.white.toARGB32(), textHaloWidth: 2.0, textAnchor: TextAnchor.BOTTOM, textOffset: [0, -1.0], symbolSortKey: 2500.0, filter: ["==", ["get", "type"], "SESSION_START"]));

        if (mounted) setState(() => _truckLayersCreated = true);
      } else {
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode({"type": "FeatureCollection", "features": features}));
        await style.setStyleSourceProperty("resident-marker-source", "data", jsonEncode({"type": "FeatureCollection", "features": residentFeature != null ? [residentFeature] : []}));
      }
    } catch (e) {
      if (mounted) setState(() => _truckLayersCreated = false);
    } finally { _isUpdatingMarkers = false; }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isDesktop = constraints.maxWidth >= 900;
      return Scaffold(backgroundColor: const Color(0xFFF8F9FA), body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(), floatingActionButton: _buildMapControls());
    });
  }

  Widget _buildMapControls() {
    return Positioned(bottom: 200, right: 16, child: Column(mainAxisSize: MainAxisSize.min, children: [_buildFab(Icons.my_location_rounded, "My Location", _recenterToResident), const SizedBox(height: 12), _buildFab(Icons.map_outlined, "Recenter Balintawak", _recenterToBalintawak)]));
  }

  Widget _buildFab(IconData icon, String label, VoidCallback onTap) {
    return FloatingActionButton.small(heroTag: label, onPressed: onTap, backgroundColor: Colors.white, foregroundColor: AppColors.tealText, child: Icon(icon));
  }

  Widget _buildDesktopLayout() {
    return Row(children: [
      Expanded(child: Stack(children: [Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5))), _buildHeader(), _buildDebugOverlay()])),
      Container(width: 400, decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20, offset: const Offset(-5, 0))]), child: _buildFleetStatusContent(null))
    ]);
  }

  Widget _buildMobileLayout() {
    return Stack(children: [
      Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5))),
      _buildHeader(), _buildDebugOverlay(),
      Positioned.fill(child: DraggableScrollableSheet(initialChildSize: 0.45, minChildSize: 0.18, maxChildSize: 0.95, snap: true, snapSizes: const [0.18, 0.45, 0.95], builder: (context, scrollController) => PointerInterceptor(child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(40)), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 25, spreadRadius: 5, offset: const Offset(0, -5))]), child: _buildFleetStatusContent(scrollController, isMobile: true)))))
    ]);
  }

  Widget _buildDebugOverlay() {
    final activeTrucksWithGps = _trucks.where((t) => (t['latitude'] ?? 0) != 0).toList();
    return Positioned(top: 100, right: 20, child: Container(padding: const EdgeInsets.all(8), color: Colors.black54, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text("DATA TRUCKS: ${_trucks.length}", style: const TextStyle(color: Colors.white, fontSize: 10)),
      Text("GPS TRUCKS: ${activeTrucksWithGps.length}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ...activeTrucksWithGps.map((t) => Text("${t['truck_id']}: ${t['latitude']}, ${t['longitude']}", style: const TextStyle(color: Colors.greenAccent, fontSize: 9))),
      Text("MAP READY: ${mapboxMap != null}", style: const TextStyle(color: Colors.white, fontSize: 10)),
    ])));
  }

  Widget _buildHeader() {
    return Positioned(top: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]), child: SafeArea(child: Row(children: [if (!widget.isEmbedded || widget.onBack != null) IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 20), onPressed: () => widget.onBack != null ? widget.onBack!() : Navigator.pop(context)), const SizedBox(width: 8), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Track Fleet", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))), Text("Active GPS signal connected", style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontWeight: FontWeight.w600))])]))));
  }

  Widget _buildFleetStatusContent(ScrollController? scrollController, {bool isMobile = false}) {
    return ListView(controller: scrollController, physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), padding: EdgeInsets.zero, children: [
      if (isMobile) ...[const SizedBox(height: 12), Center(child: Container(width: 60, height: 8, decoration: BoxDecoration(color: const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(10))))],
      const SizedBox(height: 32),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Fleet Status", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))), Icon(Icons.keyboard_arrow_up_rounded, color: Colors.grey)])),
      const SizedBox(height: 20),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(children: _trucks.isEmpty ? [const Padding(padding: EdgeInsets.all(60), child: Center(child: Text("Scanning for active units...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500))))] : _trucks.map((truck) => _buildOrganizedTruckCard(truck)).toList())),
      _buildFleetGuide(),
      const SizedBox(height: 150)
    ]);
  }

  Widget _buildOrganizedTruckCard(Map<dynamic, dynamic> truck) {
    final String truckId = truck['truck_id'].toString();
    final String status = (truck['status'] ?? 'IDLE').toString().toUpperCase();
    final Color color = status == 'ACTIVE' || status == 'COLLECTING' ? const Color(0xFF00C853) : const Color(0xFFFF1744);
    final double speed = (truck['speed'] ?? 0.0).toDouble();
    final double distance = (truck['distance'] ?? 0.0).toDouble();
    final String driverName = (truck['driver_name'] ?? "Driver").toString();
    String eta;
    if (truck['eta_minutes'] != null) eta = "${truck['eta_minutes']} mins";
    else eta = "${PredictionEngine.estimateArrivalTime(distance > 0 ? distance : 2.5, [speed > 5 ? speed : 15.0]).toStringAsFixed(0)} mins";
    return InkWell(onTap: () => _focusOnTruck(truck), child: Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 16), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 12, offset: const Offset(0, 4))], border: Border.all(color: const Color(0xFFF8F9FA), width: 1.5)), child: Column(children: [
      Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF00897B), size: 26)), const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(truckId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Color(0xFF1A1A1A))), Text(driverName, style: const TextStyle(color: Color(0xFF757575), fontSize: 12, fontWeight: FontWeight.w500))])), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(12)), child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900))), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(eta, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))), const Text("ETA", style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w700))])]),
      const SizedBox(height: 28), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildRefinedInfo(Icons.speed_rounded, "Fleet Velocity", "${speed.toStringAsFixed(1)} km/h"), _buildRefinedInfo(Icons.location_on_outlined, "Current Area", (truck['current_purok'] ?? "Barangay Balintawak").toString())]),
      const SizedBox(height: 24), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStatItem("Distance", "${distance.toStringAsFixed(2)}km"), Container(width: 1, height: 20, color: Colors.black12), _buildStatItem("Accuracy", "${(truck['accuracy'] ?? 0.0).toStringAsFixed(1)}m")])),
      const SizedBox(height: 24), Row(children: [
        Expanded(child: _buildSecondaryButton("TRACK TRUCK", Icons.center_focus_strong_rounded, () => _focusOnTruck(truck))), 
        const SizedBox(width: 12), 
        Expanded(child: _buildPrimaryButton(
          _comparingTrucks.contains(truckId) ? "HIDE PATH" : "PATH", 
          Icons.insights_rounded, 
          _comparingTrucks.contains(truckId) ? const Color(0xFFFFA726) : const Color(0xFF00BFA5), 
          () => _togglePath(truckId)
        ))
      ])
    ])));
  }

  void _togglePath(String truckId) {
    if (!_comparingTrucks.contains(truckId) && !_lastRoutePoints.containsKey(truckId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No active route available for this truck."))
      );
      return;
    }

    setState(() {
      if (_comparingTrucks.contains(truckId)) {
        _comparingTrucks.remove(truckId);
        _clearTruckRoute(truckId);
      } else {
        _comparingTrucks.add(truckId);
        if (_lastRoutePoints.containsKey(truckId)) {
          _updateRoutePolyline(truckId, _lastRoutePoints[truckId]!);
        }
      }
      _updateTruckMarkers();
    });
  }

  Widget _buildRefinedInfo(IconData icon, String label, String val) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 14, color: const Color(0xFF00897B)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w700))]), const SizedBox(height: 4), Text(val, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1A1A)))]);
  }

  Widget _buildStatItem(String label, String val) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(val, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1A1A1A)))]);
  }

  Widget _buildSecondaryButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5F5F5), foregroundColor: const Color(0xFF1A1A1A), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
  }

  Widget _buildPrimaryButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 6, shadowColor: color.withAlpha(100), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
  }

  Widget _buildFleetGuide() {
    return Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFFF0F0F0)), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Tracking Guide", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))), SizedBox(height: 20),
      _GuideRow(Icons.circle, "Green: Active collection", color: Colors.green), SizedBox(height: 12),
      _GuideRow(Icons.circle, "Yellow: Idle / Signal issue", color: Colors.yellow), SizedBox(height: 12),
      _GuideRow(Icons.circle, "Magenta: Truck is FULL", color: Colors.pinkAccent), SizedBox(height: 12),
      _GuideRow(Icons.linear_scale, "Dashed: Signal gap detected", color: Colors.grey), SizedBox(height: 12),
      _GuideRow(Icons.check_circle_outline_rounded, "Track real-time ETA & distance"),
    ]));
  }
}

class _GuideRow extends StatelessWidget {
  final IconData icon; final String text; final Color color;
  const _GuideRow(this.icon, this.text, {this.color = const Color(0xFF00BFA5)});
  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w500)))]);
  }
}
