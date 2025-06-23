// admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'admin_create_slots.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'client_list_screen.dart';


class AdminDashboard extends StatelessWidget {
  final String userName;

  const AdminDashboard({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
appBar: AppBar(
  backgroundColor: const Color(0xFF1C2D5E),
  automaticallyImplyLeading: false,
  title: Text(
    'Hi, $userName',
    style: const TextStyle(color: Colors.white),
  ),
  actions: [
    IconButton(
      icon: const Icon(Icons.logout, color: Colors.white),
      onPressed: () async {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      },
    )
  ],
),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildPieCard("Active Members", ["Active", "Inactive"], [70, 30], [Colors.indigo, Colors.grey]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPieCard("Schedule Slots", ["Booked", "Available"], [45, 15], [Colors.green, Colors.red]),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildNavTile(context, Icons.calendar_today, 'Trainer Schedule', const AdminCreateSlotsScreen()),
                _buildNavTile(context, Icons.people, 'Client List', const ClientListScreen()),
                _buildNavTile(context, FontAwesomeIcons.dollarSign, 'Revenue Report', null),
                _buildNavTile(
                  context,
                  FontAwesomeIcons.dumbbell, 
                  'Workout Plans', null,
                  action: () {
                    // Navigate to workout page with empty client list or a fallback
                    Navigator.pushNamed(context, '/adminWorkoutMulti', arguments: []);
                  },
                ),
                _buildNavTile(context, Icons.announcement, 'Announcements', null),
                _buildNavTile(context, Icons.settings, 'Settings', null),
                _buildNavTile(context, Icons.upload, 'Upload Slots', null, action: () async {
                  await uploadTrainerSlots(context);
                }),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPieCard(String title, List<String> labels, List<double> values, List<Color> colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Stack(
              children: [
                Center(
                  child: SizedBox(
                    height: 100,
                    width: 100,
                    child: CircularProgressIndicator(
                      value: values[0] / (values[0] + values[1]),
                      backgroundColor: colors[1],
                      color: colors[0],
                      strokeWidth: 10,
                    ),
                  ),
                ),
                Center(
                  child: Text('${values[0].toInt()} ${labels[0]}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildNavTile(BuildContext context, IconData icon, String label, Widget? targetScreen, {VoidCallback? action}) {
    return GestureDetector(
      onTap: targetScreen != null
          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => targetScreen))
          : action,
      child: Container(
        width: MediaQuery.of(context).size.width / 2 - 24,
        height: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: const Color(0xFF1C2D5E)),

            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}


Future<void> uploadTrainerSlots(BuildContext context) async {
  final firestore = FirebaseFirestore.instance;
  final today = DateTime.now();
  final Map<int, List<List<String>>> schedule = {
    1: [['5:30', '11:00']],
    5: [['5:30', '11:00']],
    6: [['5:30', '11:00']],
    7: [['5:30', '11:00']],
    2: [['5:30', '9:00'], ['16:30', '19:00']],
    3: [['5:30', '9:00'], ['16:30', '19:00']],
    4: [['5:30', '9:00'], ['16:30', '19:00']],
  };

  try {
    for (int i = 0; i < 14; i++) {
      final date = today.add(Duration(days: i));
      final weekday = date.weekday;
      if (!schedule.containsKey(weekday)) continue;

      final slots = schedule[weekday]!;
      for (final pair in slots) {
        final start = _parseTime(pair[0]);
        final end = _parseTime(pair[1]);

        DateTime current = DateTime(date.year, date.month, date.day, start.hour, start.minute);
        final endTime = DateTime(date.year, date.month, date.day, end.hour, end.minute);

        while (current.isBefore(endTime)) {
          final slotId = '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}';
          await firestore.collection('trainer_slots').doc('${date.year}-${date.month}-${date.day}').collection('time_slots').doc(slotId).set({
            'time': slotId,
            'capacity': 6,
            'bookedBy': [],
            'status': 'available',
          });
          current = current.add(const Duration(minutes: 30));
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trainer slots uploaded!")));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error uploading: \$e")));
  }
}

TimeOfDay _parseTime(String time) {
  final parts = time.split(":");
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}
