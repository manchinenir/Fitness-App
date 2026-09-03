import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';

import 'package:google_fonts/google_fonts.dart';

import 'ai_chat_screen.dart';
import 'client_message_screen.dart';
import 'health_screen.dart';
import 'client_book_slot.dart';
import 'client_plans_screen.dart';
import 'schedule_screen.dart';
import 'post_announcement_client.dart';
import 'ProfileScreen.dart';

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
  Timer? _timer;
  
  Map<String, bool> _tabDisabledStatus = {};
  bool _hasNewWorkout = false;
  int _carouselPage = 0;
  final PageController _pageCtrl = PageController();

  Future<bool> _enforceVerifiedAccess(User? user) async {
    if (user == null) return false;

    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser == null || !refreshedUser.emailVerified) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your email before accessing the app.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return false;
    }

    return true;
  }

  @override
  void initState() {
    super.initState();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final canAccess = await _enforceVerifiedAccess(user);
        if (!canAccess) return;

        _fetchUserProfile();
        _setupSessionsListener();
        _setupProfileImageListener();
        _loadTabDisabledStatus();
        _setupRealTimeSessionListener();
      }
    });

    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser != null) {
      _enforceVerifiedAccess(initialUser).then((canAccess) {
        if (!canAccess) return;
        _fetchUserProfile();
        _setupSessionsListener();
        _setupProfileImageListener();
        _loadTabDisabledStatus();
        _setupRealTimeSessionListener();
      });
    }

    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null && mounted) {
        final isReminder = message.data['type'] == 'session_reminder';
        final slotTime = message.data['slotTime'] ?? '';
        final slotDate = message.data['slotDate'] ?? '';
        final title = message.notification!.title ?? '';
        final body = message.notification!.body ?? '';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            backgroundColor: isReminder ? const Color(0xFF1e3c72) : Colors.blueAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                Icon(
                  isReminder ? Icons.alarm : Icons.notifications,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      if (isReminder && slotTime.isNotEmpty)
                        Text('$slotTime${slotDate.isNotEmpty ? ' · $slotDate' : ''}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12))
                      else
                        Text(body,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                if (isReminder)
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const MySchedulePage()));
                    },
                    child: const Text('VIEW',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
        );
      }
    });

    // Save FCM token to Firestore so server can send reminders
    _saveFcmToken();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFcmToken);
  }

  Future<void> _saveFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'fcm_token': token},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      print('FCM token save error: $e');
    }
  }

  Future<void> _updateFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'fcm_token': token},
        SetOptions(merge: true),
      );
    } catch (e) {
      print('FCM token update error: $e');
    }
  }

  @override
  void dispose() {
    _sessionsSubscription?.cancel();
    _authSubscription?.cancel();
    _profileListener?.cancel();
    _timer?.cancel();
    _pageCtrl.dispose();
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
      print('Error loading tab disabled status: $e');
    }
  }

  void _setupRealTimeSessionListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('booked_by', arrayContains: uid)
        .snapshots()
        .listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  DateTime _parseEndDate(dynamic endDate) {
    if (endDate is Timestamp) {
      return endDate.toDate().toLocal();
    } else if (endDate is String) {
      return DateTime.parse(endDate).toLocal();
    } else if (endDate is DateTime) {
      return endDate.toLocal();
    } else {
      return DateTime.now().add(const Duration(days: 1));
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
          final data = snapshot.data();
          setState(() {
            firestorePhotoUrl = data?['profileImage'];
            _hasNewWorkout = data?['hasNewWorkout'] == true;
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

  String _formatMonthDayYear(DateTime dt) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
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
        
        // Check if this session is completed (in the past)
        if (date.isBefore(now)) {
          completed++;
        } else {
          // For upcoming sessions, check if they're today or in the future
          upcoming.add({'date': date, 'time': timeRange});
        }
      }
      
      String? nextInfo;
      if (upcoming.isNotEmpty) {
        // Sort by date
        upcoming.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
        final next = upcoming.first;
        final dt = next['date'] as DateTime;

        final dateStr = _formatMonthDayYear(dt);
        nextInfo = '$dateStr – ${next['time']}';
      } else {
        nextInfo = 'No upcoming sessions';
      }
      
      if (mounted) {
        setState(() {
          completedSessions = completed;
          nextUpcomingSessionTime = nextInfo;
        });
      }
    });

    // Subscription listeners
    FirebaseFirestore.instance
        .collection('client_subscriptions')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((subscriptionSnapshot) {
      if (mounted) {
        setState(() {});
      }
    });

    FirebaseFirestore.instance
        .collection('client_purchases')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .listen((_) {
      if (mounted) {
        setState(() {});
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
          const SnackBar(content: Text('Failed to upload image')),
        );
      }
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Design tokens — Flex Facility blue & white ────────────────────────────
  static const _bg     = Color(0xFFF5F8FF);   // clean white-blue
  static const _card   = Color(0xFFFFFFFF);   // pure white
  static const _teal   = Color(0xFF1565C0);   // royal blue (brand primary)
  static const _orange = Color(0xFFFF6B35);   // orange (warm energy contrast)
  static const _purple = Color(0xFF0288D1);   // sky blue (secondary)
  static const _green  = Color(0xFF00897B);   // teal-green
  static const _blue   = Color(0xFF0D47A1);   // deep navy blue
  static const _text   = Color(0xFF0A1628);   // deep navy (near-black)
  static const _sub    = Color(0xFF546E7A);   // blue-gray

  // Header gradient — deep navy → royal blue → sky
  static const _headerGrad = LinearGradient(
    colors: [Color(0xFF0A1628), Color(0xFF1565C0), Color(0xFF2196F3)],
    begin: Alignment.topLeft, end: Alignment.bottomRight);

  List<BoxShadow> get _shadow => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 18, offset: const Offset(0, 6)),
  ];

  static final _slides = [
    _Slide(title: 'STRONGER\nEVERYDAY', sub: 'Stay consistent. Stay active.\nSee the change.',
        btn: 'Explore Workouts', c1: const Color(0xFF0A1628), c2: const Color(0xFF1565C0)),
    _Slide(title: 'Build\nStrength', sub: 'Challenge yourself every day.',
        btn: 'Get Started', c1: const Color(0xFF01579B), c2: const Color(0xFF29B6F6)),
    _Slide(title: 'Stay\nConsistent', sub: 'Book your next session today.',
        btn: 'Book Now', c1: const Color(0xFF006064), c2: const Color(0xFF26C6DA)),
  ];

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? avatarImage;
    if (localImageFile != null) {
      avatarImage = FileImage(localImageFile!);
    } else if (firestorePhotoUrl != null && firestorePhotoUrl!.isNotEmpty) {
      avatarImage = NetworkImage(firestorePhotoUrl!);
    }

    if (isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
                const SizedBox(height: 16),
                Text(errorMessage!, textAlign: TextAlign.center,
                    style: const TextStyle(color: _sub, fontSize: 15)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _fetchUserProfile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Try Again',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: _buildBottomNav(),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: _fetchUserProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroHeader(avatarImage),
              const SizedBox(height: 22),
              _buildScheduleCard(),
              const SizedBox(height: 16),
              _buildStatsRow(),
              const SizedBox(height: 16),
              _buildAiChatBanner(),
              const SizedBox(height: 16),
              _buildQuickAccess(),
              const SizedBox(height: 24),
              _buildProgressAndUpcoming(),
              const SizedBox(height: 24),
              _buildRecommended(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gradient hero header (top bar + carousel fused) ──────────────────────
  Widget _buildHeroHeader(ImageProvider<Object>? avatarImage) {
    return Container(
      decoration: const BoxDecoration(
        gradient: _headerGrad,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36)),
      ),
      child: Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: ClipOval(
                    child: avatarImage != null
                        ? Image(image: avatarImage, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.person, color: _blue, size: 26))
                        : Icon(Icons.person, color: _blue, size: 26),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_greeting(),
                      style: TextStyle(fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.75))),
                  Row(children: [
                    Text(firstName.isNotEmpty ? firstName : 'Athlete',
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.4)),
                    const SizedBox(width: 4),
                    const Text('👋', style: TextStyle(fontSize: 18)),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('🔥', style: TextStyle(fontSize: 11)),
                      SizedBox(width: 4),
                      Text('3 day streak',
                          style: TextStyle(fontSize: 11, color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ),
              // Bell
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.notifications_outlined,
                      size: 20, color: Colors.white),
                ),
                Positioned(top: 7, right: 8,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: _orange, shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0A1628), width: 1.5)),
                  )),
              ]),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) Navigator.pushReplacementNamed(context, '/login');
                },
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.settings_outlined,
                      size: 20, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        // Carousel inside gradient
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _carouselPage = i),
            itemCount: _slides.length,
            itemBuilder: (_, i) {
              final s = _slides[i];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(colors: [s.c1, s.c2],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: s.c2.withValues(alpha: 0.4),
                      blurRadius: 20, offset: const Offset(0, 8))],
                ),
                clipBehavior: Clip.hardEdge,
                child: Stack(children: [
                  Positioned(right: -20, top: -20,
                      child: Container(width: 140, height: 140,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08)))),
                  Positioned(right: 30, bottom: -30,
                      child: Container(width: 90, height: 90,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05)))),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.title,
                            style: const TextStyle(color: Colors.white, fontSize: 24,
                                fontWeight: FontWeight.w900, height: 1.1,
                                letterSpacing: -0.5)),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.sub,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 11, height: 1.4)),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const ClientBookSlot())),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(s.btn,
                                    style: TextStyle(color: s.c2,
                                        fontSize: 11, fontWeight: FontWeight.w800)),
                                const SizedBox(width: 4),
                                Icon(Icons.play_arrow_rounded,
                                    color: s.c2, size: 14),
                              ]),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        // Page dots — white on dark bg
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _carouselPage == i ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: _carouselPage == i
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999)),
          )),
        ),
        const SizedBox(height: 22),
      ]),
    );
  }

  // ── Today's schedule card ─────────────────────────────────────────────────
  Widget _buildScheduleCard() {
    final hasSession = nextUpcomingSessionTime != null &&
        nextUpcomingSessionTime != 'No upcoming sessions';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1628), Color(0xFF1565C0), Color(0xFF2196F3)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha: 0.4),
              blurRadius: 24, offset: const Offset(0, 10))],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          Positioned(right: -30, top: -30,
              child: Container(width: 150, height: 150,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1)))),
          Positioned(right: 60, bottom: -40,
              child: Container(width: 90, height: 90,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07)))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.calendar_today_outlined, color: Colors.white, size: 11),
                    const SizedBox(width: 5),
                    const Text("TODAY'S SCHEDULE",
                        style: TextStyle(color: Colors.white, fontSize: 10,
                            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Ready for your\nnext session?',
                      style: TextStyle(color: Colors.white, fontSize: 19,
                          fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 5),
                  Text(hasSession ? nextUpcomingSessionTime! : 'No sessions booked yet',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11), maxLines: 2),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => hasSession
                            ? const MySchedulePage() : const ClientBookSlot())),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(hasSession ? 'View Schedule' : 'Book a Session',
                            style: const TextStyle(color: _purple, fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 3),
                        const Icon(Icons.chevron_right, color: _purple, size: 15),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.event_available_rounded,
                    color: Colors.white, size: 46),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: _buildActivePlansStat()),
        const SizedBox(width: 10),
        Expanded(child: _buildStatCard(
            value: '$completedSessions', label: 'Sessions\nCompleted',
            subtitle: 'This month',
            icon: Icons.emoji_events_outlined, color: _purple)),
        const SizedBox(width: 10),
        Expanded(child: _buildStatCard(
            value: (nextUpcomingSessionTime != null &&
                nextUpcomingSessionTime != 'No upcoming sessions') ? '1' : '0',
            label: 'Upcoming\nSessions',
            subtitle: 'Book your next session',
            icon: Icons.event_outlined, color: _orange)),
      ]),
    );
  }

  Widget _buildActivePlansStat() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, snap) {
        int purchaseCount = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            if ((d['isActive'] as bool? ?? false) &&
                (d['remainingSessions'] as int? ?? 0) > 0 &&
                (d['status'] as String? ?? 'active').toLowerCase() != 'cancelled') {
              purchaseCount++;
            }
          }
        }
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('client_subscriptions')
              .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
              .snapshots(),
          builder: (context, subSnap) {
            int total = purchaseCount;
            if (subSnap.hasData) {
              final now = DateTime.now().toLocal();
              for (final doc in subSnap.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                final endDate = d['endDate'];
                DateTime exp;
                if (endDate is Timestamp) { exp = endDate.toDate().toLocal(); }
                else if (endDate is String) { try { exp = DateTime.parse(endDate).toLocal(); } catch (_) { continue; } }
                else if (endDate is DateTime) { exp = endDate.toLocal(); }
                else { continue; }
                if ((d['isActive'] as bool? ?? false) &&
                    (d['status'] as String? ?? '').toLowerCase() != 'cancelled' &&
                    exp.isAfter(now)) { total++; }
              }
            }
            return _buildStatCard(
              value: snap.connectionState == ConnectionState.waiting ? '–' : '$total',
              label: 'Active\nPlans', subtitle: 'Currently active',
              icon: Icons.assignment_turned_in_outlined, color: _teal,
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard({required String value, required String label,
      required String subtitle, required IconData icon, required Color color}) {
    // Derive a slightly lighter shade for the gradient end
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.white, 0.28)!],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
            color: Colors.white, letterSpacing: -0.5)),
        Text(label, style: TextStyle(fontSize: 9.5,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.3, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 9,
            color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w700),
            maxLines: 2),
      ]),
    );
  }

  // ── AI Chat Banner ────────────────────────────────────────────────────────
  Widget _buildAiChatBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AiChatScreen())),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A1628), Color(0xFF1565C0), Color(0xFF2196F3)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A1628).withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI Fitness Coach',
                    style: GoogleFonts.barlowCondensed(
                        fontSize: 18, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text('Ask about workouts, nutrition & more',
                    style: GoogleFonts.barlow(fontSize: 12.5, color: Colors.white70)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text('Chat Now',
                  style: GoogleFonts.barlowCondensed(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: const Color(0xFF1565C0))),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Quick Access ──────────────────────────────────────────────────────────
  Widget _buildQuickAccess() {
    final items = [
      _DashItem(icon: Icons.calendar_month_rounded, label: 'My Schedule',
          sub: 'View upcoming sessions', color: _teal,
          enabled: !(_tabDisabledStatus['schedule'] ?? false),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MySchedulePage()))),
      _DashItem(icon: Icons.add_circle_rounded, label: 'Book Session',
          sub: 'Find available trainers', color: _purple,
          enabled: !(_tabDisabledStatus['booking'] ?? false),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ClientBookSlot()))),
      _DashItem(icon: Icons.card_membership_rounded, label: 'My Plans',
          sub: 'View membership plans', color: _green,
          enabled: !(_tabDisabledStatus['plans'] ?? false),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ClientPlansScreen()))),
      _DashItem(icon: FontAwesomeIcons.dumbbell, label: 'Workouts',
          sub: 'Start your workout', color: _orange, badge: _hasNewWorkout,
          enabled: !(_tabDisabledStatus['workouts'] ?? false),
          onTap: () async {
            Navigator.pushNamed(context, '/clientWorkout');
            await FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .update({'hasNewWorkout': false});
          }),
      _DashItem(icon: Icons.person_rounded, label: 'Profile',
          sub: 'Manage your account', color: _blue,
          enabled: !(_tabDisabledStatus['profile'] ?? false),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()))),
      _DashItem(icon: Icons.campaign_rounded, label: 'Announcements',
          sub: 'View latest updates', color: _purple,
          enabled: !(_tabDisabledStatus['announcements'] ?? false),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PostAnnouncementScreen()))),
      _DashItem(icon: Icons.chat_rounded, label: 'Messages',
          sub: 'Chat with Kenny', color: _teal,
          enabled: true,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ClientMessageScreen()))),
      _DashItem(icon: Icons.monitor_heart_rounded, label: 'Health',
          sub: 'Steps & calories', color: _green,
          enabled: true,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const HealthScreen()))),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quick Access',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: _text, letterSpacing: -0.3)),
            SizedBox(height: 2),
            Text('Everything you need in one place',
                style: TextStyle(fontSize: 11, color: _sub)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('View All', style: TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w700)),
              SizedBox(width: 2),
              Icon(Icons.chevron_right, color: _teal, size: 13),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 0.86,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            return GestureDetector(
              onTap: item.enabled ? item.onTap : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: item.enabled ? 1.0 : 0.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: _card, borderRadius: BorderRadius.circular(18),
                    boxShadow: item.enabled ? _shadow : []),
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(12)),
                        child: Icon(item.icon, size: 20, color: item.color),
                      ),
                      if (item.badge && item.enabled)
                        Positioned(top: -3, right: -3,
                          child: Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444), shape: BoxShape.circle,
                              border: Border.all(color: _card, width: 1.5)),
                          )),
                    ]),
                    const SizedBox(height: 8),
                    Text(item.label,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: _text, letterSpacing: -0.1),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(item.sub,
                        style: const TextStyle(fontSize: 9.5, color: _sub, height: 1.3),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Icon(Icons.chevron_right, color: _sub, size: 14),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── Weekly Progress + Upcoming Session ────────────────────────────────────
  Widget _buildProgressAndUpcoming() {
    final hasSession = nextUpcomingSessionTime != null &&
        nextUpcomingSessionTime != 'No upcoming sessions';
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime.now().weekday; // 1=Mon … 7=Sun

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Weekly Progress card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card, borderRadius: BorderRadius.circular(20), boxShadow: _shadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Weekly\nProgress',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                          color: _text, height: 1.2)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: _teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('View Stats', style: TextStyle(fontSize: 9, color: _teal,
                          fontWeight: FontWeight.w700)),
                      Icon(Icons.chevron_right, color: _teal, size: 11),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Goal: 4 Workouts',
                      style: TextStyle(fontSize: 10, color: _sub, fontWeight: FontWeight.w500)),
                  Text('${(completedSessions).clamp(0, 4)}/4',
                      style: const TextStyle(fontSize: 10, color: _teal, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (completedSessions / 4).clamp(0.0, 1.0),
                    backgroundColor: _teal.withValues(alpha: 0.15),
                    color: _teal, minHeight: 6),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final active = i < today;
                    return Column(children: [
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? _teal : _sub.withValues(alpha: 0.15)),
                        child: active
                            ? const Icon(Icons.check, size: 11, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 3),
                      Text(days[i], style: TextStyle(fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: active ? _teal : _sub)),
                    ]);
                  }),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _miniStat('🔥', '320', 'Cal'),
                    _miniStat('⚡', '180', 'Active\nMins'),
                    _miniStat('📈', '75%', 'Goal'),
                  ],
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          // Upcoming Session card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card, borderRadius: BorderRadius.circular(20), boxShadow: _shadow),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Upcoming\nSession',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: _text, height: 1.2)),
                const Spacer(),
                Center(
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: _teal.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(
                      hasSession ? Icons.event_available_rounded : Icons.event_busy_outlined,
                      color: _teal, size: 28),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    hasSession ? nextUpcomingSessionTime! : 'No upcoming sessions',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: _sub, height: 1.3),
                    maxLines: 3,
                  ),
                ),
                if (!hasSession)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Center(
                      child: Text('Book a session and stay on track',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9.5, color: _sub, height: 1.3)),
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => hasSession
                          ? const MySchedulePage() : const ClientBookSlot())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _teal, borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Text(hasSession ? 'View Session' : 'Book a Session',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _miniStat(String emoji, String value, String label) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 12,
          fontWeight: FontWeight.w800, color: _text)),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 8.5, color: _sub, height: 1.2)),
    ]);
  }

  // ── Recommended for You ───────────────────────────────────────────────────
  Widget _buildRecommended() {
    const recs = [
      _Rec(title: 'Strength Training',  level: 'Beginner',     mins: 45, cal: 320,
          c1: Color(0xFF0A1628), c2: Color(0xFF1565C0)),
      _Rec(title: 'Full Body Workout',  level: 'Intermediate', mins: 30, cal: 250,
          c1: Color(0xFF01579B), c2: Color(0xFF29B6F6)),
      _Rec(title: 'Yoga & Recovery',    level: 'Beginner',     mins: 40, cal: 200,
          c1: Color(0xFF0D47A1), c2: Color(0xFF42A5F5)),
      _Rec(title: 'Cardio Blast',       level: 'Advanced',     mins: 25, cal: 300,
          c1: Color(0xFF7C2800), c2: Color(0xFFFF6B35)),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Recommended for You',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: _text, letterSpacing: -0.3)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('See All', style: TextStyle(fontSize: 11, color: _teal,
                  fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right, color: _teal, size: 13),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16),
          itemCount: recs.length,
          itemBuilder: (_, i) {
            final r = recs[i];
            final levelColor = r.level == 'Beginner' ? _green
                : r.level == 'Intermediate' ? _orange
                : r.level == 'Advanced' ? const Color(0xFFEF4444)
                : _teal;
            return Container(
              width: 148,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: _card, borderRadius: BorderRadius.circular(20),
                boxShadow: _shadow),
              clipBehavior: Clip.hardEdge,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [r.c1, r.c2],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)),
                  child: Stack(children: [
                    Positioned(right: -10, top: -10,
                        child: Container(width: 70, height: 70,
                            decoration: BoxDecoration(shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08)))),
                    const Center(child: Icon(Icons.fitness_center,
                        color: Colors.white38, size: 38)),
                    Positioned(bottom: 7, left: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: levelColor, borderRadius: BorderRadius.circular(999)),
                        child: Text(r.level,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 8, fontWeight: FontWeight.w700)),
                      )),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.title,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: _text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.timer_outlined, size: 10, color: _sub),
                      const SizedBox(width: 2),
                      Text('${r.mins} min', style: const TextStyle(fontSize: 9.5, color: _sub)),
                      const SizedBox(width: 6),
                      const Icon(Icons.local_fire_department_outlined, size: 10, color: _sub),
                      const SizedBox(width: 2),
                      Text('${r.cal} Cal', style: const TextStyle(fontSize: 9.5, color: _sub)),
                    ]),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/clientWorkout'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _teal, borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: Text('Start Now',
                            style: TextStyle(color: Colors.white,
                                fontSize: 10, fontWeight: FontWeight.w700))),
                      ),
                    ),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  // ── Bottom navigation ─────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20, offset: const Offset(0, -6))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.home_rounded, 'Home', active: true),
          _navItem(Icons.calendar_today_rounded, 'Schedule',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MySchedulePage()))),
          // Center + button with gradient
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ClientBookSlot())),
            child: Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A1628), Color(0xFF1565C0)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha: 0.45),
                    blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          ),
          _navItem(Icons.chat_bubble_outline_rounded, 'Chat'),
          _navItem(Icons.person_outline_rounded, 'Profile',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()))),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label,
      {bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        ShaderMask(
          shaderCallback: active
              ? (b) => const LinearGradient(
                  colors: [Color(0xFF0A1628), Color(0xFF1565C0)]).createShader(b)
              : (b) => LinearGradient(colors: [_sub, _sub]).createShader(b),
          child: Icon(icon, size: 22, color: Colors.white),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600,
            color: active ? _teal : _sub)),
        if (active)
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 18, height: 3,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A1628), Color(0xFF1565C0)]),
              borderRadius: BorderRadius.circular(999)),
          ),
      ]),
    );
  }
}

class _DashItem {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final bool enabled;
  final bool badge;
  final VoidCallback? onTap;
  const _DashItem({required this.icon, required this.label, required this.sub,
      required this.color, required this.enabled, required this.onTap,
      this.badge = false});
}

class _Slide {
  final String title, sub, btn;
  final Color c1, c2;
  const _Slide({required this.title, required this.sub, required this.btn,
      required this.c1, required this.c2});
}

class _Rec {
  final String title, level;
  final int mins, cal;
  final Color c1, c2;
  const _Rec({required this.title, required this.level, required this.mins,
      required this.cal, required this.c1, required this.c2});
}