import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:intl/intl.dart';
import '../utils/prediction_engine.dart';

class TrackTrucksScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const TrackTrucksScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<TrackTrucksScreen> createState() => _TrackTrucksScreenState();
}

class _TrackTrucksScreenState extends State<TrackTrucksScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  List<Map<dynamic, dynamic>> _trucks = [];
  String? _selectedTruckId;

  // Point Annotation Manager for truck icons (Mobile Only)
  PointAnnotationManager? _pointAnnotationManager;
  PolylineAnnotationManager? _polylineAnnotationManager;
  final Map<String, List<PolylineAnnotation>> _truckHeatmapPaths = {};
  final Map<String, PolylineAnnotation> _truckOptimizedPaths = {};

  // For Web Overlay Markers & Paths
  Map<String, Offset> _webMarkerPositions = {};
  Map<String, List<Map<String, dynamic>>> _webHeatmapData = {}; // Stores lat/lng/speed for custom painting
  Map<String, List<Offset>> _webHeatmapPixels = {}; // Projected pixels for drawing
  Map<String, List<Offset>> _webOptimizedPixels = {};

  @override
  void initState() {
    super.initState();
    _listenToTrucks();
  }

  void _listenToTrucks() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        final List<Map<dynamic, dynamic>> list = [];
        data.forEach((key, value) {
          final truckMap = Map<dynamic, dynamic>.from(value as Map);
          truckMap['internal_id'] = key.toString(); 
          if (truckMap['truck_id'] == null) truckMap['truck_id'] = key.toString();
          list.add(truckMap);
        });
        if (mounted) {
          setState(() => _trucks = list);
          if (kIsWeb) {
            _updateWebOverlays();
          } else {
            _updateTruckMarkersNative();
          }
        }
      }
    });
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
  }

  void _onStyleLoaded(dynamic data) async {
    if (!kIsWeb) {
      _pointAnnotationManager = await mapboxMap?.annotations.createPointAnnotationManager();
      _polylineAnnotationManager = await mapboxMap?.annotations.createPolylineAnnotationManager();
      _updateTruckMarkersNative();
    }
  }

  // Unified update for Web markers and paths
  void _updateWebOverlays() async {
    if (!kIsWeb || mapboxMap == null) return;

    // 1. Update Marker Positions
    Map<String, Offset> newMarkerPositions = {};
    for (var truck in _trucks) {
      final double lat = (truck['latitude'] ?? 13.9402).toDouble();
      final double lng = (truck['longitude'] ?? 121.1638).toDouble();
      final String internalId = (truck['internal_id'] ?? "").toString();
      final screenPos = await mapboxMap!.pixelForCoordinate(Point(coordinates: Position(lng, lat)));
      newMarkerPositions[internalId] = Offset(screenPos.x, screenPos.y);
    }

    // 2. Update Heatmap (Strava Line) Pixels
    Map<String, List<Offset>> newHeatmapPixels = {};
    for (var entry in _webHeatmapData.entries) {
      List<Offset> pixels = [];
      for (var point in entry.value) {
        final screenPos = await mapboxMap!.pixelForCoordinate(Point(coordinates: Position(point['lng'], point['lat'])));
        pixels.add(Offset(screenPos.x, screenPos.y));
      }
      newHeatmapPixels[entry.key] = pixels;
    }

    // 3. Update Optimized Path Pixels
    Map<String, List<Offset>> newOptimizedPixels = {};
    if (_webOptimizedPixels.isNotEmpty) {
       final List<Position> idealPathCoords = [Position(121.1638, 13.9402), Position(121.1645, 13.9410), Position(121.1655, 13.9425), Position(121.1668, 13.9440)];
       for (var truckId in _webOptimizedPixels.keys) {
         List<Offset> pixels = [];
         for (var pos in idealPathCoords) {
           final screenPos = await mapboxMap!.pixelForCoordinate(Point(coordinates: pos));
           pixels.add(Offset(screenPos.x, screenPos.y));
         }
         newOptimizedPixels[truckId] = pixels;
       }
    }

    if (mounted) {
      setState(() {
        _webMarkerPositions = newMarkerPositions;
        _webHeatmapPixels = newHeatmapPixels;
        _webOptimizedPixels = newOptimizedPixels;
      });
    }
  }

  void _selectTruck(String truckId, double lat, double lng) {
    setState(() {
      _selectedTruckId = truckId;
    });
    
    mapboxMap?.setCamera(CameraOptions(center: Point(coordinates: Position(lng, lat)), zoom: 16.0, bearing: 0, pitch: 0));

    if (kIsWeb) {
      Future.delayed(const Duration(milliseconds: 100), _updateWebOverlays);
    }
  }

  Future<void> _toggleHeatmap(String truckId) async {
    if (kIsWeb) {
      if (_webHeatmapData.containsKey(truckId)) {
        setState(() {
          _webHeatmapData.remove(truckId);
          _webHeatmapPixels.remove(truckId);
        });
      } else {
        await _fetchHeatmapDataWeb(truckId);
      }
      return;
    }
    
    if (_truckHeatmapPaths.containsKey(truckId)) {
      for (var path in _truckHeatmapPaths[truckId]!) { await _polylineAnnotationManager?.delete(path); }
      setState(() => _truckHeatmapPaths.remove(truckId));
    } else {
      await _drawHeatmap(truckId);
    }
  }

  Future<void> _fetchHeatmapDataWeb(String truckId) async {
    final event = await _database.ref('truck_locations/$truckId/route_history').limitToLast(200).once();
    if (event.snapshot.exists) {
      final List<Map<String, dynamic>> points = [];
      final data = event.snapshot.value;
      
      List<Map<String, dynamic>> rawPoints = [];
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) rawPoints.add({'lat': (value['latitude'] ?? 0).toDouble(), 'lng': (value['longitude'] ?? 0).toDouble(), 'speed': (value['speed'] ?? 0).toDouble()});
        });
      } else if (data is List) {
        for (var p in data) {
          if (p is Map) rawPoints.add({'lat': (p['latitude'] ?? 0).toDouble(), 'lng': (p['longitude'] ?? 0).toDouble(), 'speed': (p['speed'] ?? 0).toDouble()});
        }
      }

      // VALIDATION LOGIC: Filter out noise to ensure it follows the "true road" (rail)
      for (int i = 0; i < rawPoints.length; i++) {
        final p = rawPoints[i];
        if (p['lat'] == 0 || p['lng'] == 0) continue;

        // Skip points that represent impossible jumps (e.g., > 500 meters in a few seconds)
        if (i > 0) {
          double dist = _getDistance(p['lat'], p['lng'], rawPoints[i-1]['lat'], rawPoints[i-1]['lng']);
          if (dist > 0.5) continue; // Skip jumps larger than 500m (GPS noise)
        }
        
        points.add(p);
      }

      setState(() => _webHeatmapData[truckId] = points);
      _updateWebOverlays();
    }
  }

  Future<void> _drawHeatmap(String truckId) async {
    if (_polylineAnnotationManager == null) return;
    final event = await _database.ref('truck_locations/$truckId/route_history').limitToLast(200).once();
    if (event.snapshot.exists) {
      final List<Map<dynamic, dynamic>> rawData = [];
      final data = event.snapshot.value;
      if (data is Map) { data.forEach((key, value) { if (value is Map) rawData.add(Map<dynamic, dynamic>.from(value)); }); }
      else if (data is List) { for (var p in data) { if (p is Map) rawData.add(Map<dynamic, dynamic>.from(p)); } }
      
      if (rawData.length < 2) return;

      List<PolylineAnnotation> segments = [];
      for (int i = 0; i < rawData.length - 1; i++) {
        final p1 = rawData[i]; 
        final p2 = rawData[i + 1];
        
        final double lat1 = (p1['latitude'] ?? 0).toDouble(); 
        final double lng1 = (p1['longitude'] ?? 0).toDouble();
        final double lat2 = (p2['latitude'] ?? 0).toDouble(); 
        final double lng2 = (p2['longitude'] ?? 0).toDouble();
        final double speed = (p2['speed'] ?? 0).toDouble();

        if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) continue;

        // VALIDATION: Filter out jumps/noise (jumps > 500m are discarded)
        double dist = _getDistance(lat1, lng1, lat2, lng2);
        if (dist > 0.5) continue; 

        Color segmentColor = speed < 5 ? Colors.red : (speed < 15 ? Colors.yellow : Colors.green);
        final annotation = await _polylineAnnotationManager!.create(PolylineAnnotationOptions(geometry: LineString(coordinates: [Position(lng1, lat1), Position(lng2, lat2)]), lineColor: segmentColor.toARGB32(), lineWidth: 4.0, lineOpacity: 0.8));
        segments.add(annotation);
      }
      setState(() => _truckHeatmapPaths[truckId] = segments);
    }
  }

  Future<void> _toggleOptimizedRoute(String truckId) async {
    if (kIsWeb) {
      if (_webOptimizedPixels.containsKey(truckId)) {
        setState(() => _webOptimizedPixels.remove(truckId));
      } else {
        setState(() => _webOptimizedPixels[truckId] = []); // Mark as active
        _updateWebOverlays();
      }
      return;
    }
    if (_truckOptimizedPaths.containsKey(truckId)) {
      await _polylineAnnotationManager?.delete(_truckOptimizedPaths[truckId]!);
      setState(() => _truckOptimizedPaths.remove(truckId));
    } else {
      await _drawOptimizedRoute(truckId);
    }
  }

  Future<void> _drawOptimizedRoute(String truckId) async {
    if (_polylineAnnotationManager == null) return;
    final List<Position> idealPath = [Position(121.1638, 13.9402), Position(121.1645, 13.9410), Position(121.1655, 13.9425), Position(121.1668, 13.9440)];
    final annotation = await _polylineAnnotationManager!.create(PolylineAnnotationOptions(geometry: LineString(coordinates: idealPath), lineColor: Colors.blue.toARGB32(), lineWidth: 8.0, lineOpacity: 0.5));
    setState(() => _truckOptimizedPaths[truckId] = annotation);
  }

  void _updateTruckMarkersNative() async {
    if (_pointAnnotationManager == null || _trucks.isEmpty || kIsWeb) return;
    try { await _pointAnnotationManager?.deleteAll(); } catch (_) {}
    for (var truck in _trucks) {
      final double lat = (truck['latitude'] ?? 13.9402).toDouble();
      final double lng = (truck['longitude'] ?? 121.1638).toDouble();
      final String id = (truck['truck_id'] ?? truck['internal_id'] ?? "GT-001").toString();
      try {
        await _pointAnnotationManager?.create(PointAnnotationOptions(geometry: Point(coordinates: Position(lng, lat)), textField: id, textOffset: [0, 2], textColor: Colors.blue.toARGB32(), iconImage: "truck-15"));
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;
        return Scaffold(backgroundColor: const Color(0xFFF8F9FA), body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout());
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: MapWidget(
                  onMapCreated: _onMapCreated,
                  onStyleLoadedListener: _onStyleLoaded,
                  onCameraChangeListener: (cameraChangedEvent) { if (kIsWeb) _updateWebOverlays(); },
                  viewport: CameraViewportState(center: Point(coordinates: Position(121.1638, 13.9402)), zoom: 14.0),
                ),
              ),
              if (kIsWeb) ..._buildWebOverlays(),
              _buildHeader(),
              _buildRouteProgress(true),
            ],
          ),
        ),
        Container(width: 400, decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20, offset: const Offset(-5, 0))]), child: _buildFleetStatusContent(null)),
      ],
    );
  }

  List<Widget> _buildWebOverlays() {
    List<Widget> overlays = [];

    // 1. Draw Paths (Heatmap and Optimized)
    overlays.add(
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: WebPathPainter(
              heatmapData: _webHeatmapData,
              heatmapPixels: _webHeatmapPixels,
              optimizedPixels: _webOptimizedPixels,
            ),
          ),
        ),
      ),
    );

    // 2. Draw Truck Markers
    overlays.addAll(_trucks.map((truck) {
      final String internalId = (truck['internal_id'] ?? "").toString();
      final String id = (truck['truck_id'] ?? internalId).toString();
      final offset = _webMarkerPositions[internalId];
      if (offset == null) return const SizedBox.shrink();

      return Positioned(
        left: offset.dx - 20, top: offset.dy - 40,
        child: Column(
          children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]), child: Text(id, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue))),
            const Icon(Icons.local_shipping, color: Colors.blue, size: 28),
          ],
        ),
      );
    }));

    return overlays;
  }

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Positioned.fill(child: MapWidget(onMapCreated: _onMapCreated, onStyleLoadedListener: _onStyleLoaded, onCameraChangeListener: (cameraChangedEvent) { if (kIsWeb) _updateWebOverlays(); }, viewport: CameraViewportState(center: Point(coordinates: Position(121.1638, 13.9402)), zoom: 14.0))),
        if (kIsWeb) ..._buildWebOverlays(),
        _buildHeader(),
        _buildRouteProgress(false),
        Positioned.fill(child: DraggableScrollableSheet(initialChildSize: 0.45, minChildSize: 0.18, maxChildSize: 0.95, snap: true, snapSizes: const [0.18, 0.45, 0.95], builder: (context, scrollController) { return PointerInterceptor(child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(40)), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, -5))]), child: _buildFleetStatusContent(scrollController, isMobile: true))); })),
      ],
    );
  }

  Widget _buildHeader() {
    return Positioned(top: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]), child: SafeArea(child: Row(children: [if (!widget.isEmbedded || widget.onBack != null) ...[IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)), onPressed: () { if (widget.onBack != null) { widget.onBack!(); } else { Navigator.pop(context); } }), const SizedBox(width: 12)], const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Track Fleet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))), Text("Real-time GPS status", style: TextStyle(fontSize: 12, color: Color(0xFF757575), fontWeight: FontWeight.w500))])]))));
  }

  Widget _buildRouteProgress(bool isDesktop) {
    // Calculate actual progress based on puroks completed if available, or just hide if no active truck
    double progress = 0.0;
    if (_trucks.isNotEmpty) {
      int active = _trucks.where((t) => t['isOnline'] == true).length;
      progress = active > 0 ? 0.3 : 0.0; // Placeholder for overall fleet progress
    }
    return Positioned(top: widget.isEmbedded ? 68 : 96, left: 0, right: 0, child: LinearProgressIndicator(value: progress, backgroundColor: const Color(0xFFE0E0E0), valueColor: const AlwaysStoppedAnimation(Color(0xFF2196F3)), minHeight: 4));
  }

  Widget _buildFleetStatusContent(ScrollController? scrollController, {bool isMobile = false}) {
    return ListView(
      controller: scrollController, physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), padding: EdgeInsets.zero,
      children: [
        if (isMobile) const SizedBox(height: 12),
        if (isMobile) Center(child: Container(width: 60, height: 8, decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(10)))),
        const SizedBox(height: 24),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Fleet Status", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -0.5)), Icon(Icons.local_shipping_rounded, color: Colors.grey)])),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: _trucks.isEmpty ? [const Padding(padding: EdgeInsets.all(60), child: Center(child: Text("Scanning for active units...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500))))] : _trucks.where((t) => t['isOnline'] == true).map((truck) => _buildDetailedTruckCard(truck)).toList())),
        const SizedBox(height: 24),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFFF0F0F0))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Fleet Management Guide", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))), const SizedBox(height: 20), _buildGuideRow("Tap 'History' to view detailed audit trails"), _buildGuideRow("Use 'Compare Path' for AI-optimized routes"), _buildGuideRow("Real-time heatmaps indicate collection speed")]))),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildGuideRow(String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("• ", style: TextStyle(color: Color(0xFF757575), fontWeight: FontWeight.w900)), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF757575), fontWeight: FontWeight.w500)))]));
  }

  double _calculateDistance(List<Map<dynamic, dynamic>> points) {
    double totalDistance = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i]; final p2 = points[i + 1];
      totalDistance += _getDistance((p1['latitude'] ?? 0).toDouble(), (p1['longitude'] ?? 0).toDouble(), (p2['latitude'] ?? 0).toDouble(), (p2['longitude'] ?? 0).toDouble());
    }
    return totalDistance;
  }

  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295; var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  int _countStops(List<Map<dynamic, dynamic>> points) {
    int stops = 0; int clusterStart = -1;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i]; final p2 = points[i + 1];
      double dist = _getDistance((p1['latitude'] ?? 0).toDouble(), (p1['longitude'] ?? 0).toDouble(), (p2['latitude'] ?? 0).toDouble(), (p2['longitude'] ?? 0).toDouble());
      if (dist < 0.01) {
        if (clusterStart == -1) clusterStart = (p1['timestamp'] ?? 0);
        int duration = (p2['timestamp'] ?? 0) - clusterStart;
        if (duration > 45000) { stops++; clusterStart = -1; }
      } else { clusterStart = -1; }
    }
    return stops;
  }

  Widget _buildDetailedTruckCard(Map<dynamic, dynamic> truck) {
    String internalId = (truck['internal_id'] ?? truck['truck_id'] ?? "GT-001").toString();
    String id = (truck['truck_id'] ?? internalId).toString();
    String status = (truck['status'] ?? "Idle").toString().toUpperCase();
    String driver = (truck['driver_name'] ?? truck['driverName'] ?? "Unknown Driver").toString();
    String location = (truck['purok'] ?? "Balintawak").toString();
    String speedStr = truck['speed']?.toString() ?? "0";
    double speedVal = double.tryParse(speedStr) ?? 0.0;
    String speed = "$speedStr km/h";
    List<Map<dynamic, dynamic>> historyPoints = [];
    final historyData = truck['route_history'];
    if (historyData is Map) { historyData.forEach((k, v) => historyPoints.add(v as Map)); }
    else if (historyData is List) { for (var p in historyData) { if (p is Map) historyPoints.add(p); } }
    double distVal = historyPoints.isNotEmpty ? _calculateDistance(historyPoints) : (double.tryParse(truck['distance_covered']?.toString() ?? "0.0") ?? 0.0);
    String distance = "${distVal.toStringAsFixed(1)} km";
    String fuel = "${(distVal / 5.0).toStringAsFixed(1)} L";
    String stops = historyPoints.isNotEmpty ? _countStops(historyPoints).toString() : (truck['stops_made']?.toString() ?? "0");
    String eta;
    if (truck['eta_minutes'] != null) { eta = "${truck['eta_minutes']} mins"; }
    else { List<double> recentSpeeds = historyPoints.reversed.take(50).map((p) => (p['speed'] as num? ?? 0.0).toDouble()).toList(); if (recentSpeeds.isEmpty) recentSpeeds = [speedVal > 0 ? speedVal : 25.0]; double estEta = PredictionEngine.estimateArrivalTime(distVal, recentSpeeds); eta = "${estEta.toStringAsFixed(0)} mins"; }
    String lastUpdate = (truck['last_update'] ?? "Just now").toString();
    bool isOffline = false;
    if (truck['timestamp'] != null) { final int ts = (truck['timestamp'] as int); final int now = DateTime.now().millisecondsSinceEpoch; if (now - ts > 120000) { isOffline = true; status = "OFFLINE"; } }
    bool isFull = truck['is_full'] == true || status == 'FULL';
    if (isFull) status = "FULL";
    bool isCompared = kIsWeb ? _webOptimizedPixels.containsKey(internalId) : _truckOptimizedPaths.containsKey(internalId);
    bool isHistoryVisible = kIsWeb ? _webHeatmapData.containsKey(internalId) : _truckHeatmapPaths.containsKey(internalId);
    bool isSelected = _selectedTruckId == internalId;
    Color statusColor = isOffline ? Colors.grey : (status == 'FULL' ? const Color(0xFFFF1744) : (status == 'ACTIVE' ? const Color(0xFF4CAF50) : const Color(0xFFFFAB00)));

    return GestureDetector(
      onTap: () => _selectTruck(internalId, (truck['latitude'] ?? 13.9402).toDouble(), (truck['longitude'] ?? 121.1638).toDouble()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: isSelected ? Colors.blue.withAlpha(40) : Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))], border: Border.all(color: isSelected ? Colors.blue : const Color(0xFFF5F5F5), width: isSelected ? 2 : 1)),
        child: Column(
          children: [
            Row(children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.local_shipping_rounded, color: Color(0xFF1976D2), size: 28)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(id, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))), Text(lastUpdate, style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13, fontWeight: FontWeight.w500))])), Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: statusColor.withAlpha(30), borderRadius: BorderRadius.circular(12)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w900)))]),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildInfoItem(Icons.location_on_rounded, const Color(0xFFFF1744), "Location", location), _buildInfoItem(Icons.refresh_rounded, const Color(0xFF03A9F4), "Speed", speed), _buildInfoItem(Icons.person_rounded, const Color(0xFF1976D2), "Driver", driver)]),
            const SizedBox(height: 24),
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStatItem(Icons.local_shipping_outlined, "DISTANCE", distance, const Color(0xFF2E7D32)), _buildStatItem(Icons.local_gas_station_outlined, "FUEL", fuel, const Color(0xFFD32F2F)), _buildStatItem(Icons.radio_button_checked_rounded, "STOPS", stops, const Color(0xFFD32F2F))])),
            const SizedBox(height: 24),
            Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () => _toggleHeatmap(internalId), icon: Icon(isHistoryVisible ? Icons.visibility_off_rounded : Icons.location_on_rounded, size: 20), label: Text(isHistoryVisible ? "HIDE HISTORY" : "HISTORY", style: const TextStyle(fontWeight: FontWeight.w900)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF0F4F8), foregroundColor: const Color(0xFF1A1A1A), elevation: 0, minimumSize: const Size(0, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))), const SizedBox(width: 12), Expanded(child: ElevatedButton.icon(onPressed: () => _toggleOptimizedRoute(internalId), icon: Icon(isCompared ? Icons.visibility_off_rounded : Icons.navigation_rounded, size: 20), label: Text(isCompared ? "HIDE PATH" : "COMPARE PATH", style: const TextStyle(fontWeight: FontWeight.w900)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, elevation: 0, minimumSize: const Size(0, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))))]),
            const SizedBox(height: 20),
            Row(children: [const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFFBDBDBD)), const SizedBox(width: 4), const Text("Last Update:", style: TextStyle(fontSize: 12, color: Color(0xFFBDBDBD), fontWeight: FontWeight.w500)), const Spacer(), Text("ETA: $eta", style: const TextStyle(fontSize: 12, color: Color(0xFF1E88E5), fontWeight: FontWeight.w900))]),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, Color color, String label, String value) {
    return Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD), fontWeight: FontWeight.w600))]), const SizedBox(height: 4), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)))]));
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Column(children: [Row(children: [Icon(icon, size: 12, color: const Color(0xFF757575)), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF757575), fontWeight: FontWeight.w800))]), const SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color))]);
  }
}

class WebPathPainter extends CustomPainter {
  final Map<String, List<Map<String, dynamic>>> heatmapData;
  final Map<String, List<Offset>> heatmapPixels;
  final Map<String, List<Offset>> optimizedPixels;

  WebPathPainter({required this.heatmapData, required this.heatmapPixels, required this.optimizedPixels});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Heatmap (Strava Line)
    heatmapPixels.forEach((truckId, pixels) {
      if (pixels.length < 2) return;
      final data = heatmapData[truckId];
      if (data == null) return;

      for (int i = 0; i < pixels.length - 1; i++) {
        final double speed = data[i + 1]['speed'] ?? 0;
        final paint = Paint()
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..color = speed < 5 ? Colors.red : (speed < 15 ? Colors.yellow : Colors.green);
        
        canvas.drawLine(pixels[i], pixels[i+1], paint);
      }
    });

    // 2. Draw Optimized Path
    optimizedPixels.forEach((truckId, pixels) {
      if (pixels.length < 2) return;
      final paint = Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(pixels[0].dx, pixels[0].dy);
      for (int i = 1; i < pixels.length; i++) {
        path.lineTo(pixels[i].dx, pixels[i].dy);
      }
      canvas.drawPath(path, paint);
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
