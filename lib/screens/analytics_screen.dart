import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const AnalyticsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();

  Map<String, double> _truckStatusData = {"Active": 0, "Full": 0, "Idle": 0};
  Map<String, double> _complaintStatusData = {"Pending": 0, "In Progress": 0, "Resolved": 0};
  String _selectedArea = "All Areas";
  DateTime _selectedDate = DateTime.now();
  
  int _totalRoutes = 0;
  int _completedRoutes = 0;
  double _coveragePercent = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchChartData();
  }

  void _fetchChartData() {
    _database.ref('truck_locations').onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map data = event.snapshot.value as Map;
        final Map<String, double> counts = {"Active": 0, "Idle": 0, "Full": 0};
        data.forEach((key, value) {
          String status = value['status']?.toString().toLowerCase() ?? 'idle';
          if (status == 'active') counts['Active'] = counts['Active']! + 1;
          else if (status == 'full') counts['Full'] = counts['Full']! + 1;
          else counts['Idle'] = counts['Idle']! + 1;
        });
        if (mounted) setState(() => _truckStatusData = counts);
      }
    });

    _apiService.getComplaints().then((response) {
      if (response.data['success'] == true) {
        final List complaints = response.data['data'];
        final Map<String, double> counts = {"Pending": 0, "In Progress": 0, "Resolved": 0};
        for (var c in complaints) {
          String status = c['status'].toString().toLowerCase().replaceAll('_', ' ');
          if (status == 'pending') counts['Pending'] = counts['Pending']! + 1;
          else if (status == 'in progress') counts['In Progress'] = counts['In Progress']! + 1;
          else if (status == 'resolved') counts['Resolved'] = counts['Resolved']! + 1;
        }
        if (mounted) setState(() => _complaintStatusData = counts);
      }
    });

    _database.ref('driver_routes').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final Map data = event.snapshot.value as Map;
        int total = 0; int completed = 0;
        data.forEach((key, value) {
          if (value is Map) {
            total++;
            if (value['route_status'] == 'COMPLETED' || value['status'] == 'COMPLETED') completed++;
          }
        });
        if (mounted) {
          setState(() {
            _totalRoutes = total;
            _completedRoutes = completed;
            _coveragePercent = total > 0 ? (completed / total) * 100 : 0.0;
          });
        }
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
                  Expanded(child: _buildMetricCard("Routes Done", "$_completedRoutes/$_totalRoutes", Icons.local_shipping_rounded, const Color(0xFF4CAF50))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard("Coverage", "${_coveragePercent.toInt()}%", Icons.map_rounded, const Color(0xFF2196F3))),
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

  Widget _buildMetricGrid(bool isMobile) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildMetricCard("Routes Done", "$_completedRoutes/$_totalRoutes", Icons.local_shipping_rounded, const Color(0xFF4CAF50)),
        _buildMetricCard("Coverage", "${_coveragePercent.toInt()}%", Icons.map_rounded, const Color(0xFF2196F3)),
        _buildMetricCard("Active Fleet", "${_truckStatusData['Active']?.toInt() ?? 0}", Icons.bolt_rounded, Colors.orange),
        _buildMetricCard("Issues", "${_complaintStatusData['Pending']?.toInt() ?? 0}", Icons.warning_rounded, Colors.red),
      ],
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          if (!widget.isEmbedded || widget.onBack != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF2C3E50), size: 20),
              onPressed: () {
                if (widget.onBack != null) widget.onBack!();
                else Navigator.pop(context);
              },
            ),
            const SizedBox(width: 8),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Analytics Overview", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                Text("Comprehensive system performance overview", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (!isMobile)
            ElevatedButton.icon(
              onPressed: () => _showExportDialog(context),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text("EXPORT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade100))),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _filterChip(Icons.location_on_rounded, _selectedArea, onTap: () => _showAreaSelection(context)),
          const SizedBox(width: 24),
          _filterChip(Icons.calendar_today_rounded, DateFormat('MMM dd, yyyy').format(_selectedDate), onTap: () => _showDatePicker(context)),
        ],
      ),
    );
  }

  Widget _filterChip(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF1F4F8), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF2C3E50)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF2C3E50))),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withAlpha(15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.w700)),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2C3E50))),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildPurokChartSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Purok Visit Frequency", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF2C3E50))),
          const SizedBox(height: 32),
          SizedBox(height: 300, child: _buildPurokBarChart()),
        ],
      ),
    );
  }

  Widget _buildInsightsSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("System Intelligence", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2C3E50))),
        const SizedBox(height: 20),
        _buildEfficiencyCard(),
        const SizedBox(height: 20),
        _buildInsightBlock("Waste Volume Prediction", "Tomorrow: High Volume Expected\nThis Week: Stable", const Color(0xFFE8EAF6), const Color(0xFF3F51B5)),
        const SizedBox(height: 12),
        _buildInsightBlock("Route Efficiency", "GT-001 optimal path maintained.\nFuel usage in normal range.", const Color(0xFFE8F5E9), const Color(0xFF4CAF50)),
      ],
    );
  }

  Widget _buildEfficiencyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _insightRow("Avg Collection Time", "1.2h"),
          _insightRow("Stops per Route", "14"),
          _insightRow("Distance Covered", "12.4km"),
          _insightRow("System Uptime", "99.9%", isSuccess: true),
        ],
      ),
    );
  }

  Widget _buildInsightBlock(String title, String content, Color bgColor, Color themeColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: themeColor, fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), height: 1.4)),
        ],
      ),
    );
  }

  Widget _insightRow(String label, String value, {bool isSuccess = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: isSuccess ? Colors.green : const Color(0xFF2C3E50))),
        ],
      ),
    );
  }

  Widget _buildTruckDonutChart() {
    if (_truckStatusData.values.every((v) => v == 0)) {
      return const Center(child: Text("No live data"));
    }
    return PieChart(
      PieChartData(
        sections: _truckStatusData.entries.map((e) {
          Color color = Colors.grey;
          if (e.key == "Active") color = Colors.green;
          if (e.key == "Full") color = Colors.pinkAccent;
          return PieChartSectionData(value: e.value, color: color, radius: 20, showTitle: false);
        }).toList(),
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  Widget _buildComplaintsDonutChart() {
    if (_complaintStatusData.values.every((v) => v == 0)) {
      return const Center(child: Text("No data"));
    }
    return PieChart(
      PieChartData(
        sections: _complaintStatusData.entries.map((e) {
          Color color = Colors.grey;
          if (e.key == "Pending") color = Colors.orange;
          if (e.key == "In Progress") color = Colors.blue;
          if (e.key == "Resolved") color = Colors.green;
          return PieChartSectionData(value: e.value, color: color, radius: 20, showTitle: false);
        }).toList(),
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  Widget _buildPurokBarChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 40,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                const areas = ["P1", "P2", "P3", "P4", "Riles", "Sentro", "ISID", "PARA", "RIV", "KAL", "HOME", "TANC"];
                if (value.toInt() >= 0 && value.toInt() < areas.length) {
                  return Text(areas[value.toInt()], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold));
                }
                return const Text("");
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          _barGroup(0, 11), _barGroup(1, 15), _barGroup(2, 8), _barGroup(3, 10), _barGroup(4, 32),
          _barGroup(5, 25), _barGroup(6, 12), _barGroup(7, 5), _barGroup(8, 18), _barGroup(9, 7),
          _barGroup(10, 22), _barGroup(11, 14),
        ],
      ),
    );
  }

  BarChartGroupData _barGroup(int x, double y) {
    return BarChartGroupData(x: x, barRods: [BarChartRodData(toY: y, color: const Color(0xFF2196F3), width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))]);
  }

  void _showAreaSelection(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select Area Filter", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF2C3E50))),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    "All Areas", "Purok 1", "Purok 2", "Purok 3", "Purok 4", "Dos Riles", "Sentro",
                    "San Isidro", "Paraiso", "Riverside", "Kalaw Street",
                    "Home Subdivision", "Tanco Road", "Brixton Area"
                  ].map((area) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(area, style: TextStyle(fontWeight: area == _selectedArea ? FontWeight.w900 : FontWeight.w600, color: area == _selectedArea ? const Color(0xFF00BFA5) : Colors.black87)),
                    trailing: area == _selectedArea ? const Icon(Icons.check_circle, color: Color(0xFF00BFA5)) : null,
                    onTap: () {
                      setState(() => _selectedArea = area);
                      Navigator.pop(context);
                    },
                  )).toList(),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDatePicker(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, color: Color(0xFF00BFA5), size: 48),
              const SizedBox(height: 24),
              const Text("Export Performance Reports", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF2C3E50))),
              const SizedBox(height: 12),
              const Text("Download detailed analytics for your records", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              _exportDropdown("Report Category", ["Full System Report", "Truck Performance", "Area Coverage"]),
              const SizedBox(height: 16),
              _exportDropdown("File Format", ["PDF Document (.pdf)", "Excel Spreadsheet (.xlsx)"]),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFA5),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text("DOWNLOAD REPORT", style: TextStyle(fontWeight: FontWeight.w900)),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportDropdown(String hint, List<String> items) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(hint, style: const TextStyle(fontSize: 14)),
          isExpanded: true,
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
          onChanged: (_) {},
        ),
      ),
    );
  }
}
