import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'client_book_slot.dart';
import 'client_plans_screen.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  String firstName = '';
  bool isLoading = true;
  bool showWorkoutBadge = false;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _checkWorkoutBadge();
  }

  Future<void> _fetchUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final fullName = doc.data()?['name'] ?? '';
      setState(() {
        firstName = fullName.toString().split(' ').first;
        isLoading = false;
      });
    }
  }

  Future<void> _checkWorkoutBadge() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final hasNew = doc.data()?['hasNewWorkout'] ?? false;
      setState(() {
        showWorkoutBadge = hasNew;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<Map<String, dynamic>> navItems = [
      {
        'icon': Icons.schedule,
        'label': 'My Schedule',
        'target': null,
      },
      {
        'icon': Icons.calendar_today,
        'label': 'Book Session',
        'target': const ClientBookSlot(),
      },
      {
        'icon': FontAwesomeIcons.dollarSign,
        'label': 'Plans',
        'target': ClientPlansScreen(),
      },
      {
        'icon': FontAwesomeIcons.dumbbell,
        'label': 'Workouts',
        'onTap': () async {
          Navigator.pushNamed(context, '/clientWorkout');
          await FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .update({'hasNewWorkout': false});
          setState(() {
            showWorkoutBadge = false;
          });
        },
        'showBadge': showWorkoutBadge,
      },
      {
        'icon': Icons.person,
        'label': 'My Profile',
        'target': null,
      },
      {
        'icon': Icons.announcement,
        'label': 'Announcements',
        'target': null,
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2D5E),
        automaticallyImplyLeading: false,
        title: const Text(
          'Dashboard',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Welcome, $firstName',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C2D5E),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                itemCount: navItems.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 3 / 2,
                ),
                itemBuilder: (context, index) {
                  final item = navItems[index];
                  return _buildNavTile(
                    context,
                    item['icon'],
                    item['label'],
                    item['target'],
                    onTap: item['onTap'],
                    showBadge: item['showBadge'] ?? false,
                  );
                },
              ),
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
    VoidCallback? onTap,
    bool showBadge = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap ??
          (targetScreen != null
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => targetScreen))
              : null),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 30, color: const Color(0xFF1C2D5E)),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1C2D5E),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showBadge)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Text('!', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
