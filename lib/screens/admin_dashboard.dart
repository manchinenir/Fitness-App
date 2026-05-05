import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/admin_access.dart';
import 'Admin_Plan_Screen.dart';
import 'admin_create_slots.dart';
import 'client_list_screen.dart';
import 'post_announcement.dart';
import 'RevenueReport_screen.dart';
import 'settings.dart';
import 'active_members_screen.dart'; // ⬅️ tap the pie to open this page

class AdminDashboard extends StatefulWidget {
  final String userName;

  const AdminDashboard({super.key, required this.userName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _fs = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  File? _profileImage;
  String adminName = 'Admin';

  final Map<String, List<Map<String, String>>> availabilityMap = const {
    'Monday': [
      {'start': '05:30', 'end': '11:00'},
      {'start': '16:30', 'end': '19:00'}
    ],
    'Tuesday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'}
    ],
    'Wednesday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'}
    ],
    'Thursday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'}
    ],
    'Friday': [
      {'start': '05:30', 'end': '11:00'}
    ],
    'Saturday': [
      {'start': '05:30', 'end': '11:00'}
    ],
    'Sunday': [
      {'start': '05:30', 'end': '11:00'}
    ],
  };

  late final DateTime _weekStart;
  late final DateTime _nextWeekStart;
  late final int _totalSlotsThisWeek;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = _mondayStart(now);
    _nextWeekStart = _weekStart.add(const Duration(days: 7));
    _totalSlotsThisWeek = _totalSlotsForWeek(_weekStart, availabilityMap);
    _enforceAdminAccess();
    _loadAdminName(); // keeps local fallback for first time login
  }

  Future<void> _enforceAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser == null || !refreshedUser.emailVerified) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your email before accessing the admin side.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    if (AdminAccess.isAllowedAdminEmail(refreshedUser.email)) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This account is not allowed to access the admin side.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _loadAdminName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedName = prefs.getString('admin_name');

      if (savedName != null && savedName.isNotEmpty) {
        setState(() {
          adminName = savedName;
        });
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await _fs.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data();
          final name = (data != null && data['name'] != null) ? data['name'].toString() : null;
          if (name != null && name.isNotEmpty) {
            setState(() {
              adminName = name;
            });
            await prefs.setString('admin_name', name);
            return;
          }
        }
      }

      if (widget.userName.isNotEmpty) {
        setState(() {
          adminName = _getNameFromEmail(widget.userName);
        });
      }
    } catch (e) {
      debugPrint('Error loading admin name: $e');
      if (widget.userName.isNotEmpty) {
        setState(() {
          adminName = _getNameFromEmail(widget.userName);
        });
      }
    }
  }

  // ========= Active predicate helpers (respect status + date window) =========
  bool _isWithin(DateTime now, Timestamp? start, Timestamp? end) {
    final s = start?.toDate();
    final e = end?.toDate();
    final afterStart = (s == null) || !now.isBefore(s);
    final beforeEnd  = (e == null) || !now.isAfter(e);
    return afterStart && beforeEnd;
  }

  bool _isCurrentlyActive(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status != 'active') return false;

    return _isWithin(
      DateTime.now(),
      data['startDate'] is Timestamp ? data['startDate'] as Timestamp : null,
      data['endDate']   is Timestamp ? data['endDate']   as Timestamp : null,
    );
  }

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
  // =========================================================================

  // (Old _activeMembersStream removed; pie uses nested builders to union purchases+subs)

  Stream<int> _bookedThisWeekStream() {
    final q = _fs
        .collection('trainer_slots')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_weekStart))
        .where('date', isLessThan: Timestamp.fromDate(_nextWeekStart))
        .snapshots();
    return q.map((snap) {
      int total = 0;
      for (final d in snap.docs) {
        final data = d.data();
        final booked = (data.containsKey('booked')) ? (data['booked'] as int?) : null;
        total += booked ?? 0;
      }
      return total;
    });
  }

  String _getGreeting() {
    final nowUtc = DateTime.now().toUtc();
    final year = nowUtc.year;

    DateTime findNthSunday(int year, int month, int n) {
      DateTime date = DateTime.utc(year, month, 1);
      int daysToAdd = (DateTime.sunday - date.weekday + 7) % 7;
      date = date.add(Duration(days: daysToAdd));
      return date.add(Duration(days: 7 * (n - 1)));
    }

    final dstStart = DateTime.utc(year, 3, findNthSunday(year, 3, 2).day, 7); // 2nd Sun Mar @07:00 UTC
    final dstEnd   = DateTime.utc(year, 11, findNthSunday(year, 11, 1).day, 6); // 1st Sun Nov @06:00 UTC
    final isDST = nowUtc.isAfter(dstStart) && nowUtc.isBefore(dstEnd);
    final easternTime = nowUtc.add(Duration(hours: isDST ? -4 : -5));
    final hour = easternTime.hour;

    if (hour >= 0 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getNameFromEmail(String email) {
    if (email.contains('@')) return email.split('@')[0];
    return email;
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  DateTime _mondayStart(DateTime d) {
    final localMidnight = DateTime(d.year, d.month, d.day);
    final delta = (localMidnight.weekday - DateTime.monday);
    return localMidnight.subtract(Duration(days: delta));
  }

  int _totalSlotsForWeek(DateTime monday, Map<String, List<Map<String, String>>> avail) {
    int total = 0;
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final weekdayName = DateFormat('EEEE').format(day);
      final blocks = avail[weekdayName] ?? [];
      for (final b in blocks) {
        final start = b['start'];
        final end = b['end'];
        if (start != null && end != null) {
          total += _hourSlotsInBlock(start, end, day);
        }
      }
    }
    return total;
  }

  int _hourSlotsInBlock(String start, String end, DateTime day) {
    final fmt = DateFormat('HH:mm');
    final startParsed = fmt.parse(start);
    final endParsed = fmt.parse(end);

    DateTime s = DateTime(day.year, day.month, day.day, startParsed.hour, startParsed.minute);
    final e = DateTime(day.year, day.month, day.day, endParsed.hour, endParsed.minute);
    int count = 0;
    while (s.isBefore(e)) {
      s = s.add(const Duration(hours: 1));
      count++;
      if (count > 24) break;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final double appBarExpandedHeight = MediaQuery.of(context).size.height * 0.26;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: appBarExpandedHeight,
            backgroundColor: const Color(0xFF1C2D5E),
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1C2D5E), Color(0xFF2E4A9E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _pickProfileImage,
                          child: Stack(
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2.5),
                                  gradient: _profileImage == null
                                      ? const LinearGradient(
                                          colors: [Color(0xFF4A6FD4), Color(0xFF2E4A9E)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  image: _profileImage != null
                                      ? DecorationImage(image: FileImage(_profileImage!), fit: BoxFit.cover)
                                      : null,
                                ),
                                child: _profileImage == null
                                    ? const Icon(Icons.person, size: 30, color: Colors.white)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 12, color: Color(0xFF1C2D5E)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.wb_sunny_outlined, color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getGreeting(),
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.3),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (user != null)
                                StreamBuilder<DocumentSnapshot>(
                                  stream: _fs.collection('users').doc(user.uid).snapshots(),
                                  builder: (context, snapshot) {
                                    String displayName = adminName;
                                    if (snapshot.hasData && snapshot.data!.exists) {
                                      final data = snapshot.data!.data() as Map<String, dynamic>;
                                      final liveName = data['name']?.toString() ?? '';
                                      if (liveName.isNotEmpty) displayName = liveName;
                                    }
                                    final capitalized = displayName.isNotEmpty
                                        ? '${displayName[0].toUpperCase()}${displayName.substring(1)}'
                                        : displayName;
                                    return Text(
                                      capitalized,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 23,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.2,
                                      ),
                                    );
                                  },
                                )
                              else
                                Text(adminName, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Admin',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.logout_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Stats Row ──────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _fs.collection('client_purchases').where('status', isEqualTo: 'active').snapshots(),
                        builder: (context, purchasesSnap) {
                          final activePurchaseUsers = <String>{};
                          for (final d in (purchasesSnap.data?.docs ?? [])) {
                            final m = d.data() as Map<String, dynamic>;
                            if (_isCurrentlyActive(m)) {
                              final uid = (m['userId'] ?? '').toString();
                              if (uid.isNotEmpty) activePurchaseUsers.add(uid);
                            }
                          }
                          return StreamBuilder<QuerySnapshot>(
                            stream: _fs.collection('client_subscriptions').where('status', isEqualTo: 'active').snapshots(),
                            builder: (context, subsSnap) {
                              final usersWithSubs = <String>{};
                              for (final d in (subsSnap.data?.docs ?? [])) {
                                final m = d.data() as Map<String, dynamic>;
                                if (_isSubscriptionActive(m)) {
                                  final uid = (m['userId'] ?? '').toString();
                                  if (uid.isNotEmpty) usersWithSubs.add(uid);
                                }
                              }
                              final activeUsersUnion = <String>{}..addAll(activePurchaseUsers)..addAll(usersWithSubs);
                              return FutureBuilder<QuerySnapshot>(
                                future: _fs.collection('users').where('role', isEqualTo: 'client').get(),
                                builder: (context, usersSnap) {
                                  final totalClients = usersSnap.data?.docs.length ?? 0;
                                  final activeCount = activeUsersUnion.length;
                                  final pct = totalClients == 0 ? 0.0 : (activeCount / totalClients).clamp(0.0, 1.0);
                                  return GestureDetector(
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActiveMembersScreen())),
                                    child: _buildStatCard(
                                      icon: Icons.people_alt_rounded,
                                      label: 'Active Members',
                                      value: purchasesSnap.connectionState == ConnectionState.waiting ? '—' : activeCount.toString(),
                                      sub: totalClients > 0 ? 'of $totalClients total' : 'members',
                                      percentage: pct,
                                      gradientColors: const [Color(0xFF4A6FD4), Color(0xFF7B9EFF)],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: StreamBuilder<int>(
                        stream: _bookedThisWeekStream(),
                        builder: (context, snap) {
                          final booked = snap.data ?? 0;
                          final pct = _totalSlotsThisWeek == 0 ? 0.0 : (booked / _totalSlotsThisWeek).clamp(0.0, 1.0);
                          return GestureDetector(
                            onTap: () {
                              final now = DateTime.now();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ScheduleSlotsDetailScreen(
                                    weekStart: now.subtract(const Duration(days: 7)),
                                    nextWeekStart: now.add(const Duration(days: 60)),
                                  ),
                                ),
                              );
                            },
                            child: _buildStatCard(
                              icon: Icons.event_available_rounded,
                              label: 'This Week',
                              value: booked.toString(),
                              sub: 'slots booked',
                              percentage: pct,
                              gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Section Label ──────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C2D5E),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                // ── Nav Grid ───────────────────────────────────────────
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.15,
                  children: [
                    _buildNavTile(
                      context,
                      Icons.calendar_today_rounded,
                      'Trainer\nSchedule',
                      const AdminCreateSlotsScreen(),
                      gradientColors: const [Color(0xFF4A6FD4), Color(0xFF7B9EFF)],
                    ),
                    _buildNavTile(
                      context,
                      Icons.people_alt_rounded,
                      'Client\nList',
                      const ClientListScreen(),
                      gradientColors: const [Color(0xFF9B59B6), Color(0xFFD98AFF)],
                    ),
                    _buildNavTile(
                      context,
                      FontAwesomeIcons.dollarSign,
                      'Revenue\nReport',
                      const RevenueReportScreen(),
                      gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
                    ),
                    _buildNavTile(
                      context,
                      FontAwesomeIcons.dumbbell,
                      'Workout\nPlans',
                      null,
                      gradientColors: const [Color(0xFFE67E22), Color(0xFFF5A623)],
                      action: () => Navigator.pushNamed(context, '/adminWorkoutMulti', arguments: []),
                    ),
                    _buildNavTile(
                      context,
                      Icons.campaign_rounded,
                      'Announce-\nments',
                      const PostAnnouncementScreen(),
                      gradientColors: const [Color(0xFFE74C3C), Color(0xFFFF7675)],
                    ),
                    _buildNavTile(
                      context,
                      Icons.settings_rounded,
                      'Settings',
                      const AdminSettingsPage(),
                      gradientColors: const [Color(0xFF636E72), Color(0xFFB2BEC3)],
                    ),
                    _buildNavTile(
                      context,
                      Icons.card_membership_rounded,
                      'Plans',
                      const PlansScreen(),
                      gradientColors: const [Color(0xFF00B09B), Color(0xFF96C93D)],
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required double percentage,
    required List<Color> gradientColors,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const Spacer(),
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  value: percentage,
                  strokeWidth: 4,
                  backgroundColor: gradientColors[0].withValues(alpha: 0.15),
                  color: gradientColors[0],
                  strokeCap: StrokeCap.round,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: gradientColors[0],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C2D5E))),
          Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context,
    IconData icon,
    String label,
    Widget? targetScreen, {
    VoidCallback? action,
    required List<Color> gradientColors,
  }) {
    return GestureDetector(
      onTap: targetScreen != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => targetScreen))
          : action,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned(
                top: -18,
                right: -18,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [gradientColors[0].withValues(alpha: 0.12), gradientColors[1].withValues(alpha: 0.05)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: gradientColors[0].withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C2D5E),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Schedule Slots Detail Screen (unchanged functional logic) =====
class ScheduleSlotsDetailScreen extends StatefulWidget {
  final DateTime weekStart;
  final DateTime nextWeekStart;

  const ScheduleSlotsDetailScreen({
    super.key,
    required this.weekStart,
    required this.nextWeekStart,
  });

  @override
  State<ScheduleSlotsDetailScreen> createState() => _ScheduleSlotsDetailScreenState();
}

class _ScheduleSlotsDetailScreenState extends State<ScheduleSlotsDetailScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  List<SlotDetail> _slots = [];
  bool _isLoading = true;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchSlots();
    // Re-evaluate slot statuses every minute so TODAY slots flip to COMPLETED as time passes
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _recomputeStatuses();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _recomputeStatuses() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      for (int i = 0; i < _slots.length; i++) {
        final s = _slots[i];
        final endDt = _parseAmPmTime(s.endTime, s.date);
        String status;
        if (now.isAfter(endDt)) {
          status = 'COMPLETED';
        } else if (s.date.isAfter(today)) {
          status = 'UPCOMING';
        } else {
          status = 'TODAY';
        }
        _slots[i] = SlotDetail(
          date: s.date,
          startTime: s.startTime,
          endTime: s.endTime,
          booked: s.booked,
          status: status,
          bookedNames: s.bookedNames,
        );
      }
      _slots.sort(_compareSlots);
    });
  }

  // Parses "5:30 AM" or "6:00 PM" style times into a DateTime on the given date.
  DateTime _parseAmPmTime(String raw, DateTime date) {
    try {
      final parsed = DateFormat('h:mm a').parse(raw.trim().toUpperCase());
      return DateTime(date.year, date.month, date.day, parsed.hour, parsed.minute);
    } catch (_) {
      try {
        final parsed = DateFormat('HH:mm').parse(raw.trim());
        return DateTime(date.year, date.month, date.day, parsed.hour, parsed.minute);
      } catch (_) {
        return DateTime(date.year, date.month, date.day, 23, 59);
      }
    }
  }

  int _compareSlots(SlotDetail a, SlotDetail b) {
    final orderA = _getOrder(a.status);
    final orderB = _getOrder(b.status);
    if (orderA != orderB) return orderA.compareTo(orderB);
    final aDateTime = _parseSlotDateTime(a);
    final bDateTime = _parseSlotDateTime(b);
    // COMPLETED: most recent first; TODAY/UPCOMING: earliest first
    return a.status == 'COMPLETED'
        ? bDateTime.compareTo(aDateTime)
        : aDateTime.compareTo(bDateTime);
  }

  Future<void> _fetchSlots() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Documents are keyed "yyyy-MM-dd|slot_time" — query by ID range.
      final startKey = DateFormat('yyyy-MM-dd').format(widget.weekStart);
      final endKey   = DateFormat('yyyy-MM-dd').format(widget.nextWeekStart);

      final querySnapshot = await _fs
          .collection('trainer_slots')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
          .where(FieldPath.documentId, isLessThan: endKey)
          .get();

      final List<SlotDetail> slots = [];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final docId = doc.id;

        // Parse date and slot time from "yyyy-MM-dd|5:30 AM - 6:30 AM"
        final pipeIdx = docId.indexOf('|');
        if (pipeIdx < 0) continue;
        final dateStr  = docId.substring(0, pipeIdx);
        final slotTime = docId.substring(pipeIdx + 1);

        DateTime date;
        try {
          date = DateFormat('yyyy-MM-dd').parseStrict(dateStr);
        } catch (_) {
          continue;
        }

        // Count bookings from booked_by array
        final bookedBy = List<String>.from(data['booked_by'] ?? []);
        final bookedCount = bookedBy.length;
        if (bookedCount == 0) continue;

        // Split "5:30 AM - 6:30 AM" → start / end
        final timeParts = slotTime.split(RegExp(r'\s*[-–]\s*'));
        final startTimeStr = timeParts.isNotEmpty ? timeParts[0].trim() : slotTime;
        final endTimeStr   = timeParts.length > 1  ? timeParts[1].trim() : '';

        final endDt = _parseAmPmTime(
          endTimeStr.isNotEmpty ? endTimeStr : startTimeStr,
          date,
        );

        final String status;
        if (now.isAfter(endDt)) {
          status = 'COMPLETED';
        } else if (date.isAfter(today)) {
          status = 'UPCOMING';
        } else {
          status = 'TODAY';
        }

        slots.add(SlotDetail(
          date: date,
          startTime: startTimeStr,
          endTime: endTimeStr.isNotEmpty ? endTimeStr : startTimeStr,
          booked: bookedCount,
          status: status,
          bookedNames: List<String>.from(data['booked_names'] ?? []),
        ));
      }

      slots.sort(_compareSlots);

      setState(() {
        _slots = slots;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching slots: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  int _getOrder(String status) {
    switch (status) {
      case 'TODAY':
        return 0;
      case 'UPCOMING':
        return 1;
      case 'COMPLETED':
        return 2;
      default:
        return 1;
    }
  }

  DateTime _parseSlotDateTime(SlotDetail slot) {
    return _parseAmPmTime(slot.startTime, slot.date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduled Sessions'),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _slots.isEmpty
              ? const Center(child: Text('No booked slots found for this week'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _buildGroupedSlotsWithHeaders().length,
                  itemBuilder: (context, index) {
                    final item = _buildGroupedSlotsWithHeaders()[index];
                    
                    if (item is String) {
                      // Date header
                      return Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C2D5E),
                          ),
                        ),
                      );
                    } else {
                      // Slot card
                      return _buildSlotCard(item as SlotDetail);
                    }
                  },
                ),
    );
  }

  List<dynamic> _buildGroupedSlotsWithHeaders() {
    final result = <dynamic>[];
    String? lastDateKey;
    final dayFormat = DateFormat('EEEE, MMMM d, yyyy');
    
    for (final slot in _slots) {
      final dateKey = dayFormat.format(slot.date);
      
      if (lastDateKey != dateKey) {
        result.add(dateKey);
        lastDateKey = dateKey;
      }
      
      result.add(slot);
    }
    
    return result;
  }

  Widget _buildSlotCard(SlotDetail slot) {
    final Color badgeColor = _getBadgeColor(slot.status);
    final Color textColor = _getBadgeTextColor(slot.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  slot.status,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${slot.startTime} - ${slot.endTime}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C2D5E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event_seat, color: Color(0xFF1C2D5E), size: 20),
              const SizedBox(width: 8),
              Text(
                '${slot.booked} booked slot${slot.booked > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
          if (slot.bookedNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.people, color: Color(0xFF1C2D5E), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '👥 ${slot.bookedNames.join(', ')}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getBadgeColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.red;
      case 'TODAY':
        return Colors.blue;
      case 'UPCOMING':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getBadgeTextColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.red;
      case 'TODAY':
        return Colors.blue;
      case 'UPCOMING':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

class SlotDetail {
  final DateTime date;
  final String startTime;
  final String endTime;
  final int booked;
  final String status;
  final List<String> bookedNames;

  SlotDetail({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.booked,
    required this.status,
    required this.bookedNames,
  });
}