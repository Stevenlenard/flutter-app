import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../utils/app_theme.dart';
import '../utils/session_manager.dart';

class ResidentComplaintsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;
  const ResidentComplaintsScreen({super.key, this.isEmbedded = false, this.onBack});

  @override
  State<ResidentComplaintsScreen> createState() => _ResidentComplaintsScreenState();
}

class _ResidentComplaintsScreenState extends State<ResidentComplaintsScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _complaints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchComplaints();
  }

  Future<void> _fetchComplaints() async {
    setState(() => _isLoading = true);
    final user = await SessionManager.getUser();
    try {
      final response = await _apiService.getComplaints();
      if (response.data['success'] == true) {
        final List all = response.data['data'];
        setState(() {
          _complaints = all.where((c) => c['user_id'].toString() == user?.userId.toString()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int pending = _complaints.where((c) => c['status'].toString().toLowerCase() == 'pending').length;
    int inProgress = _complaints.where((c) => c['status'].toString().toLowerCase() == 'in_progress').length;
    int resolved = _complaints.where((c) => c['status'].toString().toLowerCase() == 'resolved').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // 🏛️ ORGANIZED HEADER
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
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
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("My Complaints", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                    Text("Track your submitted reports", style: TextStyle(fontSize: 11, color: Color(0xFF757575), fontWeight: FontWeight.w600)),
                  ])),
                  const Icon(Icons.history_edu_rounded, color: Color(0xFFBDBDBD), size: 26),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // 📊 BALANCED SUMMARY CARDS
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: Row(
                        children: [
                          _buildSummaryCard("Pending", pending.toString(), const Color(0xFFE0F2F1), const Color(0xFF00796B), Icons.hourglass_empty_rounded),
                          const SizedBox(width: 10),
                          _buildSummaryCard("Active", inProgress.toString(), const Color(0xFFE3F2FD), const Color(0xFF1976D2), Icons.bolt_rounded),
                          const SizedBox(width: 10),
                          _buildSummaryCard("Solved", resolved.toString(), const Color(0xFFE8F5E9), const Color(0xFF2E7D32), Icons.verified_rounded),
                        ],
                      ),
                    ),

                    // ➕ PRO ACTION BUTTON
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.pushNamed(context, '/file_complaint');
                          _fetchComplaints(); // Refresh from database after returning
                        },
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                        label: const Text("New Complaint", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          minimumSize: const Size(double.infinity, 64),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 8,
                          shadowColor: const Color(0xFF00897B).withAlpha(100),
                        ),
                      ),
                    ),

                    // 📋 REFINED COMPLAINTS LIST
                    if (_isLoading)
                      const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator(color: Color(0xFF00897B)))
                    else if (_complaints.isEmpty)
                      _buildEmptyState()
                    else
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(children: _complaints.map((c) => _buildOrganizedComplaintItem(c)).toList()),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, String count, Color bgColor, Color textColor, IconData icon) {
    return Expanded(
      child: Container(
        height: 110,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(height: 6),
            Text(count, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -1)),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizedComplaintItem(dynamic complaint) {
    String status = (complaint['status'] ?? 'PENDING').toString().toUpperCase();
    Color statusColor = status == 'PENDING' ? Colors.orange : (status == 'RESOLVED' ? Colors.green : Colors.blue);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 12, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFF8F9FA), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(complaint['category'] ?? "General", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1A1A1A))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 12),
          Text(complaint['description'] ?? "", style: const TextStyle(color: Color(0xFF616161), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          Row(children: [const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.black26), const SizedBox(width: 8), Text(complaint['created_at']?.toString().split('T')[0] ?? "2026-06-27", style: const TextStyle(color: Colors.black26, fontSize: 11, fontWeight: FontWeight.w800))]),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(64),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFFF5F5F5), shape: BoxShape.circle), child: const Icon(Icons.assignment_turned_in_rounded, size: 56, color: Colors.black12)),
        const SizedBox(height: 24),
        const Text("Clear History", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        const Text("All your system complaints will appear here once submitted.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF757575), fontSize: 13, height: 1.4)),
      ]),
    );
  }
}
