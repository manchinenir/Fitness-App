import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'admin_create_slots.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_announcement.dart';
import 'client_list_screen.dart';
import 'RevenueReport_screen.dart';
import 'package:intl/intl.dart';
import 'settings.dart';

class AdminDashboard extends StatefulWidget {
  final String userName;

  const AdminDashboard({super.key, required this.userName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _fs = FirebaseFirestore.instance;

  // Same availability map you use elsewhere (hourly blocks)
  final Map<String, List<Map<String, String>>> availabilityMap = const {
    'Monday':     [{'start': '05:30', 'end': '11:00'}, {'start': '16:30', 'end': '19:00'}],
    'Tuesday':    [{'start': '05:30', 'end': '09:00'}, {'start': '16:30', 'end': '19:00'}],
    'Wednesday':  [{'start': '05:30', 'end': '09:00'}, {'start': '16:30', 'end': '19:00'}],
    'Thursday':   [{'start': '05:30', 'end': '09:00'}, {'start': '16:30', 'end': '19:00'}],
    'Friday':     [{'start': '05:30', 'end': '11:00'}],
    'Saturday':   [{'start': '05:30', 'end': '11:00'}],
    'Sunday':     [{'start': '05:30', 'end': '11:00'}],
  };

  late final DateTime _weekStart;          // this Monday 00:00
  late final DateTime _nextWeekStart;      // next Monday 00:00
  late final int _totalSlotsThisWeek;      // denominator for donut

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = _mondayStart(now);
    _nextWeekStart = _weekStart.add(const Duration(days: 7));
    _totalSlotsThisWeek = _totalSlotsForWeek(_weekStart, availabilityMap);
  }

  // ---------- Active members once (future) ----------
  Future<_ActiveData> _fetchActiveMembers() async {
    final now = DateTime.now();

    // Choose the rule that matches your schema:
    // A) planActive == true
    // final active = (await _fs.collection('users')
    //   .where('planActive', isEqualTo: true).get()).docs.length;

    // B) plan_end >= now (Timestamp)
    final active = (await _fs.collection('users')
        .where('plan_end', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .get()).docs.length;

    final total = (await _fs.collection('users').get()).docs.length;
    return _ActiveData(active: active, total: total);
  }

  // ---------- Schedule slots live (stream) ----------
  Stream<int> _bookedThisWeekStream() {
    final q = _fs.collection('trainer_slots')
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_weekStart))
      .where('date', isLessThan: Timestamp.fromDate(_nextWeekStart))
      .snapshots();

    // Sum "booked" across docs in this week
    return q.map((snap) {
      int total = 0;
      for (final d in snap.docs) {
        total += (d.data()['booked'] ?? 0) as int;
      }
      return total;

      // If you prefer "slots that have at least 1 booking":
      // return snap.docs.where((d) => ((d.data()['booked'] ?? 0) as int) > 0).length;
    });
  }

  // ---------- Helpers ----------
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2D5E),
        automaticallyImplyLeading: false,
        title: Text(
          'HI, ${widget.userName.isNotEmpty ? widget.userName : 'Admin'}',
          style: const TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ----- Stats Row: Active (Future) + Schedule (Stream) -----
            Row(
              children: [
                // Active Members (loads once)
                Expanded(
                  child: FutureBuilder<_ActiveData>(
                    future: _fetchActiveMembers(),
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
                      final d = snap.data!;
                      final pct = d.total == 0 ? 0.0 : (d.active / d.total).clamp(0.0, 1.0);
                      return _buildPieChartCard(
                        title: 'Active Members',
                        value: d.active.toString(),
                        subtitle: 'Active',
                        percentage: pct,
                        color: Colors.blue,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),

                // Schedule Slots (live)
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

            // ----- Navigation Grid (unchanged) -----
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
                  action: () {
                    // Add settings navigation here
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----- UI helpers (unchanged) -----
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
