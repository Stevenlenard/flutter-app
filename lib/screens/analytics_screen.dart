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
          if (value is Map) {
            total++;
            if (value['route_status'] == 'COMPLETED' || value['status'] == 'COMPLETED') completed++;
          }
        });
        if (mounted) setState(() { _totalRoutes = total; _completedRoutes = completed; _coveragePercent = total > 0 ? (completed / total) * 100 : 0.0; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      bool isDesktop = constraints.maxWidth >= 1024;
      bool isMobile = constraints.maxWidth < 600;

      return Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: widget.isEmbedded ? null : AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text("Analytics Overview", style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w900)),
          leading: widget.onBack != null ? IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20), onPressed: widget.onBack) : null,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Metrics Row
              Row(
                children: [
                  Expanded(child: _buildMetricCard("Routes Done", "$_completedRoutes/$_totalRoutes", const Color(0xFF4CAF50), isMobile)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard("Coverage", "${_coveragePercent.toInt()}%", const Color(0xFF2196F3), isMobile)),
                ],
              ),
              const SizedBox(height: 32),

              // Charts Layout
              if (isDesktop) 
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 1, child: _buildChartSection("Truck Status Distribution", _buildTruckDonutChart())),
                    const SizedBox(width: 24),
                    Expanded(flex: 1, child: _buildChartSection("Purok Visit Frequency", _buildPurokBarChart())),
                  ],
                )
              else 
                Column(
                  children: [
                    _buildChartSection("Truck Status Distribution", _buildTruckDonutChart()),
                    _buildChartSection("Purok Visit Frequency", _buildPurokBarChart()),
                  ],
                ),
              const SizedBox(height: 100),
            ],
          ),
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
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2C3E50))),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: chart,
          ),
        ],
      ),
    );
  }

  Widget _buildTruckDonutChart() {
    if (_truckStatusData['Active'] == 0 && _truckStatusData['Idle'] == 0) {
       return const Center(child: Text("No truck data available", style: TextStyle(color: Colors.grey, fontSize: 13)));
    }
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
