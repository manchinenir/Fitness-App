import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import 'client_book_slot.dart';
import 'client_plans_screen.dart';
import 'schedule_screen.dart';
import 'booking_confirmation_page.dart';

class DashboardItem {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? targetScreen;
  final VoidCallback? action;
  final bool showBadge;

  DashboardItem({
    required this.icon,
    required this.label,
    required this.color,
    this.targetScreen,
    this.action,
    this.showBadge = false,
  });
}

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  String firstName = '';
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('User not authenticated');

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) throw Exception('User document not found');

      final fullName = doc.data()?['name']?.toString() ?? '';
      setState(() {
        firstName = fullName.split(' ').first;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load user data: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    if (isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _fetchUserName,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: theme.primaryColor,
            expandedHeight: size.height * 0.2,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Dashboard',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.primaryColor,
                      theme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.logout, color: theme.colorScheme.onPrimary),
                onPressed: () => _confirmLogout(context),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back,',
                    style: TextStyle(
                      fontSize: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    firstName,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildStatCard(
                          context,
                          icon: Icons.fitness_center,
                          value: '5',
                          label: 'Active Plans',
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          context,
                          icon: Icons.calendar_today,
                          value: '2',
                          label: 'Upcoming Sessions',
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          context,
                          icon: Icons.star,
                          value: '12',
                          label: 'Completed',
                          color: Colors.orangeAccent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final hasNewWorkout = snapshot.hasData &&
                    snapshot.data!.exists &&
                    (snapshot.data!.data() as Map<String, dynamic>)['hasNewWorkout'] == true;

                final dashboardItems = [
                  DashboardItem(
                    icon: Icons.schedule,
                    label: 'My Schedule',
                    color: Colors.blue.shade400,
                    targetScreen: const MySchedulePage(),
                  ),
                  DashboardItem(
                    icon: Icons.calendar_today,
                    label: 'Book Session',
                    color: Colors.purple.shade400,
                    targetScreen: const ClientBookSlot(),
                  ),
                  DashboardItem(
                    icon: FontAwesomeIcons.dollarSign,
                    label: 'Plans',
                    color: Colors.green.shade400,
                    targetScreen: ClientPlansScreen(), // fixed: removed const
                  ),
                  DashboardItem(
                    icon: FontAwesomeIcons.dumbbell,
                    label: 'Workouts',
                    color: Colors.orange.shade400,
                    showBadge: hasNewWorkout,
                    action: () async {
                      Navigator.pushNamed(context, '/clientWorkout');
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .update({'hasNewWorkout': false});
                    },
                  ),
                  DashboardItem(
                    icon: Icons.person,
                    label: 'My Profile',
                    color: Colors.red.shade400,
                    action: () {}, // add navigation if needed
                  ),
                  DashboardItem(
                    icon: Icons.announcement,
                    label: 'Announcements',
                    color: Colors.teal.shade400,
                    action: () {}, // add navigation if needed
                  ),
                ];

                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildDashboardCard(context, dashboardItems[index]),
                    childCount: dashboardItems.length,
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 14, color: color.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, DashboardItem item) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (item.targetScreen != null) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => item.targetScreen!));
          } else if (item.action != null) {
            item.action!();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [item.color.withOpacity(0.2), item.color.withOpacity(0.05)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: 8,
                top: 8,
                child: Icon(item.icon, size: 60, color: item.color.withOpacity(0.1)),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(item.icon, size: 28, color: item.color),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(height: 2, width: 24, color: item.color),
                      ],
                    ),
                  ],
                ),
              ),
              if (item.showBadge)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: const Text('!', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }
}
