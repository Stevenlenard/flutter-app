import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../utils/prediction_engine.dart';

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
          textColor: Colors.blue.value,
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
            initialChildSize: 0.45,
            minChildSize: 0.18,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: const [0.18, 0.45, 0.95],
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
                  Text("Track Fleet", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                  Text("Active GPS signal connected", style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontWeight: FontWeight.w600)),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Fleet Status", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
              Icon(Icons.keyboard_arrow_up_rounded, color: Colors.grey),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: _trucks.isEmpty
              ? [const Padding(padding: EdgeInsets.all(60), child: Center(child: Text("Scanning for active units...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500))))]
              : _trucks.map((truck) => _buildOrganizedTruckCard(truck)).toList(),
          ),
        ),
        _buildFleetGuide(),
        const SizedBox(height: 150),
      ],
    );
  }

  Widget _buildOrganizedTruckCard(Map<dynamic, dynamic> truck) {
    final String truckId = (truck['id'] ?? 'unknown').toString();
    final bool isComparing = _comparingTrucks.contains(truckId);
    final String status = (truck['status'] ?? 'IDLE').toString().toUpperCase();
    final Color statusColor = status == 'ACTIVE' ? const Color(0xFF00C853) : const Color(0xFFFF1744);
    
    // Calculate ETA (Aligned with Kotlin Arrival Estimates)
    String eta;
    if (truck['eta_minutes'] != null) {
      eta = "${truck['eta_minutes']} mins";
    } else {
      double speedVal = double.tryParse(truck['speed']?.toString() ?? '0') ?? 25.0;
      double estEta = PredictionEngine.estimateArrivalTime(2.5, [speedVal > 0 ? speedVal : 25.0]);
      eta = "${estEta.toStringAsFixed(0)} mins";
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 12, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFF8F9FA), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.local_shipping_outlined, color: Color(0xFF00897B), size: 26)),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((truck['truck_id'] ?? 'GT-001').toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Color(0xFF1A1A1A))),
                Text((truck['driver_name'] ?? "Assigned: Steve E.").toString(), style: const TextStyle(color: Color(0xFF757575), fontSize: 12, fontWeight: FontWeight.w500)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(12)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900))),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(eta, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                  const Text("ETA", style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildRefinedInfo(Icons.my_location_rounded, "Current Location", (truck['location'] ?? "Balintawak").toString()),
              _buildRefinedInfo(Icons.speed_rounded, "Fleet Velocity", "${truck['speed'] ?? 0} km/h"),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem("Distance", "${truck['distance'] ?? '3.4'}km"),
                Container(width: 1, height: 20, color: Colors.black12),
                _buildStatItem("Fuel Level", "${truck['fuel'] ?? '0.7'}L"),
                Container(width: 1, height: 20, color: Colors.black12),
                _buildStatItem("Stops", "${truck['stops'] ?? '2'}"),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildSecondaryButton("HISTORY", Icons.history_rounded, () {})),
              const SizedBox(width: 12),
              Expanded(child: _buildPrimaryButton(isComparing ? "HIDE PATH" : "COMPARE PATH", Icons.insights_rounded, isComparing ? const Color(0xFFFFA726) : const Color(0xFF00BFA5), () {
                setState(() => isComparing ? _comparingTrucks.remove(truckId) : _comparingTrucks.add(truckId));
              })),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRefinedInfo(IconData icon, String label, String val) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: const Color(0xFF00897B)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w700))]),
      const SizedBox(height: 4),
      Text(val, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1A1A))),
    ]);
  }

  Widget _buildStatItem(String label, String val) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(val, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF1A1A1A))),
    ]);
  }

  Widget _buildSecondaryButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5F5F5), foregroundColor: const Color(0xFF1A1A1A), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
  }

  Widget _buildPrimaryButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 6, shadowColor: color.withAlpha(100), padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
  }

  Widget _buildFleetGuide() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Management Insights", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A))),
          SizedBox(height: 20),
          _GuideRow(Icons.check_circle_outline_rounded, "View audit trails in 'History'"),
          SizedBox(height: 12),
          _GuideRow(Icons.check_circle_outline_rounded, "Use AI Path comparison for optimization"),
          SizedBox(height: 12),
          _GuideRow(Icons.check_circle_outline_rounded, "Real-time heatmaps indicate fleet load"),
        ],
      ),
    );
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
