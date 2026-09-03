import 'dart:io';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:google_fonts/google_fonts.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  static const _navy    = Color(0xFF0A1628);
  static const _blue    = Color(0xFF1565C0);
  static const _sky     = Color(0xFF2196F3);
  static const _green   = Color(0xFF00897B);
  static const _orange  = Color(0xFFFF6B35);
  static const _purple  = Color(0xFF7B1FA2);
  static const _red     = Color(0xFFE53935);
  static const _bg      = Color(0xFFF5F8FF);
  static const _card    = Color(0xFFFFFFFF);
  static const _text    = Color(0xFF0A1628);
  static const _sub     = Color(0xFF546E7A);

  final _health = Health();

  bool _authorized = false;
  bool _loading = true;
  String? _error;

  int    _steps     = 0;
  double _calories  = 0;
  double _distanceKm = 0;
  int    _heartRate  = 0;
  double _activeCalories = 0;

  static final _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthDataType.HEART_RATE,
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _health.configure();
      final ok = await _health.requestAuthorization(_types);
      if (!ok) {
        if (mounted) {
          setState(() { _authorized = false; _loading = false; });
        }
        return;
      }
      setState(() => _authorized = true);
      await _fetchData();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetchData() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    try {
      // Steps
      final steps = await _health.getTotalStepsInInterval(midnight, now);

      // Active energy + distance + heart rate
      final points = await _health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.DISTANCE_WALKING_RUNNING,
          HealthDataType.HEART_RATE,
        ],
      );

      double activeCal = 0;
      double distM = 0;
      int hrLatest = 0;

      for (final p in points) {
        final val = (p.value as NumericHealthValue).numericValue.toDouble();
        switch (p.type) {
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            activeCal += val;
          case HealthDataType.DISTANCE_WALKING_RUNNING:
            distM += val;
          case HealthDataType.HEART_RATE:
            hrLatest = val.toInt();
          default:
            break;
        }
      }

      if (mounted) {
        setState(() {
          _steps           = steps ?? 0;
          _activeCalories  = activeCal;
          _calories        = activeCal;
          _distanceKm      = distM / 1000.0;
          _heartRate       = hrLatest;
          _loading         = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        Platform.isIOS ? 'Apple Health' : 'Health Connect',
        style: GoogleFonts.barlowCondensed(
            fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      actions: [
        if (!_loading)
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _fetchData,
            tooltip: 'Refresh',
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildError('Something went wrong', _error!);
    }

    if (!_authorized) {
      return _buildPermissionPrompt();
    }

    return RefreshIndicator(
      onRefresh: _fetchData,
      color: _blue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildDateHeader(),
          const SizedBox(height: 16),
          _buildStepsBanner(),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _buildStatCard(
              icon: Icons.local_fire_department_rounded,
              label: 'Calories',
              value: _calories.toStringAsFixed(0),
              unit: 'kcal',
              color: _orange,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard(
              icon: Icons.straighten_rounded,
              label: 'Distance',
              value: _distanceKm.toStringAsFixed(2),
              unit: 'km',
              color: _blue,
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildStatCard(
              icon: Icons.favorite_rounded,
              label: 'Heart Rate',
              value: _heartRate > 0 ? '$_heartRate' : '--',
              unit: 'bpm',
              color: _red,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard(
              icon: Icons.bolt_rounded,
              label: 'Active Cal',
              value: _activeCalories.toStringAsFixed(0),
              unit: 'kcal',
              color: _purple,
            )),
          ]),
          const SizedBox(height: 20),
          _buildTip(),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _buildDateHeader() {
    final now = DateTime.now();
    final weekday = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']
        [now.weekday - 1];
    final months  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Today — $weekday, ${months[now.month - 1]} ${now.day}',
              style: GoogleFonts.barlowCondensed(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _text)),
          Text('Synced from ${Platform.isIOS ? 'Apple Health' : 'Health Connect'}',
              style: GoogleFonts.barlow(fontSize: 12, color: _sub)),
        ]),
      ),
      Icon(Platform.isIOS ? Icons.apple : Icons.health_and_safety_rounded,
          color: _sub, size: 22),
    ]);
  }

  Widget _buildStepsBanner() {
    const goal = 10000;
    final progress = (_steps / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, _blue, _sky],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _navy.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.directions_walk_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text('Steps Today',
              style: GoogleFonts.barlowCondensed(
                  fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
        ]),
        const SizedBox(height: 8),
        Text(_steps.toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},'),
            style: GoogleFonts.barlowCondensed(
                fontSize: 48, fontWeight: FontWeight.w800, color: Colors.white,
                letterSpacing: -1)),
        const SizedBox(height: 4),
        Text('Goal: ${goal.toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} steps',
            style: GoogleFonts.barlow(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text('${(progress * 100).toStringAsFixed(0)}% of daily goal',
            style: GoogleFonts.barlow(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _navy.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 10),
        Text(value,
            style: GoogleFonts.barlowCondensed(
                fontSize: 26, fontWeight: FontWeight.w800, color: _text,
                letterSpacing: -0.5)),
        Text(unit,
            style: GoogleFonts.barlow(fontSize: 11, color: _sub)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.barlowCondensed(
                fontSize: 13, fontWeight: FontWeight.w600, color: _sub)),
      ]),
    );
  }

  Widget _buildTip() {
    const tips = [
      'Taking 10,000 steps a day burns roughly 300–400 extra calories.',
      'Aim for at least 150 minutes of moderate activity per week.',
      'Consistent movement throughout the day is just as important as workouts.',
      'Resting heart rate below 60 bpm indicates good cardiovascular fitness.',
    ];
    final tip = tips[DateTime.now().day % tips.length];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.tips_and_updates_rounded, color: _green, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tip,
              style: GoogleFonts.barlow(
                  fontSize: 13, height: 1.5, color: _text)),
        ),
      ]),
    );
  }

  Widget _buildPermissionPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            Platform.isIOS ? Icons.apple : Icons.health_and_safety_rounded,
            size: 64,
            color: _blue,
          ),
          const SizedBox(height: 20),
          Text(
            'Connect ${Platform.isIOS ? 'Apple Health' : 'Health Connect'}',
            style: GoogleFonts.barlowCondensed(
                fontSize: 22, fontWeight: FontWeight.w700, color: _text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Allow Flex Facility to read your steps, calories, and activity data to track your fitness progress.',
            style: GoogleFonts.barlow(fontSize: 14, color: _sub, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _init,
              icon: const Icon(Icons.health_and_safety_rounded),
              label: const Text('Grant Access'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.barlowCondensed(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildError(String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.barlowCondensed(
                  fontSize: 20, fontWeight: FontWeight.w700, color: _text)),
          const SizedBox(height: 8),
          Text(detail,
              style: GoogleFonts.barlow(fontSize: 13, color: _sub),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _init,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ]),
      ),
    );
  }
}
