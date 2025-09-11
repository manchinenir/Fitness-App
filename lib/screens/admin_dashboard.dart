 import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'admin_create_slots.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_announcement.dart';
import 'client_list_screen.dart';
import 'RevenueReport_screen.dart';
import 'package:intl/intl.dart';
import 'settings.dart';
import 'package:image_picker/image_picker.dart'; // Added for image picker
import 'dart:io'; // Added for File handling
import 'package:shared_preferences/shared_preferences.dart'; // Added for getting admin name
import 'package:firebase_auth/firebase_auth.dart'; // Added for current user
import 'Admin_Plan_Screen.dart';
import 'dart:async';
class AdminDashboard extends StatefulWidget {
  final String userName;

  const AdminDashboard({super.key, required this.userName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _fs = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker(); // Added image picker instance
  File? _profileImage; // Added to store selected profile image
  String adminName = 'Admin'; // Added to store admin name

  final Map<String, List<Map<String, String>>> availabilityMap = const {
    'Monday':     [{'start': '05:30', 'end': '11:00'}, {'start': '16:30', 'end': '19:00'}],
    'Tuesday':    [{'start': '05:30', 'end': '09:00'}, {'start': '16:30', 'end': '19:00'}],
    'Wednesday':  [{'start': '05:30', 'end': '09:00'}, {'start': '16:30', 'end': '19:00'}],
    'Thursday':   [{'start': '05:30', 'end': '09:00'}, {'start': '16:30', 'end': '19:00'}],
    'Friday':     [{'start': '05:30', 'end': '11:00'}],
    'Saturday':   [{'start': '05:30', 'end': '11:00'}],
    'Sunday':     [{'start': '05:30', 'end': '11:00'}],
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
    _loadAdminName(); // Added to load admin name
  }

  // Added method to load admin name from SharedPreferences or Firestore
  Future<void> _loadAdminName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedName = prefs.getString('admin_name');
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
          final name = doc.data()?['name'] as String?;
          if (name != null && name.isNotEmpty) {
            setState(() {
              adminName = name;
            });
            await prefs.setString('admin_name', name);
            return;
          }
        }
      }
      if (adminName == 'Admin' && widget.userName.isNotEmpty) {
        setState(() {
          adminName = _getNameFromEmail(widget.userName);
        });
      }
    } catch (e) {
      print('Error loading admin name: $e');
      if (widget.userName.isNotEmpty) {
        setState(() {
          adminName = _getNameFromEmail(widget.userName);
        });
      }
    }
  }

  // Added method to get greeting based on US timezone
  String _getGreeting() {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 5)); // EST/EDT approx
    final hour = now.hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  // Added method to extract name from email
  String _getNameFromEmail(String email) {
    if (email.contains('@')) {
      return email.split('@')[0];
    }
    return email;
  }

  // Added method to handle profile image selection
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
      print('Error picking image: $e');
    }
  }
  Stream<int> _activeMembersStream() {
    return _fs
        .collection('client_purchases')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((purchasesSnap) async {
          // Collect unique active userIds
          final activeUserIds = <String>{};
          for (var doc in purchasesSnap.docs) {
            final userId = doc.data()['userId'] as String?;
            if (userId != null) activeUserIds.add(userId);
          }

          // Only count unique users
          return activeUserIds.length;
        });
  }

  Future<_ActiveData> _fetchActiveMembers() async {
    try {
      // Fetch all client purchases where status is active
      final purchasesSnap = await _fs
          .collection('client_purchases')
          .where('status', isEqualTo: 'active')
          .get();

      // Extract unique userIds from active purchases
      final activeUserIds = <String>{};
      for (var doc in purchasesSnap.docs) {
        final userId = doc.data()['userId'] as String?;
        if (userId != null) {
          activeUserIds.add(userId);
        }
      }

      // Active members = number of unique users with at least one active plan
      final activeMembers = activeUserIds.length;

      // Total clients (for percentage calculation) = all users with role client
      final usersSnap = await _fs
          .collection('users')
          .where('role', isEqualTo: 'client')
          .get();

      final totalClients = usersSnap.docs.length;

      return _ActiveData(active: activeMembers, total: totalClients);
    } catch (e) {
      print('Error fetching active members: $e');
      return _ActiveData(active: 0, total: 0);
    }
  }

  Stream<int> _bookedThisWeekStream() {
    final q = _fs.collection('trainer_slots')
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_weekStart))
      .where('date', isLessThan: Timestamp.fromDate(_nextWeekStart))
      .snapshots();
    return q.map((snap) {
      int total = 0;
      for (final d in snap.docs) {
        total += (d.data()['booked'] ?? 0) as int;
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
        total += _hourSlotsInBlock(b['start']!, b['end']!, day);
      }
    }
    return total;
  }

  int _hourSlotsInBlock(String start, String end, DateTime day) {
    final fmt = DateFormat('HH:mm');
    DateTime s = DateTime(day.year, day.month, day.day,
        fmt.parse(start).hour, fmt.parse(start).minute);
    final e = DateTime(day.year, day.month, day.day,
        fmt.parse(end).hour, fmt.parse(end).minute);
    int count = 0;
    while (s.isBefore(e)) {
      s = s.add(const Duration(hours: 1));
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: MediaQuery.of(context).size.height * 0.3,
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              image: _profileImage != null
                                  ? DecorationImage(
                                      image: FileImage(_profileImage!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: _profileImage == null ? Colors.grey[300] : null,
                            ),
                            child: _profileImage == null
                                ? const Icon(Icons.person, size: 28, color: Colors.grey)
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
                              style: const TextStyle(color: Colors.white70, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Hi, $adminName',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
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

                          // For percentage calculation, fetch total clients
                          return FutureBuilder<QuerySnapshot>(
                            future: _fs.collection('users').where('role', isEqualTo: 'client').get(),
                            builder: (context, usersSnap) {
                              final totalClients = usersSnap.data?.docs.length ?? 0;
                              final pct = totalClients == 0
                                  ? 0.0
                                  : (activeCount / totalClients).clamp(0.0, 1.0);

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
                          final pct = _totalSlotsThisWeek == 0
                              ? 0.0
                              : (booked / _totalSlotsThisWeek).clamp(0.0, 1.0);
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
                const SizedBox(height: 24),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: percentage,
                    strokeWidth: 10,
                    backgroundColor: color.withOpacity(0.2),
                    color: color,
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 24,
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
              color: Colors.grey.withOpacity(0.1),
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