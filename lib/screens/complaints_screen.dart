import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
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
  StreamSubscription? _driverIssuesSubscription;

  List<dynamic> _residentComplaints = [];
  List<dynamic> _driverIssues = [];
  List<dynamic> _filteredResidentComplaints = [];
  List<dynamic> _filteredDriverIssues = [];
  
  final Set<dynamic> _selectedItems = {};
  bool _isLoading = true;
  bool _showArchived = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          _selectedItems.clear();
        });
      }
    });
    _fetchResidentComplaints();
    _setupDriverIssuesListener();
  }

  @override
  void dispose() {
    _driverIssuesSubscription?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchResidentComplaints() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Trigger a silent schema check/update
      await _apiService.triggerSchemaDebug();

      final response = await _apiService.getComplaints();
      final List complaints = response.data['data'] ?? [];
      if (mounted) {
        setState(() {
          _residentComplaints = complaints;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _setupDriverIssuesListener() {
    _driverIssuesSubscription = _database.ref('notifications').onValue.listen((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        if (mounted) setState(() => _driverIssues = []);
        return;
      }

      final Map data = event.snapshot.value as Map;
      final List issues = [];
      data.forEach((key, value) {
        if (value is Map && value['type'] == 'DRIVER_ISSUE') {
          issues.add({...Map<String, dynamic>.from(value), 'id': key});
        }
      });

      issues.sort((a, b) => (b['timestamp'] ?? "").toString().compareTo((a['timestamp'] ?? "").toString()));

      if (mounted) {
        setState(() {
          _driverIssues = issues;
          _applyFilter();
        });
      }
    });
  }

  void _applyFilter() {
    final String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredResidentComplaints = _residentComplaints.where((c) {
        // MORE RESILIENT FILTERING LOGIC
        final rawArchived = c['is_archived'];
        final bool isArchivedInDb = rawArchived == 1 || rawArchived == "1" || rawArchived == true;
        
        final rawDeleted = c['deleted_by_resident'];
        final bool isDeletedInDb = rawDeleted == 1 || rawDeleted == "1" || rawDeleted == true;

        if (!_showArchived) {
          // Main view: hide anything archived or deleted
          if (isArchivedInDb || isDeletedInDb) return false;
        } else {
          // Archive view: show ONLY archived items, and hide deleted ones
          if (!isArchivedInDb || isDeletedInDb) return false;
        }

        final name = (c['full_name'] ?? "").toString().toLowerCase();
        final purok = (c['purok'] ?? "").toString().toLowerCase();
        final cat = (c['category'] ?? "").toString().toLowerCase();
        return name.contains(query) || purok.contains(query) || cat.contains(query);
      }).toList();

      _filteredDriverIssues = _driverIssues.where((i) {
        final bool isArchivedInFb = i['status'] == 'ARCHIVED';
        
        if (!_showArchived) {
          if (isArchivedInFb) return false;
        } else {
          if (!isArchivedInFb) return false;
        }

        final name = (i['driver_name'] ?? "").toString().toLowerCase();
        final location = (i['location'] ?? "").toString().toLowerCase();
        final title = (i['title'] ?? "").toString().toLowerCase();
        return name.contains(query) || location.contains(query) || title.contains(query);
      }).toList();
    });
  }

  Future<void> _bulkAction(String action) async {
    if (_selectedItems.isEmpty) return;

    final String message = action == 'delete' ? "delete" : (action == 'archive' ? "archive" : "restore");
    final bool isDangerous = action == 'delete';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDangerous ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                color: isDangerous ? Colors.red : Colors.blue,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                "${message[0].toUpperCase()}${message.substring(1)} Items?",
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Text(
                "Are you sure you want to $message ${_selectedItems.length} items? This action cannot be easily undone.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDangerous ? Colors.red : Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        message.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      if (_tabController.index == 0) {
        // Resident Complaints
        if (action == 'delete') {
          await _apiService.bulkDeleteComplaints(_selectedItems.map((e) => int.parse(e.toString())).toList());
        } else {
          for (var id in _selectedItems) {
            await _apiService.archiveComplaint(int.parse(id.toString()), action == 'archive');
          }
        }
        await _fetchResidentComplaints();
      } else {
        // Driver Issues (Firebase)
        for (var id in _selectedItems) {
          if (action == 'delete') {
            await _database.ref('notifications').child(id.toString()).remove();
          } else {
            await _database.ref('notifications').child(id.toString()).update({
              'status': action == 'archive' ? 'ARCHIVED' : 'PENDING'
            });
          }
        }
      }
      if (mounted) {
        setState(() {
          _selectedItems.clear();
          _isLoading = false;
        });
        _showSuccessModal("Items ${message}d successfully");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildProfessionalHeader(),
            _buildActionBar(),
            _buildTabBar(),
            Expanded(
              child: _isLoading && _residentComplaints.isEmpty && _driverIssues.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFA5)))
                  : _buildTableView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfessionalHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.onBack != null)
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Resolve Radar", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                  Text("Navigating Complaints, Guiding Solutions", style: TextStyle(fontSize: 12, color: Color(0xFF757575))),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.file_download_outlined, color: Color(0xFFC62828), size: 28),
                onPressed: _exportComplaints,
                tooltip: "Export Complaints Report",
              ),
              const SizedBox(width: 12),
              _buildArchiveToggle(),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              _showArchived ? "Archived Complaints and Issues" : "Reported Complaints and Issues",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Serif'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportComplaints() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.exportComplaintsReport();
      if (response.data['success'] == true && response.data['url'] != null) {
        final Uri uri = Uri.parse(response.data['url']);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildArchiveToggle() {
    return InkWell(
      onTap: () => setState(() {
        _showArchived = !_showArchived;
        _applyFilter();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _showArchived ? const Color(0xFFE0F2F1) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _showArchived ? const Color(0xFF00BFA5) : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(_showArchived ? Icons.archive : Icons.archive_outlined, size: 18, color: _showArchived ? const Color(0xFF00BFA5) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              _showArchived ? "Viewing Archive" : "View Archive",
              style: TextStyle(fontWeight: FontWeight.bold, color: _showArchived ? const Color(0xFF00BFA5) : Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(color: Color(0xFFF8F9FA)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => _applyFilter(),
              decoration: InputDecoration(
                hintText: "Search by Name or Purok...",
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (_selectedItems.isNotEmpty) ...[
            _buildActionButton("Delete", Icons.delete_outline, Colors.red, () => _bulkAction('delete')),
            const SizedBox(width: 8),
            _buildActionButton(
              _showArchived ? "Restore" : "Archive",
              _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              const Color(0xFF1976D2),
              () => _bulkAction(_showArchived ? 'restore' : 'archive'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: "RESIDENT COMPLAINTS"),
          Tab(text: "DRIVER ISSUES"),
        ],
        labelColor: Colors.black,
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color(0xFFC62828), // Dark red line like in reference
        indicatorWeight: 4,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1),
      ),
    );
  }

  Widget _buildTableView() {
    final List<dynamic> items = _tabController.index == 0 ? _filteredResidentComplaints : _filteredDriverIssues;
    final bool isResident = _tabController.index == 0;

    if (items.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_showArchived ? "No archived items found" : "No active complaints found", style: const TextStyle(color: Colors.grey)),
        ],
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(const Color(0xFF424242)),
          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          columnSpacing: 24,
          dataRowHeight: 64,
          columns: [
            const DataColumn(label: Text("Date")),
            DataColumn(label: Text(isResident ? "Resident" : "Driver")),
            const DataColumn(label: Text("Category")),
            const DataColumn(label: Text("Complaint Details")),
            const DataColumn(label: Text("Status")),
            const DataColumn(label: Text("Action Taken")),
          ],
          rows: items.map((item) => _buildDataRow(item, isResident)).toList(),
        ),
      ),
    );
  }

  DataRow _buildDataRow(dynamic item, bool isResident) {
    final id = item['id'];
    final bool isSelected = _selectedItems.contains(id);
    
    String date = (item['created_at'] ?? item['timestamp'] ?? "").toString();
    if (date.contains('T')) date = date.split('T')[0];
    else if (date.contains(' ')) date = date.split(' ')[0];

    String name = isResident ? (item['full_name'] ?? "N/A") : (item['driver_name'] ?? "N/A");
    String cat = isResident ? (item['category'] ?? "General") : (item['title']?.toString().replaceAll("New Driver Issue: ", "") ?? "Vehicle");
    String details = isResident ? (item['description'] ?? "") : (item['message'] ?? "");
    String status = (item['status'] ?? 'PENDING').toString().toUpperCase();
    String action = item['admin_response'] ?? "-";

    return DataRow(
      selected: isSelected,
      onSelectChanged: (v) {
        setState(() {
          if (v == true) _selectedItems.add(id);
          else _selectedItems.remove(id);
        });
      },
      cells: [
        DataCell(
          GestureDetector(
            onTap: () => _showActionModal(item, isResident),
            child: Text(date, style: const TextStyle(fontSize: 13)),
          ),
        ),
        DataCell(
          GestureDetector(
            onTap: () => _showActionModal(item, isResident),
            child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
        DataCell(
          GestureDetector(
            onTap: () => _showActionModal(item, isResident),
            child: Text(cat, style: const TextStyle(fontSize: 13)),
          ),
        ),
        DataCell(
          GestureDetector(
            onTap: () => _showActionModal(item, isResident),
            child: SizedBox(width: 250, child: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          ),
        ),
        DataCell(
          GestureDetector(
            onTap: () => _showActionModal(item, isResident),
            child: _buildStatusBadge(status),
          ),
        ),
        DataCell(
          InkWell(
            onTap: () => _showActionModal(item, isResident),
            child: Row(
              children: [
                Expanded(child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.blue))),
                const Icon(Icons.edit_outlined, size: 16, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.orange;
    if (status.contains('PROGRESS')) color = Colors.blue;
    else if (status.contains('RESOLVED') || status.contains('DONE')) color = Colors.green;
    else if (status.contains('ARCHIVED')) color = Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withAlpha(100))),
      child: Text(status.replaceAll('_', ' '), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _showActionModal(dynamic item, bool isResident) {
    String currentStatus = (item['status'] ?? 'PENDING').toString().toUpperCase().replaceAll(' ', '_');
    if (!['PENDING', 'IN_PROGRESS', 'RESOLVED'].contains(currentStatus)) currentStatus = 'PENDING';
    
    final TextEditingController responseController = TextEditingController(text: item['admin_response'] ?? "");
    String selectedStatus = currentStatus;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Manage Complaint", style: TextStyle(fontWeight: FontWeight.w900)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Update Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'PENDING', child: Text("Pending")),
                    DropdownMenuItem(value: 'IN_PROGRESS', child: Text("In Progress")),
                    DropdownMenuItem(value: 'RESOLVED', child: Text("Resolved")),
                  ],
                  onChanged: (v) => setModalState(() => selectedStatus = v!),
                ),
                const SizedBox(height: 24),
                const Text("Action Taken / Admin Response", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                TextField(
                  controller: responseController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: "Enter resolution steps or response...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                await _updateTicket(item['id'], selectedStatus, isResident, responseController.text.trim());
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("SAVE CHANGES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTicket(dynamic id, String status, bool isResident, String adminResponse) async {
    setState(() => _isLoading = true); // Added loading state for visual feedback
    try {
      if (isResident) {
        final response = await _apiService.updateComplaint(
          int.parse(id.toString()),
          status.toLowerCase(),
          adminResponse,
        );
        if (response.data['success'] != true) throw response.data['message'] ?? "Failed to update";

        // Try to find the correct complaint entry for notification
        final entry = _residentComplaints.firstWhere(
          (c) => c['id'].toString() == id.toString() || c['complaint_id'].toString() == id.toString(),
          orElse: () => null,
        );
        
        if (entry != null && entry['user_id'] != null) {
          final residentId = entry['user_id'];
          await _database.ref('notification_logs').push().set({
            'type': 'COMPLAINT_UPDATE',
            'title': 'Complaint Update',
            'message': 'Your complaint has been updated to $status.',
            'user_id': residentId,
            'isRead': false,
            'timestamp': ServerValue.timestamp,
          });
        }
        
        await _fetchResidentComplaints();
      } else {
        await _database.ref('notifications').child(id.toString()).update({
          'status': status,
          'admin_response': adminResponse,
          'resolved_at': status == 'RESOLVED' ? DateTime.now().toIso8601String() : null,
        });
      }
      if (mounted) {
        _showSuccessModal("Complaint updated successfully");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _showSuccessModal(String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
              const SizedBox(height: 24),
              const Text("Success!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("CLOSE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
