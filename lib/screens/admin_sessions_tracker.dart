import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminSessionsTrackerScreen extends StatefulWidget {
  const AdminSessionsTrackerScreen({super.key});

  @override
  State<AdminSessionsTrackerScreen> createState() =>
      _AdminSessionsTrackerScreenState();
}

class _AdminSessionsTrackerScreenState
    extends State<AdminSessionsTrackerScreen> {
  final _fs = FirebaseFirestore.instance;
  String _searchQuery = '';
  String _filter = 'all'; // 'all' | 'active' | 'completed' | 'cancelled'
  final Set<String> _expanded = {};

  static const _navy   = Color(0xFF1C2D5E);
  static const _bg     = Color(0xFFF0F4FF);
  static const _teal   = Color(0xFF4ECDC4);
  static const _orange = Color(0xFFF97316);
  static const _green  = Color(0xFF10B981);
  static const _red    = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Session Tracker',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search client name or plan…',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // Status filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                _chip('All', 'all'),
                const SizedBox(width: 8),
                _chip('Active', 'active'),
                const SizedBox(width: 8),
                _chip('Completed', 'completed'),
                const SizedBox(width: 8),
                _chip('Cancelled', 'cancelled'),
              ]),
            ),
          ]),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _fs.collection('client_purchases').orderBy('purchaseDate', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _navy));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return _emptyState('No purchases found.');
          }

          final allPurchases = snap.data!.docs
              .map((d) {
                final m = d.data() as Map<String, dynamic>;
                m['_docId'] = d.id;
                return m;
              })
              .where((m) {
                // Filter by status chip
                final status = (m['status'] as String? ?? 'active').toLowerCase();
                if (_filter != 'all' && status != _filter) return false;
                // Filter by search
                if (_searchQuery.isNotEmpty) {
                  final clientName = (m['clientName'] ?? '').toString().toLowerCase();
                  final planName   = (m['planName']   ?? '').toString().toLowerCase();
                  return clientName.contains(_searchQuery) || planName.contains(_searchQuery);
                }
                return true;
              })
              .toList();

          if (allPurchases.isEmpty) {
            return _emptyState('No results for "$_searchQuery".');
          }

          // Group by userId
          final Map<String, List<Map<String, dynamic>>> byClient = {};
          for (final p in allPurchases) {
            final uid = p['userId'] as String? ?? 'unknown';
            byClient.putIfAbsent(uid, () => []).add(p);
          }

          // Build summary totals
          int totalPurchased = 0, totalUsed = 0, totalRemaining = 0;
          for (final p in allPurchases) {
            totalPurchased += (p['totalSessions'] as int? ?? p['sessions'] as int? ?? 0);
            totalUsed      += (p['usedSessions']  as int? ?? 0);
            totalRemaining += (p['remainingSessions'] as int? ?? 0);
          }

          return Column(children: [
            // Summary bar
            _buildSummary(totalPurchased, totalUsed, totalRemaining, allPurchases.length),
            // Client list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                itemCount: byClient.length,
                itemBuilder: (_, i) {
                  final uid = byClient.keys.elementAt(i);
                  final plans = byClient[uid]!;
                  return _buildClientCard(uid, plans);
                },
              ),
            ),
          ]);
        },
      ),
    );
  }

  // ── Summary banner ────────────────────────────────────────────────────────
  Widget _buildSummary(int total, int used, int remaining, int purchases) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.08),
              blurRadius: 12, offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        _summaryTile('Total', '$total', Icons.bar_chart_rounded, _navy),
        _vDivider(),
        _summaryTile('Completed', '$used', Icons.check_circle_rounded, _green),
        _vDivider(),
        _summaryTile('Remaining', '$remaining', Icons.hourglass_bottom_rounded, _orange),
        _vDivider(),
        _summaryTile('Plans', '$purchases', Icons.card_membership_rounded, _teal),
      ]),
    );
  }

  Widget _summaryTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
      ]),
    );
  }

  Widget _vDivider() => Container(
      width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.shade200);

  // ── Client card (expandable) ──────────────────────────────────────────────
  Widget _buildClientCard(String uid, List<Map<String, dynamic>> plans) {
    final clientName = (plans.first['clientName'] as String?)?.trim();
    final displayName = (clientName != null && clientName.isNotEmpty)
        ? clientName
        : 'Unknown Client';

    // Aggregate for this client
    int clientTotal = 0, clientUsed = 0, clientRemaining = 0;
    for (final p in plans) {
      clientTotal     += (p['totalSessions'] as int? ?? p['sessions'] as int? ?? 0);
      clientUsed      += (p['usedSessions']  as int? ?? 0);
      clientRemaining += (p['remainingSessions'] as int? ?? 0);
    }
    final progress = clientTotal == 0 ? 0.0 : (clientUsed / clientTotal).clamp(0.0, 1.0);
    final isExpanded = _expanded.contains(uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _navy.withValues(alpha: 0.07),
              blurRadius: 10, offset: const Offset(0, 3))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Client header (tappable)
        GestureDetector(
          onTap: () => setState(() {
            if (isExpanded) { _expanded.remove(uid); } else { _expanded.add(uid); }
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              // Avatar circle
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: _navy),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name + compact stats
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    _miniPill('${plans.length} plan${plans.length == 1 ? '' : 's'}',
                        _navy.withValues(alpha: 0.08), _navy),
                    const SizedBox(width: 6),
                    _miniPill('$clientUsed done', _green.withValues(alpha: 0.1), _green),
                    const SizedBox(width: 6),
                    _miniPill('$clientRemaining left', _orange.withValues(alpha: 0.1), _orange),
                  ]),
                  const SizedBox(height: 6),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade100,
                      color: progress >= 1.0 ? _green : _teal,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey),
            ]),
          ),
        ),
        // Expanded plan rows
        if (isExpanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14),
          ...plans.map((p) => _buildPlanRow(p)),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }

  // ── Individual plan row ───────────────────────────────────────────────────
  Widget _buildPlanRow(Map<String, dynamic> p) {
    final planName  = p['planName'] as String? ?? 'Unknown Plan';
    final total     = p['totalSessions'] as int? ?? p['sessions'] as int? ?? 0;
    final used      = p['usedSessions']  as int? ?? 0;
    final remaining = p['remainingSessions'] as int? ?? 0;
    final status    = (p['status'] as String? ?? 'active').toLowerCase();
    final purchaseDate = p['purchaseDate'] as Timestamp?;

    final statusColor = status == 'active' ? _green
        : status == 'completed' ? _teal
        : _red;
    final progress = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0);

    String dateStr = '';
    if (purchaseDate != null) {
      dateStr = DateFormat('MMM d, y').format(purchaseDate.toDate().toLocal());
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Plan icon
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.card_membership_rounded, size: 17, color: statusColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(planName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (dateStr.isNotEmpty)
                Text('Purchased $dateStr',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ]),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999)),
            child: Text(
              status[0].toUpperCase() + status.substring(1),
              style: TextStyle(fontSize: 10, color: statusColor,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // Session counts
        Row(children: [
          _sessionBox('Total', '$total', _navy),
          const SizedBox(width: 8),
          _sessionBox('Completed', '$used', _green),
          const SizedBox(width: 8),
          _sessionBox('Remaining', '$remaining', _orange),
        ]),
        const SizedBox(height: 8),
        // Progress bar
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                color: progress >= 1.0 ? _green : _teal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(progress * 100).round()}%',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: progress >= 1.0 ? _green : _teal)),
        ]),
      ]),
    );
  }

  Widget _sessionBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ]),
      ),
    );
  }

  Widget _miniPill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 9.5, color: fg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _chip(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? _navy : Colors.white)),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.bar_chart_rounded, size: 56, color: Colors.grey),
        const SizedBox(height: 12),
        Text(message,
            style: const TextStyle(fontSize: 15, color: Colors.grey)),
      ]),
    );
  }
}
