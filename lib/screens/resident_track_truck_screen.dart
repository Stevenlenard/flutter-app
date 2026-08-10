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
  List<Map<dynamic, dynamic>> _trucks = [];
  final Set<String> _comparingTrucks = {};
  geo.Position? _residentPosition;
  
  PolylineAnnotationManager? _polylineAnnotationManager;
  final Map<String, StreamSubscription> _routeSubscriptions = {};

  bool _managersReady = false;
  bool _truckLayersCreated = false;
  
  // Barangay Balintawak center coordinate
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

          // ONLY SHOW TRUCKS THAT ARE ONLINE AND ACTIVE
          // AND updated within the last 5 minutes (stale data prevention)
          bool isFresh = true;
          if (val['lastSeen'] != null) {
            final int lastSeen = (val['lastSeen'] as int);
            final int now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastSeen > 300000) { // 5 minutes timeout
              isFresh = false;
            }
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
          debugPrint("RESIDENT TRACK DEBUG: Found ${list.length} active trucks");
          for (var t in list) {
            debugPrint("[RESIDENT LISTENER] truckId = ${t['truck_id']}, lat = ${t['latitude']}, lng = ${t['longitude']}, status = ${t['status']}");
          }
          setState(() => _trucks = list);
          _updateTruckMarkers();
          
          for (var t in list) {
            final String tid = t['truck_id'];
            final String? sid = t['current_session'];
            if (sid != null && !_routeSubscriptions.containsKey(tid)) {
              _setupRouteSubscription(tid, sid);
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
        _updateRoutePolyline(points);
      }
    });
  }

  void _updateRoutePolyline(List<Map> points) async {
    if (_polylineAnnotationManager == null || points.length < 2) return;
    _polylineAnnotationManager?.deleteAll();
    List<Position> currentSegment = [];
    String currentColor = (points.first['color'] ?? 'BLUE').toString().toUpperCase();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final color = (p['color'] ?? 'BLUE').toString().toUpperCase();
      final pos = Position((p['lng'] ?? 0.0).toDouble(), (p['lat'] ?? 0.0).toDouble());
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
    _polylineAnnotationManager?.create(PolylineAnnotationOptions(
      geometry: LineString(coordinates: segment),
      lineColor: color.toARGB32(),
      lineWidth: 4.0,
      lineOpacity: 0.8,
    ));
  }

  void _recenterToBalintawak() {
    mapboxMap?.setCamera(CameraOptions(
      center: Point(coordinates: _balintawakCenter),
      zoom: 14.5,
    ));
  }

  void _recenterToResident() {
    if (_residentPosition == null) return;
    mapboxMap?.setCamera(CameraOptions(
      center: Point(coordinates: Position(_residentPosition!.longitude, _residentPosition!.latitude)),
      zoom: 16.5,
    ));
  }

  void _focusOnTruck(Map<dynamic, dynamic> truck) {
    final double lat = (truck['latitude'] ?? 0.0).toDouble();
    final double lng = (truck['longitude'] ?? 0.0).toDouble();
    if (lat == 0 || lng == 0) return;
    mapboxMap?.setCamera(CameraOptions(
      center: Point(coordinates: Position(lng, lat)),
      zoom: 17.5,
    ));
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
  }

  void _onStyleLoaded(dynamic data) async {
    // 1. DISABLE NATIVE BLUE PUCK (We will use a custom one for better layering)
    mapboxMap?.location.updateSettings(LocationComponentSettings(
      enabled: false,
      pulsingEnabled: false,
    ));
    
    _polylineAnnotationManager = await mapboxMap?.annotations.createPolylineAnnotationManager();
    
    if (mounted) setState(() => _managersReady = true);
    
    _updateTruckMarkers();
    
    // Default startup behavior: focus Balintawak
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
      final String status = (truck['status'] ?? 'IDLE').toString().toUpperCase();
      
      return {
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [lng, lat]
        },
        "properties": {
          "truckId": tid,
          "status": status,
          "label": "DRIVER\n$tid"
        }
      };
    }).toList();

    final featureCollection = {
      "type": "FeatureCollection",
      "features": features
    };

    // 2. Resident "YOU" label
    final residentFeature = _residentPosition == null ? null : {
      "type": "Feature",
      "geometry": {
        "type": "Point",
        "coordinates": [_residentPosition!.longitude, _residentPosition!.latitude]
      },
      "properties": {
        "label": "YOU / RESIDENT"
      }
    };

    try {
      final style = mapboxMap!.style;
      bool layersExist = await style.styleLayerExists(circleLayerId) && 
                         await style.styleLayerExists(labelLayerId);

      if (!_truckLayersCreated || !layersExist) {
        debugPrint("[RESIDENT MAP] Creating Source and Layers...");
        
        // Clean up previous attempts
        try { await style.removeStyleLayer(circleLayerId); } catch (_) {}
        try { await style.removeStyleLayer(labelLayerId); } catch (_) {}
        try { await style.removeStyleLayer("resident-marker-circle"); } catch (_) {}
        try { await style.removeStyleLayer("resident-marker-label"); } catch (_) {}
        try { await style.removeStyleSource(sourceId); } catch (_) {}
        try { await style.removeStyleSource("resident-marker-source"); } catch (_) {}

        // 1. CREATE TRUCK SOURCE
        await style.addSource(GeoJsonSource(id: sourceId, data: jsonEncode(featureCollection)));

        // 2. CREATE RESIDENT SOURCE
        await style.addSource(GeoJsonSource(id: "resident-marker-source", data: jsonEncode({
          "type": "FeatureCollection",
          "features": residentFeature != null ? [residentFeature] : []
        })));

        // 3. CREATE RESIDENT CIRCLE LAYER
        await style.addLayer(CircleLayer(
          id: "resident-marker-circle",
          sourceId: "resident-marker-source",
          circleRadius: 7.0,
          circleColor: Colors.blue.toARGB32(),
          circleStrokeWidth: 3.0,
          circleStrokeColor: Colors.white.toARGB32(),
          circleSortKey: 2000.0, 
          visibility: mbox.Visibility.VISIBLE,
        ));

        // 4. CREATE RESIDENT LABEL LAYER
        await style.addLayer(SymbolLayer(
          id: "resident-marker-label",
          sourceId: "resident-marker-source",
          textField: "{label}",
          textSize: 10.0,
          textColor: Colors.blue.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2.0,
          textAnchor: TextAnchor.TOP,
          textOffset: [0, 1.2],
          symbolSortKey: 2000.0,
          visibility: mbox.Visibility.VISIBLE,
        ));

        // 5. CREATE TRUCK CIRCLE LAYER
        await style.addLayer(CircleLayer(
          id: circleLayerId,
          sourceId: sourceId,
          circleRadius: 9.0,
          circleColor: Colors.green.toARGB32(),
          circleStrokeWidth: 3.0,
          circleStrokeColor: Colors.white.toARGB32(),
          circleSortKey: 3000.0,
          visibility: mbox.Visibility.VISIBLE,
        ));

        // 6. CREATE TRUCK LABEL LAYER
        await style.addLayer(SymbolLayer(
          id: labelLayerId,
          sourceId: sourceId,
          textField: "{label}",
          textSize: 13.0,
          textColor: Colors.green.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2.0,
          textAnchor: TextAnchor.BOTTOM,
          textOffset: [0, -1.2],
          symbolSortKey: 3000.0,
          textAllowOverlap: true,
          iconAllowOverlap: true,
          visibility: mbox.Visibility.VISIBLE,
        ));

        if (mounted) setState(() => _truckLayersCreated = true);
      } else {
        // UPDATE SOURCES
        await style.setStyleSourceProperty(sourceId, "data", jsonEncode(featureCollection));
        await style.setStyleSourceProperty("resident-marker-source", "data", jsonEncode({
          "type": "FeatureCollection",
          "features": residentFeature != null ? [residentFeature] : []
        }));
      }
    } catch (e) {
      debugPrint("[RESIDENT MAP] Marker Update Error: $e");
      if (mounted) setState(() => _truckLayersCreated = false);
    } finally {
      _isUpdatingMarkers = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isDesktop = constraints.maxWidth >= 900;
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA), 
        body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        floatingActionButton: _buildMapControls(),
      );
    });
  }

  Widget _buildMapControls() {
    return Positioned(
      bottom: 200, right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFab(Icons.my_location_rounded, "My Location", _recenterToResident),
          const SizedBox(height: 12),
          _buildFab(Icons.map_outlined, "Recenter Balintawak", _recenterToBalintawak),
        ],
      ),
    );
  }

  Widget _buildFab(IconData icon, String label, VoidCallback onTap) {
    return FloatingActionButton.small(
      heroTag: label,
      onPressed: onTap,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.tealText,
      child: Icon(icon),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(children: [
      Expanded(child: Stack(children: [
        Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5))), 
        _buildHeader(),
        _buildDebugOverlay()
      ])),
      Container(width: 400, decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20, offset: const Offset(-5, 0))]), child: _buildFleetStatusContent(null))
    ]);
  }

  Widget _buildMobileLayout() {
    return Stack(children: [
      Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, viewport: CameraViewportState(center: Point(coordinates: Position(121.1623, 13.9413)), zoom: 14.5))),
      _buildHeader(),
      _buildDebugOverlay(),
      Positioned.fill(child: DraggableScrollableSheet(initialChildSize: 0.45, minChildSize: 0.18, maxChildSize: 0.95, snap: true, snapSizes: const [0.18, 0.45, 0.95], builder: (context, scrollController) => PointerInterceptor(child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(40)), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 25, spreadRadius: 5, offset: const Offset(0, -5))]), child: _buildFleetStatusContent(scrollController, isMobile: true)))))
    ]);
  }

  Widget _buildDebugOverlay() {
    final activeTrucksWithGps = _trucks.where((t) => (t['latitude'] ?? 0) != 0).toList();
    return Positioned(
      top: 100, right: 20,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black54,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("DATA TRUCKS: ${_trucks.length}", style: const TextStyle(color: Colors.white, fontSize: 10)),
            Text("GPS TRUCKS: ${activeTrucksWithGps.length}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ...activeTrucksWithGps.map((t) => Text("${t['truck_id']}: ${t['latitude']}, ${t['longitude']}", style: const TextStyle(color: Colors.greenAccent, fontSize: 9))),
            Text("MAP READY: ${mapboxMap != null}", style: const TextStyle(color: Colors.white, fontSize: 10)),
            Text("LAYERS READY: $_truckLayersCreated", style: const TextStyle(color: Colors.white, fontSize: 10)),
            Text("RESIDENT LOC: ${_residentPosition != null}", style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
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

    // Use current session data from Firebase
    String eta;
    if (truck['eta_minutes'] != null) eta = "${truck['eta_minutes']} mins";
    else eta = "${PredictionEngine.estimateArrivalTime(distance > 0 ? distance : 2.5, [speed > 5 ? speed : 15.0]).toStringAsFixed(0)} mins";

    return InkWell(
      onTap: () => _focusOnTruck(truck),
      child: Container(margin: const EdgeInsets.fromLTRB(20, 0, 20, 16), padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 12, offset: const Offset(0, 4))], border: Border.all(color: const Color(0xFFF8F9FA), width: 1.5)), child: Column(children: [
        Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF00897B), size: 26)), const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(truckId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Color(0xFF1A1A1A))), Text(driverName, style: const TextStyle(color: Color(0xFF757575), fontSize: 12, fontWeight: FontWeight.w500))])), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(12)), child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900))), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(eta, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))), const Text("ETA", style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w700))])]),
        const SizedBox(height: 28),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildRefinedInfo(Icons.speed_rounded, "Fleet Velocity", "${speed.toStringAsFixed(1)} km/h"), _buildRefinedInfo(Icons.location_on_outlined, "Current Area", (truck['current_purok'] ?? "Barangay Balintawak").toString())]),
        const SizedBox(height: 24),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStatItem("Distance", "${distance.toStringAsFixed(2)}km"), Container(width: 1, height: 20, color: Colors.black12), _buildStatItem("Accuracy", "${(truck['accuracy'] ?? 0.0).toStringAsFixed(1)}m")])),
        const SizedBox(height: 24),
        Row(children: [Expanded(child: _buildSecondaryButton("TRACK TRUCK", Icons.center_focus_strong_rounded, () => _focusOnTruck(truck))), const SizedBox(width: 12), Expanded(child: _buildPrimaryButton(_comparingTrucks.contains(truckId) ? "HIDE PATH" : "COMPARE PATH", Icons.insights_rounded, _comparingTrucks.contains(truckId) ? const Color(0xFFFFA726) : const Color(0xFF00BFA5), () => setState(() => _comparingTrucks.contains(truckId) ? _comparingTrucks.remove(truckId) : _comparingTrucks.add(truckId))))])
      ])),
    );
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
    return Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFFF0F0F0)), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Tracking Guide", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))), SizedBox(height: 20), _GuideRow(Icons.check_circle_outline_rounded, "Green indicates active collection"), SizedBox(height: 12), _GuideRow(Icons.check_circle_outline_rounded, "Orange indicates idle or stopped unit"), SizedBox(height: 12), _GuideRow(Icons.check_circle_outline_rounded, "Track real-time ETA and road distance")]));
  }
}

class _GuideRow extends StatelessWidget {
  final IconData icon; final String text;
  const _GuideRow(this.icon, this.text);
  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(icon, color: const Color(0xFF00BFA5), size: 18), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w500)))]);
  }
}
