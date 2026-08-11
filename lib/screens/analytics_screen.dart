import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/responsive.dart';

class AnalyticsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const AnalyticsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  Map<String, double> _truckStatusData = {"Active": 0, "Idle": 0};
  int _totalRoutes = 0;
  int _completedRoutes = 0;
  double _coveragePercent = 0.0;
  StreamSubscription? _trucksSubscription;
  StreamSubscription? _routesSubscription;

  @override
  void initState() {
    super.initState();
    _fetchChartData();
  }

  @override
  void dispose() {
    _trucksSubscription?.cancel();
    _routesSubscription?.cancel();
    super.dispose();
  }

  void _fetchChartData() {
    _trucksSubscription = _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        final Map<String, double> counts = {"Active": 0, "Idle": 0};
        data.forEach((key, value) {
          String status = value['status']?.toString().toLowerCase() ?? 'idle';
          if (status == 'active') counts['Active'] = counts['Active']! + 1;
          else counts['Idle'] = counts['Idle']! + 1;
        });
        if (mounted) setState(() => _truckStatusData = counts);
      }
    });

    _routesSubscription = _database.ref('driver_routes').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        int total = 0; int completed = 0;
        data.forEach((key, value) {
          total++;
          if (value is Map && value['route_status'] == 'COMPLETED') completed++;
        });
        if (mounted) setState(() { _totalRoutes = total; _completedRoutes = completed; _coveragePercent = total > 0 ? (completed / total) * 100 : 0.0; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      bool isMobile = constraints.maxWidth < 600;
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7F9),
        appBar: AppBar(title: const Text("Analytics"), leading: widget.onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack) : null),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _buildMetricCard("Routes Done", "$_completedRoutes/$_totalRoutes", Colors.green, isMobile)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard("Coverage", "${_coveragePercent.toInt()}%", Colors.blue, isMobile)),
            ]),
            const SizedBox(height: 24),
            _buildChartSection("Truck Status", _buildTruckDonutChart()),
            const SizedBox(height: 24),
            _buildChartSection("Purok Frequency", _buildPurokBarChart()),
          ]),
        ),
      );
    });
  }

  Widget _buildMetricCard(String title, String value, Color color, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: Colors.grey, fontSize: isMobile ? 12 : 14)),
        Text(value, style: TextStyle(fontSize: isMobile ? 20 : 28, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _buildChartSection(String title, Widget chart) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 24),
        SizedBox(height: 200, child: chart),
      ]),
    );
  }

  Widget _buildTruckDonutChart() {
    return PieChart(PieChartData(sections: [
      PieChartSectionData(value: _truckStatusData['Active'] ?? 0, color: Colors.green, title: 'Active', radius: 40),
      PieChartSectionData(value: _truckStatusData['Idle'] ?? 0, color: Colors.grey, title: 'Idle', radius: 40),
    ], centerSpaceRadius: 40));
  }

  Widget _buildPurokBarChart() {
    return BarChart(BarChartData(
      barGroups: [
        BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 10, color: Colors.blue)]),
        BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 15, color: Colors.blue)]),
        BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 8, color: Colors.blue)]),
      ],
    ));
  }
}
