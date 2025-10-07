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

class DashboardItem {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? targetScreen;
  final VoidCallback? action;
  final bool showBadge;
  final bool enabled;

  DashboardItem({
    required this.icon,
    required this.label,
    required this.color,
    this.targetScreen,
    this.action,
    this.showBadge = false,
    this.enabled = true,
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
  StreamSubscription<DocumentSnapshot>? _profileListener;
  
  Map<String, bool> _tabDisabledStatus = {};

  @override
  void initState() {
    super.initState();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _fetchUserProfile();
        _setupSessionsListener();
        _setupProfileImageListener();
        _loadTabDisabledStatus();
      }
    });

    _fetchUserProfile();
    _setupSessionsListener();
    _setupProfileImageListener();
    _loadTabDisabledStatus();

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
    _profileListener?.cancel();
    super.dispose();
  }

  Future<void> _loadTabDisabledStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final disabledTabs = List<String>.from(doc.data()?['disabledTabs'] ?? []);
        
        setState(() {
          _tabDisabledStatus = {
            'schedule': disabledTabs.contains('schedule'),
            'booking': disabledTabs.contains('booking'),
            'plans': disabledTabs.contains('plans'),
            'workouts': disabledTabs.contains('workouts'),
            'profile': disabledTabs.contains('profile'),
            'announcements': disabledTabs.contains('announcements'),
          };
        });
      }
    } catch (e) {
      print('Error loading tab disabled status');
    }
  }

  void _setupProfileImageListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profileListener = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          setState(() {
            firestorePhotoUrl = snapshot.data()?['profileImage'];
          });
          
          final disabledTabs = List<String>.from(snapshot.data()?['disabledTabs'] ?? []);
          setState(() {
            _tabDisabledStatus = {
              'schedule': disabledTabs.contains('schedule'),
              'booking': disabledTabs.contains('booking'),
              'plans': disabledTabs.contains('plans'),
              'workouts': disabledTabs.contains('workouts'),
              'profile': disabledTabs.contains('profile'),
              'announcements': disabledTabs.contains('announcements'),
            };
          });
        }
      });
    }
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

    // Add listener for purchase changes to update active plans count
    FirebaseFirestore.instance
        .collection('client_purchases')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((_) {
      if (mounted) {
        setState(() {
          // This will trigger a rebuild of the active plans count StreamBuilder
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
      final photoUrl = doc.data()?['profileImage'] as String?;

      setState(() {
        firstName = name.split(' ').first;
        firestorePhotoUrl = photoUrl;
        localImageFile = null;
      });
      
      final disabledTabs = List<String>.from(doc.data()?['disabledTabs'] ?? []);
      setState(() {
        _tabDisabledStatus = {
          'schedule': disabledTabs.contains('schedule'),
          'booking': disabledTabs.contains('booking'),
          'plans': disabledTabs.contains('plans'),
          'workouts': disabledTabs.contains('workouts'),
          'profile': disabledTabs.contains('profile'),
          'announcements': disabledTabs.contains('announcements'),
        };
      });
    } catch (e) {
      setState(() => errorMessage = 'Error loading user');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final file = File(picked.path);
      setState(() => localImageFile = file);

      await _uploadProfileImage(file);
      await _fetchUserProfile();
    }
  }

  Future<bool> _isTabDisabled(String tabKey) async {
    return _tabDisabledStatus[tabKey] ?? false;
  }

  Future<void> _uploadProfileImage(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Not authenticated';

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');

      await storageRef.putFile(file);

      final url = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'profileImage': url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ImageProvider<Object>? avatarImage;
    if (localImageFile != null) {
      avatarImage = FileImage(localImageFile!);
    } else if (firestorePhotoUrl != null && firestorePhotoUrl!.isNotEmpty) {
      avatarImage = NetworkImage(firestorePhotoUrl!);
    } else {
      avatarImage = const AssetImage('assets/profile.jpg');
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
                                onBackgroundImageError: (exception, stackTrace) {
                                  setState(() {
                                    firestorePhotoUrl = null;
                                  });
                                },
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            icon: Icons.fitness_center,
                            label: 'Active Plans',
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2E8B57), Color(0xFF228B22)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('client_purchases')
                                  .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                                  .snapshots(),
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  return const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.error, color: Colors.white70, size: 20),
                                      SizedBox(height: 2),
                                      Text(
                                        'Error', 
                                        style: TextStyle(
                                          color: Colors.white70, 
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                
                                if (!snap.hasData) {
                                  return const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Loading...', 
                                        style: TextStyle(
                                          color: Colors.white70, 
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                int activeCount = 0;
                                
                                for (final doc in snap.data!.docs) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final isActive = data['isActive'] as bool? ?? false;
                                  final remainingSessions = data['remainingSessions'] as int? ?? 0;
                                  final status = (data['status'] as String? ?? 'active').toLowerCase();
                                  
                                  // Count only active plans with remaining sessions that are not cancelled
                                  if (isActive && remainingSessions > 0 && status != 'cancelled') {
                                    activeCount++;
                                  }
                                }
                                
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$activeCount',
                                      style: const TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'ACTIVE PLANS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
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
                            icon: Icons.star,
                            label: 'Completed',
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$completedSessions',
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'COMPLETED',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _upcomingSessionBar(),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser?.uid)
                    .snapshots(),
                builder: (context, snap) {
                  final hasNew = snap.hasData && snap.data!.data()?['hasNewWorkout'] == true;
                  
                  final items = [
                    DashboardItem(
                      icon: Icons.schedule,
                      label: 'My Schedule',
                      color: Colors.blue,
                      targetScreen: const MySchedulePage(),
                      enabled: !(_tabDisabledStatus['schedule'] ?? false),
                    ),
                    DashboardItem(
                      icon: Icons.date_range,
                      label: 'Book Session',
                      color: Colors.purple,
                      targetScreen: const ClientBookSlot(),
                      enabled: !(_tabDisabledStatus['booking'] ?? false),
                    ),
                    DashboardItem(
                      icon: FontAwesomeIcons.dollarSign,
                      label: 'Plans',
                      color: Colors.green,
                      targetScreen: const ClientPlansScreen(),
                      enabled: !(_tabDisabledStatus['plans'] ?? false),
                    ),
                    DashboardItem(
                      icon: FontAwesomeIcons.dumbbell,
                      label: 'Workouts',
                      color: Colors.orange,
                      showBadge: hasNew,
                      enabled: !(_tabDisabledStatus['workouts'] ?? false),
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
                      enabled: !(_tabDisabledStatus['profile'] ?? false),
                    ),
                    DashboardItem(
                      icon: Icons.announcement,
                      label: 'Announcements',
                      color: Colors.teal,
                      targetScreen: const PostAnnouncementScreen(),
                      enabled: !(_tabDisabledStatus['announcements'] ?? false),
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
      padding: const EdgeInsets.all(10),
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
            top: 4,
            right: 4,
            child: Icon(
              icon,
              size: 32,
              color: label == 'Completed' 
                ? Colors.black.withOpacity(0.1)
                : Colors.white.withOpacity(0.2),
            ),
          ),
          Center(child: child),
        ],
      ),
    );
  }

  Widget _upcomingSessionBar() {
    return Container(
      width: double.infinity,
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1e3c72), Color(0xFF2a5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UPCOMING SESSION',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    nextUpcomingSessionTime ?? 'No upcoming session',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.calendar_today,
            size: 32,
            color: Colors.white.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(DashboardItem item) {
    return Card(
      elevation: item.enabled ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: item.enabled ? null : Colors.grey[200],
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.enabled ? () {
          if (item.targetScreen != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => item.targetScreen!),
            );
          } else {
            item.action?.call();
          }
        } : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: item.enabled ? LinearGradient(
              colors: [
                item.color.withOpacity(0.15),
                item.color.withOpacity(0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ) : null,
          ),
          child: Opacity(
            opacity: item.enabled ? 1.0 : 0.5,
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    item.icon,
                    size: 40,
                    color: item.color.withOpacity(item.enabled ? 0.15 : 0.05),
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: item.enabled ? null : Colors.grey[600],
                      ),
                    ),
                    if (!item.enabled) 
                      const Text(
                        'Disabled by admin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                if (item.showBadge && item.enabled)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.red,
                      child: Text('!',
                          style: TextStyle(
                            color: Colors.white, 
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}