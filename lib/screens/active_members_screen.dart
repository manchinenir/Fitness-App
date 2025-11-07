import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ActiveMembersScreen extends StatefulWidget {
  const ActiveMembersScreen({super.key});

  @override
  State<ActiveMembersScreen> createState() => _ActiveMembersScreenState();
}

class _ActiveMembersScreenState extends State<ActiveMembersScreen> {
  final _fs = FirebaseFirestore.instance;
  String _query = '';

  // ---------- Helpers ----------
  bool _isWithin(DateTime now, Timestamp? start, Timestamp? end) {
    final s = start?.toDate();
    final e = end?.toDate();
    final afterStart = (s == null) || !now.isBefore(s);
    final beforeEnd  = (e == null) || !now.isAfter(e);
    return afterStart && beforeEnd;
  }

  /// A record is active iff status == 'active' and (now is inside [startDate, endDate] if present).
  bool _isCurrentlyActive(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status != 'active') return false;

    return _isWithin(
      DateTime.now(),
      data['startDate'] is Timestamp ? data['startDate'] as Timestamp : null,
      data['endDate']   is Timestamp ? data['endDate']   as Timestamp : null,
    );
  }

  // NEW: Check if subscription is active (similar to PDF workouts logic)
  bool _isSubscriptionActive(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status != 'active') return false;

    // Check if subscription has isActive field
    final isActive = data['isActive'] == true;
    if (!isActive) return false;

    // Check date validity
    final endDate = data['endDate'];
    if (endDate == null) return true; // No end date = always active

    DateTime end;
    if (endDate is Timestamp) {
      end = endDate.toDate();
    } else if (endDate is DateTime) {
      end = endDate;
    } else if (endDate is String) {
      end = DateTime.tryParse(endDate) ?? DateTime.now().add(const Duration(days: 1));
    } else {
      return false;
    }

    return DateTime.now().isBefore(end);
  }

  Future<Map<String, _UserDoc>> _fetchUsersByIds(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final Map<String, _UserDoc> out = {};
    final list = ids.toList();
    for (int i = 0; i < list.length; i += 10) {
      final batch = list.sublist(i, (i + 10 > list.length) ? list.length : i + 10);
      final q = await _fs.collection('users')
          .where(FieldPath.documentId, whereIn: batch).get();
      for (final d in q.docs) {
        final data = d.data();
        out[d.id] = _UserDoc(
          uid: d.id,
          name: (data['name'] ?? '').toString(),
          email: (data['email'] ?? '').toString(),
          phone: (data['phone'] ?? '').toString(),
        );
      }
    }
    return out;
  }

  String _planTitle(Map<String, dynamic> data) {
    return (data['planName'] ??
            data['plan_title'] ??
            data['subscriptionName'] ??
            data['name'] ??
            data['title'] ??
            data['plan'] ??
            'Plan')
        .toString();
  }

  String _dateRange(Map<String, dynamic> data) {
    final tsStart = data['startDate'];
    final tsEnd = data['endDate'];
    DateTime? s, e;
    if (tsStart is Timestamp) s = tsStart.toDate();
    if (tsEnd is Timestamp) e = tsEnd.toDate();
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
    if (s != null && e != null) return '${fmt(s)} – ${fmt(e)}';
    if (s != null) return 'From ${fmt(s)}';
    if (e != null) return 'Until ${fmt(e)}';
    return '';
  }

  String _sourceLabel(QueryDocumentSnapshot doc) {
    return doc.reference.parent.id == 'client_subscriptions'
        ? 'Subscription'
        : 'Purchase';
  }

  bool _hasPdfUrl(Map<String, dynamic> data) {
    final candidates = [
      data['pdfUrl'],
      data['planPdf'],
      data['fileUrl'],
      data['document'],
      data['attachmentUrl'],
    ].whereType<String>().toList();
    return candidates.any((u) => u.toLowerCase().trim().endsWith('.pdf'));
  }

  bool _isPdfPlan(Map<String, dynamic> data) {
    final isPdfFlag =
        (data['isPdf'] == true) || (data['type']?.toString().toLowerCase() == 'pdf');
    return isPdfFlag || _hasPdfUrl(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2D5E),
        title: const Text('Active Members'),
        foregroundColor: Colors.white,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ---- Data ----
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fs.collection('client_purchases')
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, purchasesSnap) {
                if (purchasesSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (purchasesSnap.hasError) {
                  return Center(child: Text('Error: ${purchasesSnap.error}'));
                }
                final rawPurchases = purchasesSnap.data?.docs ?? [];

                return StreamBuilder<QuerySnapshot>(
                  stream: _fs.collection('client_subscriptions')
                      .where('status', isEqualTo: 'active')
                      .snapshots(),
                  builder: (context, subsSnap) {
                    if (subsSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (subsSnap.hasError) {
                      return Center(child: Text('Error: ${subsSnap.error}'));
                    }

                    // ------ Filter out expired by dates ------
                    final purchases = rawPurchases.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return _isCurrentlyActive(data);
                    }).toList();

                    final subs = (subsSnap.data?.docs ?? []).where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return _isSubscriptionActive(data); // Use the new subscription check
                    }).toList();

                    // ------ Build rows (only active items) ------
                    final merged = <QueryDocumentSnapshot>[...purchases, ...subs];

                    final Map<String, List<_PlanInfo>> plansByUser = {};
                    final Set<String> userIds = {};
                    final Set<String> usersWithActivePurchases = {};
                    final Set<String> usersWithActiveSubscriptions = {};

                    for (final d in merged) {
                      final data = d.data() as Map<String, dynamic>;
                      final uid = (data['userId'] ?? '').toString();
                      if (uid.isEmpty) continue;

                      final isSub =
                          d.reference.parent.id == 'client_subscriptions';

                      userIds.add(uid);
                      if (isSub) {
                        usersWithActiveSubscriptions.add(uid);
                      } else {
                        usersWithActivePurchases.add(uid);
                      }

                      plansByUser.putIfAbsent(uid, () => []).add(
                        _PlanInfo(
                          title: _planTitle(data),
                          dateRange: _dateRange(data),
                          price: (data['price'] ?? data['amount'] ?? '').toString(),
                          sessions: data['sessions'] is int ? data['sessions'] as int : null,
                          source: isSub ? 'Subscription' : 'Purchase',
                          isPdf: _isPdfPlan(data),
                        ),
                      );
                    }

                    return FutureBuilder<Map<String, _UserDoc>>(
                      future: _fetchUsersByIds(userIds),
                      builder: (context, usersFb) {
                        if (usersFb.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (usersFb.hasError) {
                          return Center(child: Text('Error: ${usersFb.error}'));
                        }

                        final users = usersFb.data ?? {};
                        final List<_ActiveRow> rows = [];
                        plansByUser.forEach((uid, plans) {
                          final u = users[uid] ??
                              _UserDoc(uid: uid, name: '', email: '', phone: '');
                          rows.add(_ActiveRow(user: u, plans: plans));
                        });

                        // Sort & Search
                        rows.sort((a, b) {
                          final an = a.user.name.isNotEmpty ? a.user.name : a.user.email;
                          final bn = b.user.name.isNotEmpty ? b.user.name : b.user.email;
                          return an.toLowerCase().compareTo(bn.toLowerCase());
                        });

                        final q = _query.toLowerCase();
                        final filtered = q.isEmpty
                            ? rows
                            : rows.where((r) {
                                final name = r.user.name.toLowerCase();
                                final email = r.user.email.toLowerCase();
                                return name.contains(q) || email.contains(q);
                              }).toList();

                        // --------- Correct stats ----------
                        // Count unique users who have either active purchases OR active subscriptions
                        final activeMembers = 
                            {...usersWithActivePurchases, ...usersWithActiveSubscriptions}.length;
                        final activePlansCount = purchases.length;       // non-sub plans
                        final activeSubsCount  = subs.length;            // subscriptions

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _StatPill(
                                      label: 'Active Members',
                                      value: activeMembers.toString(),
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _StatPill(
                                      label: 'Active Plans',
                                      value: activePlansCount.toString(),
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _StatPill(
                                      label: 'Subscription',
                                      value: activeSubsCount.toString(),
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),

                            Expanded(
                              child: filtered.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No active members found.',
                                        style: TextStyle(color: Colors.black54),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, i) {
                                        final row = filtered[i];
                                        final u = row.user;
                                        final count = row.plans.length;

                                        final chips = row.plans.take(3).map((p) {
                                          final label =
                                              p.title.isNotEmpty ? p.title : 'Plan';
                                          final isSub = p.source == 'Subscription';
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                right: 6, bottom: 4),
                                            child: Chip(
                                              avatar: Icon(
                                                p.isPdf
                                                    ? Icons.picture_as_pdf
                                                    : (isSub
                                                        ? Icons.autorenew
                                                        : Icons.shopping_bag),
                                                size: 14,
                                                color: p.isPdf
                                                    ? Colors.red
                                                    : (isSub
                                                        ? Colors.deepPurple
                                                        : Colors.blue),
                                              ),
                                              label: Text(label,
                                                  style: const TextStyle(fontSize: 12)),
                                              backgroundColor: p.isPdf
                                                  ? Colors.red.shade50
                                                  : (isSub
                                                      ? Colors.deepPurple.shade50
                                                      : Colors.blue.shade50),
                                            ),
                                          );
                                        }).toList();

                                        final remaining = count - chips.length;

                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.grey.withOpacity(0.08),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: ExpansionTile(
                                            tilePadding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            leading: CircleAvatar(
                                              backgroundColor:
                                                  Colors.indigo.shade50,
                                              child: Text(
                                                (u.name.isNotEmpty
                                                        ? u.name[0]
                                                        : (u.email.isNotEmpty
                                                            ? u.email[0]
                                                            : '?'))
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                    color: Colors.indigo),
                                              ),
                                            ),
                                            title: Text(
                                              u.name.isNotEmpty ? u.name : u.email,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            subtitle: Wrap(children: [
                                              ...chips,
                                              if (remaining > 0)
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                      right: 6, bottom: 4),
                                                  child: Chip(
                                                    label: Text(
                                                      '+$remaining more',
                                                      style: const TextStyle(
                                                          fontSize: 12),
                                                    ),
                                                    backgroundColor:
                                                        Colors.grey.shade200,
                                                  ),
                                                ),
                                            ]),
                                            trailing: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                    color: Colors.green
                                                        .withOpacity(0.25)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.check_circle,
                                                      size: 16, color: Colors.green),
                                                  const SizedBox(width: 6),
                                                  Text('$count',
                                                      style: const TextStyle(
                                                          color: Colors.green,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                ],
                                              ),
                                            ),
                                            children: [
                                              const Divider(height: 1),
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(
                                                    12, 8, 12, 12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: row.plans.map((p) {
                                                    final details = [
                                                      p.isPdf ? 'PDF' : p.source,
                                                      if (p.price.isNotEmpty)
                                                        '\$${p.price}',
                                                      if (p.sessions != null)
                                                        '${p.sessions} sessions',
                                                      if (p.dateRange.isNotEmpty)
                                                        p.dateRange,
                                                    ]
                                                        .where((e) => e.isNotEmpty)
                                                        .join(' • ');
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              bottom: 8.0),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            p.isPdf
                                                                ? Icons
                                                                    .picture_as_pdf
                                                                : (p.source ==
                                                                        'Subscription'
                                                                    ? Icons
                                                                        .autorenew
                                                                    : Icons
                                                                        .shopping_bag),
                                                            size: 16,
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              '${p.title}${details.isNotEmpty ? '  —  $details' : ''}',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserDoc {
  final String uid;
  final String name;
  final String email;
  final String phone;
  _UserDoc({required this.uid, required this.name, required this.email, required this.phone});
}

class _PlanInfo {
  final String title;
  final String dateRange;
  final String price;
  final int? sessions;
  final String source; // "Purchase" or "Subscription"
  final bool isPdf;    // whether the plan has a PDF file associated
  _PlanInfo({
    required this.title,
    required this.dateRange,
    required this.price,
    this.sessions,
    required this.source,
    required this.isPdf,
  });
}

class _ActiveRow {
  final _UserDoc user;
  final List<_PlanInfo> plans;
  _ActiveRow({required this.user, required this.plans});
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatPill({required this.label, required this.value, required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3)),
        ],
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}