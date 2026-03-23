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
import 'active_members_screen.dart';

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
    _loadAdminName();
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

    final isActive = data['isActive'] == true;
    if (!isActive) return false;

    final endDate = data['endDate'];
    if (endDate == null) return true;

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
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        'Dashboard',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome back,',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
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
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white, size: 26),
                onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    // Active Members Card with Professional Gradient
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _fs
                            .collection('client_purchases')
                            .where('status', isEqualTo: 'active')
                            .snapshots(),
                        builder: (context, purchasesSnap) {
                          if (purchasesSnap.connectionState == ConnectionState.waiting) {
                            return _buildProfessionalCard(
                              title: 'Active Members',
                              value: '—',
                              subtitle: 'Loading',
                              percentage: 0,
                              gradient1: const Color(0xFF4158D0),
                              gradient2: const Color(0xFFC850C0),
                            );
                          }
                          if (purchasesSnap.hasError) {
                            return _buildProfessionalCard(
                              title: 'Active Members',
                              value: '0',
                              subtitle: 'Error',
                              percentage: 0,
                              gradient1: const Color(0xFF4158D0),
                              gradient2: const Color(0xFFC850C0),
                            );
                          }

                          final activePurchaseUsers = <String>{};
                          for (final d in (purchasesSnap.data?.docs ?? [])) {
                            final m = d.data() as Map<String, dynamic>;
                            if (_isCurrentlyActive(m)) {
                              final uid = (m['userId'] ?? '').toString();
                              if (uid.isNotEmpty) activePurchaseUsers.add(uid);
                            }
                          }

                          return StreamBuilder<QuerySnapshot>(
                            stream: _fs
                                .collection('client_subscriptions')
                                .where('status', isEqualTo: 'active')
                                .snapshots(),
                            builder: (context, subsSnap) {
                              if (subsSnap.connectionState == ConnectionState.waiting) {
                                return _buildProfessionalCard(
                                  title: 'Active Members',
                                  value: '—',
                                  subtitle: 'Loading',
                                  percentage: 0,
                                  gradient1: const Color(0xFF4158D0),
                                  gradient2: const Color(0xFFC850C0),
                                );
                              }
                              if (subsSnap.hasError) {
                                return _buildProfessionalCard(
                                  title: 'Active Members',
                                  value: activePurchaseUsers.length.toString(),
                                  subtitle: 'of —',
                                  percentage: 0,
                                  gradient1: const Color(0xFF4158D0),
                                  gradient2: const Color(0xFFC850C0),
                                );
                              }

                              final usersWithSubs = <String>{};
                              for (final d in (subsSnap.data?.docs ?? [])) {
                                final m = d.data() as Map<String, dynamic>;
                                if (_isSubscriptionActive(m)) {
                                  final uid = (m['userId'] ?? '').toString();
                                  if (uid.isNotEmpty) usersWithSubs.add(uid);
                                }
                              }

                              final activeUsersUnion = <String>{}
                                ..addAll(activePurchaseUsers)
                                ..addAll(usersWithSubs);

                              return FutureBuilder<QuerySnapshot>(
                                future: _fs.collection('users').where('role', isEqualTo: 'client').get(),
                                builder: (context, usersSnap) {
                                  final totalClients = usersSnap.data?.docs.length ?? 0;
                                  final activeCount = activeUsersUnion.length;
                                  final pct = totalClients == 0
                                      ? 0.0
                                      : (activeCount / totalClients).clamp(0.0, 1.0);

                                  return InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const ActiveMembersScreen()),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: _buildProfessionalCard(
                                      title: 'Active Members',
                                      value: activeCount.toString(),
                                      subtitle: totalClients > 0 ? 'of $totalClients' : 'Active',
                                      percentage: pct,
                                      gradient1: const Color(0xFF4158D0),
                                      gradient2: const Color(0xFFC850C0),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Schedule Slots Card with Professional Gradient
                    Expanded(
                      child: StreamBuilder<int>(
                        stream: _bookedThisWeekStream(),
                        builder: (context, snap) {
                          final booked = snap.data ?? 0;
                          final pct = _totalSlotsThisWeek == 0 ? 0.0 : (booked / _totalSlotsThisWeek).clamp(0.0, 1.0);

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ScheduleSlotsDetailScreen(
                                    weekStart: _weekStart,
                                    nextWeekStart: _nextWeekStart,
                                  ),
                                ),
                              );
                            },
                            child: _buildProfessionalCard(
                              title: 'Schedule Slots',
                              value: booked.toString(),
                              subtitle: 'Booked',
                              percentage: pct,
                              gradient1: const Color(0xFF0093E9),
                              gradient2: const Color(0xFF80D0C7),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Navigation Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.2,
                  children: [
                    _buildNavTile(
                      icon: Icons.calendar_today,
                      label: 'Trainer Schedule',
                      color: Colors.blue,
                      targetScreen: const AdminCreateSlotsScreen(),
                    ),
                    _buildNavTile(
                      icon: Icons.people,
                      label: 'Client List',
                      color: Colors.purple,
                      targetScreen: const ClientListScreen(),
                    ),
                    _buildNavTile(
                      icon: FontAwesomeIcons.dollarSign,
                      label: 'Revenue Report',
                      color: Colors.green,
                      targetScreen: const RevenueReportScreen(),
                    ),
                    _buildNavTile(
                      icon: FontAwesomeIcons.dumbbell,
                      label: 'Workout Plans',
                      color: Colors.orange,
                      action: () {
                        Navigator.pushNamed(context, '/adminWorkoutMulti', arguments: []);
                      },
                    ),
                    _buildNavTile(
                      icon: Icons.announcement,
                      label: 'Announcements',
                      color: Colors.red,
                      targetScreen: const PostAnnouncementScreen(),
                    ),
                    _buildNavTile(
                      icon: Icons.settings,
                      label: 'Settings',
                      color: Colors.grey,
                      targetScreen: const AdminSettingsPage(),
                    ),
                    _buildNavTile(
                      icon: Icons.list_alt,
                      label: 'Plans',
                      color: Colors.teal,
                      targetScreen: const PlansScreen(),
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

  // Professional Card with gradient background and matching circular progress
  Widget _buildProfessionalCard({
    required String title,
    required String value,
    required String subtitle,
    required double percentage,
    required Color gradient1,
    required Color gradient2,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradient1, gradient2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradient1.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: gradient2.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer decorative circle with gradient
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Progress indicator with gradient colors
                SizedBox(
                  width: 74,
                  height: 74,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: percentage),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        backgroundColor: Colors.white.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white, // White for better contrast
                        ),
                      );
                    },
                  ),
                ),
                // Center text
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.2),
                            offset: const Offset(1, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
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

  // Navigation Tile
  Widget _buildNavTile({
    required IconData icon,
    required String label,
    required Color color,
    Widget? targetScreen,
    VoidCallback? action,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: targetScreen != null
            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => targetScreen))
            : action,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.15),
                color.withOpacity(0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              // Background icon
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  icon,
                  size: 40,
                  color: color.withOpacity(0.15),
                ),
              ),
              // Content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Schedule Slots Detail Screen (unchanged) =====
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

  @override
  void initState() {
    super.initState();
    _fetchSlots();
  }

  Future<void> _fetchSlots() async {
    try {
      final querySnapshot = await _fs
          .collection('trainer_slots')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(widget.weekStart))
          .where('date', isLessThan: Timestamp.fromDate(widget.nextWeekStart))
          .get();

      List<SlotDetail> slots = [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final fmt = DateFormat('HH:mm');

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final Timestamp dateTimestamp = data['date'];
        final DateTime date = dateTimestamp.toDate();
        final String time = data['time'] ?? '00:00';
        final int booked = data['booked'] ?? 0;

        if (booked > 0) {
          final timeParts = time.split(' - ');
          final startTimeStr = timeParts.isNotEmpty ? timeParts[0] : '00:00';
          String endTimeStr = timeParts.length > 1 ? timeParts[1] : '';
          if (endTimeStr.isEmpty) {
            final startParsed = fmt.parse(startTimeStr);
            final nextHour = startParsed.add(const Duration(hours: 1));
            endTimeStr = DateFormat('HH:mm').format(nextHour);
          }

          String status;
          if (date.isBefore(today)) {
            status = 'COMPLETED';
          } else if (date.isAfter(today)) {
            status = 'UPCOMING';
          } else {
            status = 'TODAY';
          }

          slots.add(SlotDetail(
            date: date,
            startTime: startTimeStr,
            endTime: endTimeStr,
            booked: booked,
            status: status,
            bookedNames: List<String>.from(data['booked_names'] ?? []),
          ));
        }
      }

      slots.sort((a, b) {
        final orderA = _getOrder(a.status);
        final orderB = _getOrder(b.status);
        if (orderA != orderB) return orderA.compareTo(orderB);
        final aDateTime = _parseSlotDateTime(a);
        final bDateTime = _parseSlotDateTime(b);
        if (a.status == 'COMPLETED') {
          return bDateTime.compareTo(aDateTime);
        } else {
          return aDateTime.compareTo(bDateTime);
        }
      });

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
    final timeFormat = DateFormat('HH:mm');
    final time = timeFormat.parse(slot.startTime);
    return DateTime(
      slot.date.year,
      slot.date.month,
      slot.date.day,
      time.hour,
      time.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Slots Details'),
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
                  itemCount: _slots.length,
                  itemBuilder: (context, index) {
                    final slot = _slots[index];
                    return _buildSlotCard(slot);
                  },
                ),
    );
  }

  Widget _buildSlotCard(SlotDetail slot) {
    final dayFormat = DateFormat('EEEE, MMMM d');
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
            color: Colors.grey.withOpacity(0.08),
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
                  color: badgeColor.withOpacity(0.2),
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dayFormat.format(slot.date),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, color: Color(0xFF1C2D5E), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${slot.startTime} - ${slot.endTime}',
                  style: const TextStyle(fontSize: 15),
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
                    'Clients: ${slot.bookedNames.join(', ')}',
                    style: const TextStyle(fontSize: 15),
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