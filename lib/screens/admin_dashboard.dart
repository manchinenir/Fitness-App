import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Admin_Plan_Screen.dart';
import 'admin_create_slots.dart';
import 'client_list_screen.dart';
import 'post_announcement.dart';
import 'RevenueReport_screen.dart';
import 'settings.dart';

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
    _loadAdminName(); // keeps local fallback for first time login
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

  // Updated _getGreeting function to use US Eastern Time
  String _getGreeting() {
    final nowUtc = DateTime.now().toUtc();
    final year = nowUtc.year;

    // Calculate DST boundaries for US Eastern Time
    // DST starts: 2nd Sunday in March at 2:00 AM EST (7:00 AM UTC)
    // DST ends: 1st Sunday in November at 2:00 AM EDT (6:00 AM UTC)
    
    // Helper function to find nth Sunday of a month
    DateTime findNthSunday(int year, int month, int n) {
      DateTime date = DateTime.utc(year, month, 1);
      int daysToAdd = (DateTime.sunday - date.weekday + 7) % 7;
      date = date.add(Duration(days: daysToAdd));
      return date.add(Duration(days: 7 * (n - 1)));
    }

    // DST start: 2nd Sunday in March at 7:00 AM UTC
    final dstStart = DateTime.utc(year, 3, findNthSunday(year, 3, 2).day, 7);
    
    // DST end: 1st Sunday in November at 6:00 AM UTC
    final dstEnd = DateTime.utc(year, 11, findNthSunday(year, 11, 1).day, 6);

    // Determine if we're in DST
    bool isDST = nowUtc.isAfter(dstStart) && nowUtc.isBefore(dstEnd);
    
    // Convert to Eastern Time (EST = UTC-5, EDT = UTC-4)
    final easternTime = nowUtc.add(Duration(hours: isDST ? -4 : -5));
    final hour = easternTime.hour;

    if (hour >= 0 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  String _getNameFromEmail(String email) {
    if (email.contains('@')) {
      return email.split('@')[0];
    }
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

  Stream<int> _activeMembersStream() {
    return _fs
        .collection('client_purchases')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((purchasesSnap) async {
      final activeUserIds = <String>{};
      for (var doc in purchasesSnap.docs) {
        final data = doc.data();
        final userId = data.containsKey('userId') ? (data['userId'] as String?) : null;
        if (userId != null) activeUserIds.add(userId);
      }
      return activeUserIds.length;
    });
  }

  Future<_ActiveData> _fetchActiveMembers() async {
    try {
      final purchasesSnap = await _fs.collection('client_purchases').where('status', isEqualTo: 'active').get();

      final activeUserIds = <String>{};
      for (var doc in purchasesSnap.docs) {
        final data = doc.data();
        final userId = data.containsKey('userId') ? (data['userId'] as String?) : null;
        if (userId != null) activeUserIds.add(userId);
      }

      final activeMembers = activeUserIds.length;

      final usersSnap = await _fs.collection('users').where('role', isEqualTo: 'client').get();
      final totalClients = usersSnap.docs.length;

      return _ActiveData(active: activeMembers, total: totalClients);
    } catch (e) {
      debugPrint('Error fetching active members: $e');
      return _ActiveData(active: 0, total: 0);
    }
  }

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
    final double appBarExpandedHeight = MediaQuery.of(context).size.height * 0.24;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: appBarExpandedHeight,
            backgroundColor: const Color(0xFF1C2D5E),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              image: _profileImage != null
                                  ? DecorationImage(image: FileImage(_profileImage!), fit: BoxFit.cover)
                                  : null,
                              color: _profileImage == null ? Colors.grey[300] : null,
                            ),
                            child: _profileImage == null
                                ? const Icon(Icons.person, size: 26, color: Colors.grey)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickProfileImage,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, size: 12, color: Color(0xFF1C2D5E)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 4),

                            /// 🔑 Updated: Admin name comes live from Firestore now
                            if (user != null)
                              StreamBuilder<DocumentSnapshot>(
                                stream: _fs.collection('users').doc(user.uid).snapshots(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data!.exists) {
                                    final data = snapshot.data!.data() as Map<String, dynamic>;
                                    final liveName = data['name'] ?? adminName;
                                    return Text(
                                      liveName.toString().isNotEmpty
                                          ? '${liveName.toString()[0].toUpperCase()}${liveName.toString().substring(1)}'
                                          : adminName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  }
                                  // fallback while loading
                                  return Text(
                                    adminName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
                              )
                            else
                              Text(
                                adminName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),

                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white, size: 26),
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<int>(
                        stream: _activeMembersStream(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return _buildPieChartCard(
                              title: 'Active Members',
                              value: '—',
                              subtitle: 'Active',
                              percentage: 0,
                              color: Colors.blue,
                            );
                          }
                          final activeCount = snap.data!;

                          return FutureBuilder<QuerySnapshot>(
                            future: _fs.collection('users').where('role', isEqualTo: 'client').get(),
                            builder: (context, usersSnap) {
                              final totalClients = usersSnap.data?.docs.length ?? 0;
                              final pct = totalClients == 0 ? 0.0 : (activeCount / totalClients).clamp(0.0, 1.0);

                              return _buildPieChartCard(
                                title: 'Active Members',
                                value: activeCount.toString(),
                                subtitle: 'Active',
                                percentage: pct,
                                color: Colors.blue,
                              );
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 16),
                    Expanded(
                      child: StreamBuilder<int>(
                        stream: _bookedThisWeekStream(),
                        builder: (context, snap) {
                          final booked = snap.data ?? 0;
                          final pct = _totalSlotsThisWeek == 0 ? 0.0 : (booked / _totalSlotsThisWeek).clamp(0.0, 1.0);
                          return _buildPieChartCard(
                            title: 'Schedule Slots',
                            value: booked.toString(),
                            subtitle: 'Booked',
                            percentage: pct,
                            color: Colors.green,
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    _buildNavTile(
                      context,
                      Icons.calendar_today,
                      'Trainer Schedule',
                      const AdminCreateSlotsScreen(),
                      iconColor: Colors.blue,
                    ),
                    _buildNavTile(
                      context,
                      Icons.people,
                      'Client List',
                      const ClientListScreen(),
                      iconColor: Colors.purple,
                    ),
                    _buildNavTile(
                      context,
                      FontAwesomeIcons.dollarSign,
                      'Revenue Report',
                      const RevenueReportScreen(),
                      iconColor: Colors.green,
                    ),
                    _buildNavTile(
                      context,
                      FontAwesomeIcons.dumbbell,
                      'Workout Plans',
                      null,
                      iconColor: Colors.orange,
                      action: () {
                        Navigator.pushNamed(context, '/adminWorkoutMulti', arguments: []);
                      },
                    ),
                    _buildNavTile(
                      context,
                      Icons.announcement,
                      'Announcements',
                      const PostAnnouncementScreen(),
                      iconColor: Colors.red,
                    ),
                    _buildNavTile(
                      context,
                      Icons.settings,
                      'Settings',
                      const AdminSettingsPage(),
                      iconColor: Colors.grey,
                    ),
                    _buildNavTile(
                      context,
                      Icons.list_alt,
                      'Plans',
                      const PlansScreen(),
                      iconColor: Colors.teal,
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChartCard({
    required String title,
    required String value,
    required String subtitle,
    required double percentage,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: CircularProgressIndicator(
                    value: percentage,
                    strokeWidth: 10,
                    backgroundColor: color.withOpacity(0.18),
                    color: color,
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    Color iconColor = Colors.blue,
  }) {
    return GestureDetector(
      onTap: targetScreen != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => targetScreen))
          : action,
      child: Container(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveData {
  final int active;
  final int total;
  _ActiveData({required this.active, required this.total});
}
