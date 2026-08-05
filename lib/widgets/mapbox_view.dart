import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
import 'package:firebase_database/firebase_database.dart';

class MapboxView extends StatefulWidget {
  final String mode; // 'dashboard' or 'full'
  final String? selectedTruckId;
  final VoidCallback? onTap;

  const MapboxView({super.key, required this.mode, this.selectedTruckId, this.onTap});

  @override
  State<MapboxView> createState() => _MapboxViewState();
}

class _MapboxViewState extends State<MapboxView> {
  PointAnnotationManager? _pointAnnotationManager;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final Map<String, PointAnnotation> _truckAnnotations = {};

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MapWidget(
        key: const ValueKey("mapbox_map"),
        onMapCreated: _onMapCreated,
        viewport: CameraViewportState(
          center: Point(coordinates: Position(121.1638, 13.9402)),
          zoom: widget.mode == 'dashboard' ? 12.0 : 14.0,
        ),
      ),
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    _setupFirebaseSync();
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
    if (_pointAnnotationManager == null) return;

    for (var entry in trucksData.entries) {
      final id = entry.key.toString();
      final data = entry.value as Map<dynamic, dynamic>;
      
      final lat = (data['latitude'] ?? 0.0).toDouble();
      final lng = (data['longitude'] ?? 0.0).toDouble();
      final status = (data['status'] ?? 'active').toString().toUpperCase();
      final driverName = data['driver_name'] ?? 'Unknown';

      if (lat == 0.0 || lng == 0.0) continue;

      final point = Point(coordinates: Position(lng, lat));

      if (_truckAnnotations.containsKey(id)) {
        final annotation = _truckAnnotations[id]!;
        annotation.geometry = point;
        annotation.textField = "$driverName\n($status)";
        _pointAnnotationManager!.update(annotation);
      } else {
        final annotation = await _pointAnnotationManager!.create(
          PointAnnotationOptions(
            geometry: point,
            textField: "$driverName\n($status)",
            textSize: 10,
            textColor: Colors.blue.value,
            iconImage: "marker-15",
          ),
        );
        _truckAnnotations[id] = annotation;
      }
    }
  }
}
