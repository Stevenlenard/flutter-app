import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../utils/app_theme.dart';

class DriverTrackTruckScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const DriverTrackTruckScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<DriverTrackTruckScreen> createState() => _DriverTrackTruckScreenState();
}

class _DriverTrackTruckScreenState extends State<DriverTrackTruckScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  MapboxMap? mapboxMap;
  List<Map<dynamic, dynamic>> _trucks = [];
  
  PointAnnotationManager? _pointAnnotationManager;

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
          list.add({...value as Map, 'id': key.toString()});
        });
        if (mounted) {
          setState(() => _trucks = list);
          _updateTruckMarkers();
        }
      }
    });
  }

  void _onMapCreated(MapboxMap map) {
    mapboxMap = map;
  }

  void _onStyleLoaded(dynamic data) {
    mapboxMap?.annotations.createPointAnnotationManager().then((manager) {
      _pointAnnotationManager = manager;
      _updateTruckMarkers();
    });
  }

  void _updateTruckMarkers() {
    if (_pointAnnotationManager == null || _trucks.isEmpty) return;
    _pointAnnotationManager?.deleteAll();
    for (var truck in _trucks) {
      final double lat = (truck['latitude'] ?? 13.9402).toDouble();
      final double lng = (truck['longitude'] ?? 121.1638).toDouble();
      final String id = (truck['truck_id'] ?? "GT-001").toString();
      _pointAnnotationManager?.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(lng, lat)),
          textField: id,
          textOffset: [0, 2],
          textColor: Colors.blue.toARGB32(),
          iconImage: "truck-15",
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        );
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
                  viewport: CameraViewportState(
                    center: Point(coordinates: Position(121.1638, 13.9402)),
                    zoom: 14.0,
                  ),
                ),
              ),
              _buildHeader(),
            ],
          ),
        ),
        Container(
          width: 400,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 20, offset: const Offset(-5, 0))],
          ),
          child: _buildFleetStatusContent(null),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Positioned.fill(
          child: MapWidget(
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            viewport: CameraViewportState(
              center: Point(coordinates: Position(121.1638, 13.9402)),
              zoom: 14.0,
            ),
          ),
        ),
        _buildHeader(),
        Positioned.fill(
          child: DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.15,
            maxChildSize: 0.6,
            snap: true,
            snapSizes: const [0.15, 0.25, 0.6],
            builder: (context, scrollController) {
              return PointerInterceptor(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 25, spreadRadius: 5, offset: const Offset(0, -5))],
                  ),
                  child: _buildFleetStatusContent(scrollController, isMobile: true),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
        child: SafeArea(
          child: Row(
            children: [
              if (!widget.isEmbedded || widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1A1A), size: 20),
                  onPressed: () {
                    if (widget.onBack != null) {
                      widget.onBack!();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Fleet Tracker", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                  Text("Barangay Balintawak Overview", style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFleetStatusContent(ScrollController? scrollController, {bool isMobile = false}) {
    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.zero,
      children: [
        if (isMobile) const SizedBox(height: 12),
        if (isMobile)
          Center(
            child: Container(
              width: 60,
              height: 8,
              decoration: BoxDecoration(color: const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(10)),
            ),
          ),
        const SizedBox(height: 32),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text("Fleet Map Guide", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            "View live locations of all trucks within the barangay. This helps coordinate collection coverage and avoid route overlaps.",
            style: TextStyle(fontSize: 13, color: Color(0xFF757575), height: 1.5, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 32),
        _buildFleetStatusSummary(),
        const SizedBox(height: 150),
      ],
    );
  }

  Widget _buildFleetStatusSummary() {
    int active = _trucks.where((t) => (t['status'] ?? "").toString().toUpperCase() == "ACTIVE").length;
    int idle = _trucks.where((t) => (t['status'] ?? "").toString().toUpperCase() == "IDLE" || (t['status'] ?? "").toString().toUpperCase() == "OFFLINE").length;
    int full = _trucks.where((t) => (t['status'] ?? "").toString().toUpperCase() == "FULL").length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(32)),
        child: Column(
          children: [
            _buildSummaryRow(Icons.local_shipping_rounded, "Active Units", "$active", const Color(0xFF00C853)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.black12)),
            _buildSummaryRow(Icons.pause_circle_outline_rounded, "Idle / Offline", "$idle", const Color(0xFF9E9E9E)),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.black12)),
            _buildSummaryRow(Icons.warning_amber_rounded, "Capacity Full", "$full", const Color(0xFFFF1744)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String val, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 16),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF757575))),
        const Spacer(),
        Text(val, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
      ],
    );
  }
}
