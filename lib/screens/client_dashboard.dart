import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';

import 'client_book_slot.dart';
import 'client_plans_screen.dart';
import 'schedule_screen.dart';
import 'post_announcement.dart';
import 'profileScreen.dart';

// Dashboard menu item model
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
  const ClientDashboard({Key? key}) : super(key: key);

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  String firstName = '';
  String? firestorePhotoUrl;
  File? localImageFile;

  bool isLoading = true;
  String? errorMessage;

  int completedSessions = 0;
  String? nextUpcomingSessionTime;

  StreamSubscription<QuerySnapshot>? _sessionsSubscription;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _fetchUserProfile();
        _setupSessionsListener();
      }
    });

    _fetchUserProfile();
    _setupSessionsListener();

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${message.notification!.title}: ${message.notification!.body}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.blueAccent,
        ));
      }
    });
  }

  @override
  void dispose() {
    _sessionsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _setupSessionsListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sessionsSubscription?.cancel();

    _sessionsSubscription = FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('booked_by', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      final now = DateTime.now();
      int completed = 0;
      List<Map<String, dynamic>> upcoming = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['date'] is! Timestamp) continue;
        final date = (data['date'] as Timestamp).toDate().toLocal();
        final timeRange = data['time'] as String? ?? '';
        if (date.isBefore(now)) {
          completed++;
        } else {
          upcoming.add({'date': date, 'time': timeRange});
        }
      }
      String? nextInfo;
      if (upcoming.isNotEmpty) {
        upcoming.sort((a, b) =>
            (a['date'] as DateTime).compareTo(b['date'] as DateTime));
        final next = upcoming.first;
        final dt = next['date'] as DateTime;
        final dateStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        nextInfo = '$dateStr – ${next['time']}';
      }
      if (mounted) {
        setState(() {
          completedSessions = completed;
          nextUpcomingSessionTime = nextInfo ?? 'No upcoming session';
        });
      }
    });
  }

  Future<void> _fetchUserProfile() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Not authenticated';

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final name = doc.data()?['name'] as String? ?? '';
      final photoUrl = doc.data()?['photoUrl'] as String?;

      setState(() {
        firstName = name.split(' ').first;
        firestorePhotoUrl = photoUrl;
        localImageFile = null;
      });
    } catch (e) {
      setState(() => errorMessage = 'Error loading user: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final file = File(picked.path);
      setState(() => localImageFile = file);

      await _uploadProfilePhoto(file);
      await _fetchUserProfile();
    }
  }

  Future<void> _uploadProfilePhoto(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Not authenticated';

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('${user.uid}.jpg');

      await storageRef.putFile(file);

      final url = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'photoUrl': url});
    } catch (e) {
      // Optional: display error or log
      debugPrint('Photo upload error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ImageProvider<Object>? avatarImage;
    if (localImageFile != null) {
      avatarImage = FileImage(localImageFile!);
    } else if (firestorePhotoUrl != null) {
      avatarImage = NetworkImage(firestorePhotoUrl!);
    } else {
      avatarImage = null;
    }

    if (isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _fetchUserProfile();
                  },
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
      body: RefreshIndicator(
        onRefresh: () async => _fetchUserProfile(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              backgroundColor: const Color(0xFF1C2D5E),
              expandedHeight: 240,
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Padding(
                  padding: const EdgeInsets.only(top: 80, left: 16, right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.white24,
                                backgroundImage: avatarImage,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _pickImage,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 20,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back,',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                firstName,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 28,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        icon: Icons.fitness_center,
                        label: 'Active Plans',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('client_purchases')
                              .where(
                                'userId',
                                isEqualTo: FirebaseAuth.instance.currentUser!.uid,
                              )
                              .snapshots(),
                          builder: (context, snap) {
                            final count = snap.hasData ? snap.data!.docs.length : 0;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  'Active Plans',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        icon: Icons.calendar_today,
                        label: 'Upcoming',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                nextUpcomingSessionTime ?? 'No upcoming session',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Upcoming Session',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        icon: Icons.star,
                        label: 'Completed',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFff7e5f), Color(0xFFfeb47b)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$completedSessions',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Completed',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .snapshots(),
                builder: (context, snap) {
                  final hasNew = snap.hasData && snap.data!.data()?['hasNewWorkout'] == true;
                  final items = [
                    DashboardItem(
                      icon: Icons.schedule,
                      label: 'My Schedule',
                      color: Colors.blue,
                      targetScreen: const MySchedulePage(),
                    ),
                    DashboardItem(
                      icon: Icons.date_range,
                      label: 'Book Session',
                      color: Colors.purple,
                      targetScreen: const ClientBookSlot(),
                    ),
                    DashboardItem(
                      icon: FontAwesomeIcons.dollarSign,
                      label: 'Plans',
                      color: Colors.green,
                      targetScreen: const ClientPlansScreen(),
                    ),
                    DashboardItem(
                      icon: FontAwesomeIcons.dumbbell,
                      label: 'Workouts',
                      color: Colors.orange,
                      showBadge: hasNew,
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
                      label: 'Profile',
                      color: Colors.red,
                      targetScreen: const ProfileScreen(),
                    ),
                    DashboardItem(
                      icon: Icons.announcement,
                      label: 'Announcements',
                      color: Colors.teal,
                      targetScreen: const PostAnnouncementScreen(),
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
                      (context, i) => _actionCard(items[i]),
                      childCount: items.length,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required Gradient gradient,
    required Widget child,
  }) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 6,
            right: 6,
            child: Icon(
              icon,
              size: 36,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          Center(child: child),
        ],
      ),
    );
  }

  Widget _actionCard(DashboardItem item) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (item.targetScreen != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => item.targetScreen!),
            );
          } else {
            item.action?.call();
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                item.color.withOpacity(0.15),
                item.color.withOpacity(0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  item.icon,
                  size: 40,
                  color: item.color.withOpacity(0.15),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.icon, color: item.color, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (item.showBadge)
                const Positioned(
                  top: 8,
                  left: 8,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.red,
                    child: Text('!',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}