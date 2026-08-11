import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../api/api_service.dart';

class ComplaintsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const ComplaintsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final ApiService _apiService = ApiService();
  List<dynamic> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchComplaints();
  }

  Future<void> _fetchComplaints() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.getComplaints();
      if (response.data['success'] == true) {
        setState(() { _complaints = response.data['data']; _isLoading = false; });
      }
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Resolve Radar", style: TextStyle(fontWeight: FontWeight.bold)),
        leading: widget.onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack) : null,
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: "RESIDENTS"), Tab(text: "DRIVERS")]),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(
        controller: _tabController,
        children: [_buildList(true), _buildList(false)],
      ),
    );
  }

  Widget _buildList(bool isResident) {
    final list = _complaints.where((c) => (c['role'] ?? 'resident') == (isResident ? 'resident' : 'driver')).toList();
    if (list.isEmpty) return const Center(child: Text("No items found"));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) => _buildCard(list[i]),
    );
  }

  Widget _buildCard(dynamic c) {
    String status = (c['status'] ?? 'PENDING').toString().toUpperCase();
    Color statusColor = status == 'RESOLVED' ? Colors.green : Colors.orange;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        title: Text(c['category'] ?? "General", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(c['description'] ?? ""),
        trailing: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold))),
      ),
    );
  }
}
