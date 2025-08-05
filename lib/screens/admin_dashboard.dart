import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'admin_create_slots.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post_announcement.dart';
import 'client_list_screen.dart';
import 'RevenueReport_screen.dart';

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
          'HI, ${userName.isNotEmpty ? userName : 'Admin'}',
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 24, 
            fontWeight: FontWeight.bold
          ),
        ),
        centerTitle: true,
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
          children: [
            // Stats Row with Pie Charts
            Row(
              children: [
                Expanded(
                  child: _buildPieChartCard(
                    title: 'Active Members',
                    value: '70',
                    subtitle: 'Active',
                    percentage: 0.7,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPieChartCard(
                    title: 'Schedule Slots',
                    value: '45',
                    subtitle: 'Booked',
                    percentage: 0.75,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Navigation Grid
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
                  null,
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
            Icon(
              icon,
              size: 32,
              color: iconColor,
            ),
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