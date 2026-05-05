import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

class AdminCreateSlotsScreen extends StatefulWidget {
  const AdminCreateSlotsScreen({super.key});

  @override
  State<AdminCreateSlotsScreen> createState() => _AdminCreateSlotsScreenState();
}

class _AdminCreateSlotsScreenState extends State<AdminCreateSlotsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  Map<String, dynamic> _firestoreSlots = {};
  final int slotCapacity = 6;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _dayListener;
  Timer? _uiRefreshTimer;

  // Default schedule — individual slots per day
  static const Map<String, List<String>> _defaultSchedule = {
    'Monday': [
      '5:30 AM - 6:30 AM', '6:00 AM - 7:00 AM', '6:30 AM - 7:30 AM',
      '7:00 AM - 8:00 AM', '7:30 AM - 8:30 AM', '8:00 AM - 9:00 AM',
      '8:30 AM - 9:30 AM', '9:00 AM - 10:00 AM',
      '5:00 PM - 6:00 PM', '5:30 PM - 6:30 PM', '6:00 PM - 7:00 PM',
    ],
    'Tuesday': [
      '5:30 AM - 6:30 AM', '6:00 AM - 7:00 AM', '6:30 AM - 7:30 AM',
      '7:00 AM - 8:00 AM', '7:30 AM - 8:30 AM', '8:00 AM - 9:00 AM',
      '5:00 PM - 6:00 PM', '5:30 PM - 6:30 PM', '6:00 PM - 7:00 PM',
    ],
    'Wednesday': [
      '5:30 AM - 6:30 AM', '6:00 AM - 7:00 AM', '6:30 AM - 7:30 AM',
      '7:00 AM - 8:00 AM', '7:30 AM - 8:30 AM', '8:00 AM - 9:00 AM',
      '5:00 PM - 6:00 PM', '5:30 PM - 6:30 PM', '6:00 PM - 7:00 PM',
    ],
    'Thursday': [
      '5:30 AM - 6:30 AM', '6:00 AM - 7:00 AM', '6:30 AM - 7:30 AM',
      '7:00 AM - 8:00 AM', '7:30 AM - 8:30 AM', '8:00 AM - 9:00 AM',
      '5:00 PM - 6:00 PM', '5:30 PM - 6:30 PM', '6:00 PM - 7:00 PM',
    ],
    'Friday': [
      '5:30 AM - 6:30 AM', '6:00 AM - 7:00 AM', '6:30 AM - 7:30 AM',
      '7:00 AM - 8:00 AM', '7:30 AM - 8:30 AM', '8:00 AM - 9:00 AM',
      '9:30 AM - 10:30 AM',
    ],
    'Saturday': [
      '7:00 AM - 8:00 AM', '7:30 AM - 8:30 AM', '8:00 AM - 9:00 AM',
      '9:30 AM - 10:30 AM',
      '5:00 PM - 6:00 PM', '5:30 PM - 6:30 PM', '6:00 PM - 7:00 PM',
    ],
  };

  // Live weekly schedule — loaded from Firestore, editable by admin
  Map<String, List<String>> availabilityMap = {
    for (final e in _defaultSchedule.entries) e.key: List<String>.from(e.value),
  };

  // Date-specific slot overrides — keyed by 'yyyy-MM-dd'
  Map<String, List<String>> _dateOverrides = {};

  void _setupRealTimeSessionListener() {
    FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('date_time', isLessThan: Timestamp.now())
        .snapshots()
        .listen((snapshot) {});
  }

  // ── Dynamic schedule: load from Firestore ──────────────────────────────────
  Future<void> _loadSchedule() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('trainer_schedule')
          .doc('schedule')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        // Load weekly schedule
        final loaded = <String, List<String>>{};
        for (final day in _defaultSchedule.keys) {
          if (data[day] != null) {
            loaded[day] = List<String>.from(data[day] as List);
          } else {
            loaded[day] = List<String>.from(_defaultSchedule[day]!);
          }
        }
        // Load date-specific overrides
        final overrides = <String, List<String>>{};
        if (data['date_overrides'] != null) {
          (data['date_overrides'] as Map<String, dynamic>).forEach((dateKey, slots) {
            overrides[dateKey] = List<String>.from(slots as List);
          });
        }
        if (mounted) setState(() {
          availabilityMap = loaded;
          _dateOverrides = overrides;
        });
      }
    } catch (e) {
      print('❌ Error loading schedule: $e');
    }
  }

  Future<void> _saveSchedule() async {
    try {
      await FirebaseFirestore.instance
          .collection('trainer_schedule')
          .doc('schedule')
          .set({
        for (final e in availabilityMap.entries) e.key: e.value,
        'date_overrides': _dateOverrides,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule saved successfully'), backgroundColor: Colors.green),
        );
        _listenToDay(_selectedDay);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving schedule: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Manage Schedule dialog ─────────────────────────────────────────────────
  void _showManageScheduleDialog() {
    // Deep-copy so Cancel doesn't affect the live maps
    final editMap = <String, List<String>>{
      for (final e in availabilityMap.entries) e.key: List<String>.from(e.value),
    };
    final editOverrides = <String, List<String>>{
      for (final e in _dateOverrides.entries) e.key: List<String>.from(e.value),
    };

    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    String selectedDay = days[0];

    Widget _slotTile(String label, VoidCallback onDelete) => Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.access_time, size: 16, color: Color(0xFF1C2D5E)),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
        );

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final weeklySlots = editMap[selectedDay] ??= [];

          // Date overrides sorted by date for display
          final sortedDateKeys = editOverrides.keys.toList()..sort();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manage Schedule',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                    ),
                    const SizedBox(height: 12),

                    // ── Weekly slots section ───────────────────────────────
                    const Text('Weekly Slots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    // Day selector chips
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: days.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final day = days[i];
                          final isSelected = day == selectedDay;
                          return GestureDetector(
                            onTap: () => setDialogState(() => selectedDay = day),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF1C2D5E) : Colors.grey[200],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                day.substring(0, 3),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: weeklySlots.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('No weekly slots for this day.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: weeklySlots.length,
                              itemBuilder: (_, i) => _slotTile(
                                weeklySlots[i],
                                () => setDialogState(() => weeklySlots.removeAt(i)),
                              ),
                            ),
                    ),

                    // ── Date-specific slots section ────────────────────────
                    if (sortedDateKeys.isNotEmpty) ...[
                      const Divider(),
                      const Text('Date-Specific Slots', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: sortedDateKeys.length,
                          itemBuilder: (_, di) {
                            final dateKey = sortedDateKeys[di];
                            final dateSlots = editOverrides[dateKey]!;
                            final displayDate = DateFormat('EEE, MMM d yyyy').format(DateTime.parse(dateKey));
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(displayDate,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1C2D5E))),
                                ),
                                ...dateSlots.asMap().entries.map((e) => _slotTile(
                                      e.value,
                                      () => setDialogState(() {
                                        dateSlots.removeAt(e.key);
                                        if (dateSlots.isEmpty) editOverrides.remove(dateKey);
                                      }),
                                    )),
                              ],
                            );
                          },
                        ),
                      ),
                    ],

                    const Divider(),
                    // Add slot button
                    TextButton.icon(
                      icon: const Icon(Icons.add, color: Color(0xFF1C2D5E)),
                      label: const Text('Add time slot for a specific date', style: TextStyle(color: Color(0xFF1C2D5E))),
                      onPressed: () async {
                        final result = await _showAddSlotDialog(ctx);
                        if (result != null) {
                          setDialogState(() {
                            editOverrides[result['dateKey']!] ??= [];
                            if (!editOverrides[result['dateKey']!]!.contains(result['slot'])) {
                              editOverrides[result['dateKey']!]!.add(result['slot']!);
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1C2D5E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              availabilityMap = editMap;
                              _dateOverrides = editOverrides;
                            });
                            _saveSchedule();
                          },
                          child: const Text('SAVE'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Returns {dateKey: 'yyyy-MM-dd', slot: 'X:XX AM - Y:YY AM'} or null if cancelled
  Future<Map<String, String>?> _showAddSlotDialog(BuildContext ctx) async {
    DateTime? selectedDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    String? errorText;

    String _formatTod(TimeOfDay tod) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
      return DateFormat.jm().format(dt);
    }

    return showDialog<Map<String, String>>(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Time Slot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose a date and time for the new slot.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),

              // ── Date picker ──────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today, color: Color(0xFF1C2D5E)),
                title: Text(
                  selectedDate == null
                      ? 'Pick a date'
                      : DateFormat('EEE, MMM d yyyy').format(selectedDate!),
                  style: TextStyle(
                    color: selectedDate == null ? Colors.grey : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogCtx,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (ctx, child) => Theme(
                      data: ThemeData.light().copyWith(
                        colorScheme: const ColorScheme.light(primary: Color(0xFF1C2D5E)),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setDialogState(() { selectedDate = picked; errorText = null; });
                },
              ),

              // ── Start time picker ────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow, color: Color(0xFF1C2D5E)),
                title: Text(
                  startTime == null ? 'Pick start time' : _formatTod(startTime!),
                  style: TextStyle(
                    color: startTime == null ? Colors.grey : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: dialogCtx,
                    initialTime: startTime ?? const TimeOfDay(hour: 5, minute: 30),
                  );
                  if (picked != null) setDialogState(() { startTime = picked; errorText = null; });
                },
              ),

              // ── End time picker ──────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.stop, color: Color(0xFF1C2D5E)),
                title: Text(
                  endTime == null ? 'Pick end time' : _formatTod(endTime!),
                  style: TextStyle(
                    color: endTime == null ? Colors.grey : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: dialogCtx,
                    initialTime: endTime ?? const TimeOfDay(hour: 6, minute: 30),
                  );
                  if (picked != null) setDialogState(() { endTime = picked; errorText = null; });
                },
              ),

              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C2D5E),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (selectedDate == null) {
                  setDialogState(() => errorText = 'Please pick a date.');
                  return;
                }
                if (startTime == null || endTime == null) {
                  setDialogState(() => errorText = 'Please pick both start and end time.');
                  return;
                }
                final startMins = startTime!.hour * 60 + startTime!.minute;
                final endMins   = endTime!.hour   * 60 + endTime!.minute;
                if (endMins <= startMins) {
                  setDialogState(() => errorText = 'End time must be after start time.');
                  return;
                }
                final base = selectedDate!;
                final startDt = DateTime(base.year, base.month, base.day, startTime!.hour, startTime!.minute);
                final endDt   = DateTime(base.year, base.month, base.day, endTime!.hour,   endTime!.minute);
                Navigator.pop(dialogCtx, {
                  'dateKey': DateFormat('yyyy-MM-dd').format(base),
                  'slot': '${DateFormat.jm().format(startDt)} - ${DateFormat.jm().format(endDt)}',
                });
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSchedule();
    _listenToDay(_selectedDay);
    _startSessionCompletionChecker();
    _setupRealTimeSessionListener();
    // Refresh UI every minute so past slots flip to "Unavailable" without waiting for Firestore
    _uiRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dayListener?.cancel();
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  void _listenToDay(DateTime date) {
    _dayListener?.cancel();

    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final col = FirebaseFirestore.instance.collection('trainer_slots');

    _dayListener = col
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: '$dateKey|')
        .where(FieldPath.documentId, isLessThan: '$dateKey|z')
        .snapshots()
        .listen((snap) {
      final Map<String, dynamic> slots = {
        for (final doc in snap.docs) doc.id: doc.data()
      };
      if (mounted) {
        setState(() => _firestoreSlots = slots);
      }
    }, onError: (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error listening slots: $e')),
      );
    });
  }

  List<String> generateHourlySlots(DateTime date) {
    final weekday = DateFormat('EEEE').format(date);
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final weekly = availabilityMap[weekday] ?? [];
    final dateSpecific = _dateOverrides[dateKey] ?? [];
    // Merge, avoid duplicates
    final combined = [...weekly];
    for (final s in dateSpecific) {
      if (!combined.contains(s)) combined.add(s);
    }
    return combined;
  }

  // ✅ FIXED: Enhanced session completion checker
  void _startSessionCompletionChecker() {
    // Check every 5 minutes for past sessions
    Timer.periodic(Duration(minutes: 5), (timer) {
      _markPastSessionsAsCompleted();
    });
    
    // Also check when the screen loads
    _markPastSessionsAsCompleted();
  }

  // ✅ FIXED: Enhanced method to parse slot end time
  DateTime _parseFlexibleTime(String raw) {
    final value = raw.trim();
    final upper = value.toUpperCase();

    if (upper.contains('AM') || upper.contains('PM')) {
      try {
        return DateFormat("h:mm a", 'en_US').parseStrict(upper);
      } catch (_) {
        try {
          return DateFormat("hh:mm a", 'en_US').parseStrict(upper);
        } catch (_) {
          return DateFormat.jm().parseStrict(value);
        }
      }
    }

    try {
      return DateFormat("HH:mm").parseStrict(value);
    } catch (_) {
      return DateFormat.jm().parseStrict(value);
    }
  }

  List<String> _splitSlotRange(String slotTime) {
    return slotTime
        .split(RegExp(r'\s*[\-–]\s*'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
  }

  DateTime _parseSlotEndTime(String slotTime, DateTime slotDate) {
    try {
      // Supports "5:30 AM - 6:30 AM", "17:30 - 18:30", and en-dash variants.
      final parts = _splitSlotRange(slotTime);
      if (parts.length < 2) {
        throw const FormatException('Invalid slot range');
      }
      final endTime = _parseFlexibleTime(parts[1]);

      // Create DateTime in LOCAL time (not UTC)
      return DateTime(
        slotDate.year,
        slotDate.month,
        slotDate.day,
        endTime.hour,
        endTime.minute,
      );
    } catch (e) {
      print('❌ Error parsing slot end time: $slotTime - $e');
      // Keep today's slot as available if parse fails (past-day check is handled separately).
      return DateTime(slotDate.year, slotDate.month, slotDate.day, 23, 59, 59);
    }
  }
  
  // ✅ FIXED: Enhanced method to handle past sessions with proper session counting
  Future<void> _markPastSessionsAsCompleted() async {
    try {
      final nowLocal = DateTime.now();
      print('🕒 Checking for past sessions at: ${nowLocal.toLocal()}');

      final allSlotsSnapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (final slotDoc in allSlotsSnapshot.docs) {
        final slotData = slotDoc.data();

        // Parse slot end time safely
        DateTime slotEndTime;
        if (slotData['slot_end_time'] != null) {
          slotEndTime = (slotData['slot_end_time'] as Timestamp).toDate().toLocal();
        } else {
          final slotDate = (slotData['date'] as Timestamp).toDate().toLocal();
          final slotTime = slotData['time'] as String? ?? '';
          slotEndTime = _parseSlotEndTime(slotTime, slotDate);
        }

        // ✅ Only mark completed if the end time has passed (in LOCAL time)
        if (slotEndTime.isBefore(nowLocal)) {
          final bookedBy = List<String>.from(slotData['booked_by'] ?? []);
          final purchaseIds = List<String>.from(slotData['purchase_ids'] ?? []);
          final userPurchaseMap = Map<String, dynamic>.from(slotData['user_purchase_map'] ?? {});
          final statusByUser = Map<String, dynamic>.from(slotData['status_by_user'] ?? {});

          for (int i = 0; i < bookedBy.length; i++) {
            final clientId = bookedBy[i];
            final purchaseId = i < purchaseIds.length
                ? purchaseIds[i]
                : userPurchaseMap[clientId];
            final userStatus = statusByUser[clientId] as String?;

            // Only process if session is still confirmed/rescheduled (not already completed)
            if ((userStatus == 'Confirmed' || userStatus == 'Rescheduled') &&
                purchaseId != null) {
              
              final purchaseDoc = await FirebaseFirestore.instance
                  .collection('client_purchases')
                  .doc(purchaseId)
                  .get();

              if (purchaseDoc.exists) {
                final purchaseData = purchaseDoc.data()!;
                final currentBooked = (purchaseData['bookedSessions'] as num?)?.toInt() ?? 0;
                final totalSessions = (purchaseData['totalSessions'] as num?)?.toInt() ?? 0;

                if (currentBooked > 0) {
                  // ✅ CORRECTED: Decrement booked sessions and update available sessions
                  final newBookedSessions = currentBooked; // DECREMENT booked
                  final newAvailableSessions = totalSessions - newBookedSessions;

                  batch.update(purchaseDoc.reference, {
                    'bookedSessions': newBookedSessions,
                    'availableSessions': newAvailableSessions,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  // Mark session as completed
                  statusByUser[clientId] = 'Completed';
                  hasUpdates = true;

                  print(
                      '✅ Marked session completed for $clientId (purchase $purchaseId) - '
                      'Booked: $newBookedSessions, '
                      'Available: $newAvailableSessions');
                }
              }
            }
          }

          if (hasUpdates) {
          batch.update(slotDoc.reference, {
            'status_by_user': statusByUser,
            'status': 'Completed', // ✅ ADD THIS LINE
            'last_updated': FieldValue.serverTimestamp(),
          });
        }
        }
      }

      if (hasUpdates) {
        await batch.commit();
        print('✅ Successfully processed past sessions');
      }
    } catch (e) {
      print('❌ Error marking past sessions: $e');
    }
  }
  DateTime _parseSlotDateTime(String slotTime, DateTime baseDate) {
    try {
      // Supports "5:30 AM - 6:30 AM", "17:30 - 18:30", and en-dash variants.
      final parts = _splitSlotRange(slotTime);
      if (parts.isEmpty) {
        throw const FormatException('Invalid slot range');
      }
      final startTime = _parseFlexibleTime(parts.first);

      // Create DateTime in LOCAL time (not UTC)
      return DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        startTime.hour,
        startTime.minute,
      );
    } catch (e) {
      print('❌ Error parsing slot time: $slotTime - $e');
      // Fallback to base date at midnight if parsing fails
      return DateTime(baseDate.year, baseDate.month, baseDate.day);
    }
  }
  Future<String?> _findAppropriatePurchaseId(String userId) async {
    try {
      final purchasesSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      if (purchasesSnapshot.docs.isEmpty) return null;

      final purchases = purchasesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'purchaseId': doc.id,
          'purchaseDate': (data['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime(1970),
          'totalSessions': data['totalSessions'] as int? ?? 0,
          'bookedSessions': (data['bookedSessions'] as num?)?.toInt() ?? 0,
          'availableSessions': (data['totalSessions'] as int? ?? 0) - 
                            ((data['bookedSessions'] as num?)?.toInt() ?? 0),
        };
      }).toList();

      // Sort by purchase date (oldest first) - FIFO
      purchases.sort((a, b) => (a['purchaseDate'] as DateTime).compareTo(b['purchaseDate'] as DateTime));

      // Find the first purchase with available sessions
      for (var purchase in purchases) {
        if ((purchase['availableSessions'] as int) > 0) {
          return purchase['purchaseId'] as String;
        }
      }

      // If no purchases have available sessions, return the oldest one
      return purchases.isNotEmpty ? purchases[0]['purchaseId'] as String : null;
    } catch (e) {
      print('❌ Error finding appropriate purchase: $e');
      return null;
    }
  }

  void _showPastSlotViewDialog(String docId) {
    final currentSlotData = _firestoreSlots[docId];
    final List<String> bookedNames = currentSlotData != null 
        ? List<String>.from(currentSlotData['booked_names'] ?? [])
        : [];
    final List<String> bookedEmails = currentSlotData != null
        ? List<String>.from(currentSlotData['booked_emails'] ?? [])
        : [];
    final Map<String, dynamic> statusByUser = currentSlotData != null
        ? Map<String, dynamic>.from(currentSlotData['status_by_user'] ?? {})
        : {};

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text("Past Session Details - View Only",  // Added "View Only" to make it clear
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E))),
              const SizedBox(height: 8),
              Text("Time: ${docId.split('|')[1]}",
                  style: const TextStyle(fontSize: 16, color: Colors.grey)),
              Text("Date: ${DateFormat('MMMM d, yyyy').format(_selectedDay)}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
              
              const SizedBox(height: 20),
              const Text("Booked Clients:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              if (bookedNames.isEmpty) 
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      "No bookings for this session",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: bookedNames.length,
                    itemBuilder: (context, index) {
                      final clientId = currentSlotData != null && 
                                      index < (currentSlotData['booked_by']?.length ?? 0)
                          ? (currentSlotData['booked_by'] as List)[index]
                          : '';
                      
                      final originalStatus = clientId.isNotEmpty ? statusByUser[clientId] ?? 'Confirmed' : 'Confirmed';

                      final status = originalStatus == 'Cancelled' ? 'Cancelled' : 'Completed';
                      final statusColor = originalStatus == 'Cancelled' ? Colors.red : Colors.green;
                      
                      return ListTile(
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(bookedNames[index]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bookedEmails.length > index ? bookedEmails[index] : ''),
                            Text(
                              'Status: $status',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C2D5E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CLOSE"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScheduledSlotViewDialog(String docId) {
    final currentSlotData = _firestoreSlots[docId];
    final List<String> bookedNames = currentSlotData != null 
        ? List<String>.from(currentSlotData['booked_names'] ?? [])
        : [];
    final List<String> bookedEmails = currentSlotData != null
        ? List<String>.from(currentSlotData['booked_emails'] ?? [])
        : [];
    final Map<String, dynamic> statusByUser = currentSlotData != null
        ? Map<String, dynamic>.from(currentSlotData['status_by_user'] ?? {})
        : {};
    final List<String> bookedBy = currentSlotData != null
        ? List<String>.from(currentSlotData['booked_by'] ?? [])
        : [];

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Scheduled Session - Booking Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E))),
              const SizedBox(height: 8),
              Text("Time: ${docId.split('|')[1]}",
                  style: const TextStyle(fontSize: 16, color: Colors.grey)),
              Text("Date: ${DateFormat('MMMM d, yyyy').format(_selectedDay)}",
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
              Text("Status: ${bookedNames.length}/${slotCapacity} booked",
                  style: const TextStyle(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.w600)),
              
              const SizedBox(height: 20),
              const Text("Booked Clients:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              if (bookedNames.isEmpty) 
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      "No bookings for this session",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 250,
                  child: ListView.builder(
                    itemCount: bookedNames.length,
                    itemBuilder: (context, index) {
                      final clientId = index < bookedBy.length ? bookedBy[index] : '';
                      final status = clientId.isNotEmpty ? statusByUser[clientId] ?? 'Confirmed' : 'Confirmed';
                      final statusColor = status == 'Cancelled' ? Colors.red : 
                                         status == 'Confirmed' ? Colors.green :
                                         status == 'Rescheduled' ? Colors.orange : Colors.grey;
                      
                      return ListTile(
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(bookedNames[index]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(bookedEmails.length > index ? bookedEmails[index] : ''),
                            Text(
                              'Status: $status',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            _cancelBookingDialog(docId, _firestoreSlots[docId]!);
                          },
                          tooltip: "Cancel this booking",
                        ),
                      );
                    },
                  ),
                ),
              
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("ADD BOOKING"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C2D5E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _bookForClientDialog(docId);
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("CLOSE"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ ADDED: Email notification function for booking confirmations
  Future<void> _sendBookingEmailNotification({
    required String clientEmail,
    required String clientName,
    required String slotTime,
    required DateTime slotDate,
    required String action, // 'booked' or 'cancelled'
  }) async {
    try {
      final emailData = {
        'to': clientEmail,
        'message': {
          'subject': action == 'booked' 
              ? 'Training Session Confirmed - ${DateFormat('MMMM d, yyyy').format(slotDate)}'
              : 'Training Session Cancelled - ${DateFormat('MMMM d, yyyy').format(slotDate)}',
          'text': action == 'booked'
              ? '''
Hello $clientName,

Your training session has been confirmed by the admin.

Session Details:
📅 Date: ${DateFormat('EEEE, MMMM d, yyyy').format(slotDate)}
⏰ Time: $slotTime
🏋️ Trainer: Kenny Sims

Please arrive 5-10 minutes before your scheduled time.

If you have any questions, please contact us.

Best regards,
Kenny Sims Fitness Team
'''
              : '''
Hello $clientName,

Your training session has been cancelled by the admin.

Session Details:
📅 Date: ${DateFormat('EEEE, MMMM d, yyyy').format(slotDate)}
⏰ Time: $slotTime

If you have any questions or would like to reschedule, please contact us.

Best regards,
Kenny Sims Fitness Team
''',
          'html': action == 'booked'
              ? '''
<html>
<body>
  <h2>Training Session Confirmed</h2>
  <p>Hello $clientName,</p>
  <p>Your training session has been confirmed by the admin.</p>
  
  <h3>Session Details:</h3>
  <ul>
    <li><strong>Date:</strong> ${DateFormat('EEEE, MMMM d, yyyy').format(slotDate)}</li>
    <li><strong>Time:</strong> $slotTime</li>
    <li><strong>Trainer:</strong> Kenny Sims</li>
  </ul>
  
  <p>Please arrive 5-10 minutes before your scheduled time.</p>
  <p>If you have any questions, please contact us.</p>
  
  <br>
  <p>Best regards,<br>Kenny Sims Fitness Team</p>
</body>
</html>
'''
              : '''
<html>
<body>
  <h2>Training Session Cancelled</h2>
  <p>Hello $clientName,</p>
  <p>Your training session has been cancelled by the admin.</p>
  
  <h3>Cancelled Session:</h3>
  <ul>
    <li><strong>Date:</strong> ${DateFormat('EEEE, MMMM d, yyyy').format(slotDate)}</li>
    <li><strong>Time:</strong> $slotTime</li>
  </ul>
  
  <p>If you have any questions or would like to reschedule, please contact us.</p>
  
  <br>
  <p>Best regards,<br>Kenny Sims Fitness Team</p>
</body>
</html>
''',
        },
        'type': 'booking_notification',
        'timestamp': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('mail').add(emailData);
      print('✅ Email notification sent to $clientEmail for $action session');
    } catch (e) {
      print('❌ Error sending email notification: $e');
      // Don't throw error - email failure shouldn't break the booking process
    }
  }
  // 📧 NEW: Email notification to trainer whenever admin updates a slot
  Future<void> _sendTrainerUpdateEmail({
    required String slotTime,
    required DateTime slotDate,
    required List<Map<String, String>> newBookings,
    required List<Map<String, String>> cancelledBookings,
  }) async {
    try {
      const String trainerEmail = 'Kenny@flextraining.co';

      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(slotDate);

      // Plain text body
      final StringBuffer textBuffer = StringBuffer()
        ..writeln('Hello Kenny,')
        ..writeln()
        ..writeln('The admin updated a training session.')
        ..writeln('Date: $dateStr')
        ..writeln('Time: $slotTime')
        ..writeln();

      if (newBookings.isNotEmpty) {
        textBuffer.writeln('New bookings:');
        for (final b in newBookings) {
          textBuffer.writeln('- ${b['name']} (${b['email']})');
        }
        textBuffer.writeln();
      }

      if (cancelledBookings.isNotEmpty) {
        textBuffer.writeln('Cancellations:');
        for (final c in cancelledBookings) {
          textBuffer.writeln('- ${c['name']} (${c['email']})');
        }
        textBuffer.writeln();
      }

      textBuffer.writeln('— Flex Facility Admin Panel');

      // HTML body
      final StringBuffer htmlBuffer = StringBuffer()
        ..writeln('<html><body>')
        ..writeln('<h2>Admin Updated Training Session</h2>')
        ..writeln('<p>Date: <strong>$dateStr</strong><br>')
        ..writeln('Time: <strong>$slotTime</strong></p>');

      if (newBookings.isNotEmpty) {
        htmlBuffer.writeln('<h3>New bookings:</h3><ul>');
        for (final b in newBookings) {
          htmlBuffer.writeln('<li>${b['name']} (${b['email']})</li>');
        }
        htmlBuffer.writeln('</ul>');
      }

      if (cancelledBookings.isNotEmpty) {
        htmlBuffer.writeln('<h3>Cancellations:</h3><ul>');
        for (final c in cancelledBookings) {
          htmlBuffer.writeln('<li>${c['name']} (${c['email']})</li>');
        }
        htmlBuffer.writeln('</ul>');
      }

      htmlBuffer
        ..writeln('<p>— Flex Facility Admin Panel</p>')
        ..writeln('</body></html>');

      final emailData = {
        'to': trainerEmail,
        'message': {
          'subject': 'Admin updated training session - $dateStr',
          'text': textBuffer.toString(),
          'html': htmlBuffer.toString(),
        },
        'type': 'trainer_booking_notification',
        'timestamp': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('mail').add(emailData);
      print('✅ Trainer update email queued for $trainerEmail');
    } catch (e) {
      print('❌ Error sending trainer update email: $e');
      // Don’t throw – trainer email failure shouldn’t break admin flow
    }
  }

  // ✅ FIXED: Enhanced booking dialog with proper session tracking and email notifications
  void _bookForClientDialog(String docId) async {
    final docParts = docId.split('|');
    if (docParts.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid slot format'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final slotDateKey = docParts[0];
    final slotTime = docParts[1];
    final slotDateParts = slotDateKey.split('-');
    final slotDate = DateTime(
      int.parse(slotDateParts[0]),
      int.parse(slotDateParts[1]),
      int.parse(slotDateParts[2]),
    );
    final isPastSlot = _isPastSlot(slotTime, slotDate);
    
    if (isPastSlot) {
      // Show view-only dialog for past slots
      _showPastSlotViewDialog(docId);
      return;
    }

    List<Map<String, dynamic>> clients = [];
    Map<String, bool> selectedClients = {};
    Map<String, String> selectedPurchaseIds = {};

    // Get current bookings for this slot to show tick marks
    final currentSlotData = _firestoreSlots[docId];
    final List<String> alreadyBookedClientIds = currentSlotData != null 
        ? List<String>.from(currentSlotData['booked_by'] ?? [])
        : [];

    try {
      // Get all active client purchases
      final activePurchasesSnapshot = await FirebaseFirestore.instance
          .collection('client_purchases')
          .where('status', isEqualTo: 'active')
          .get();

      // Organize purchases by user with proper session tracking
      final userPurchasesMap = <String, List<Map<String, dynamic>>>{};
      
      for (var purchaseDoc in activePurchasesSnapshot.docs) {
        final purchaseData = purchaseDoc.data();
        final userId = purchaseData['userId'] as String?;
        if (userId != null) {
          if (!userPurchasesMap.containsKey(userId)) {
            userPurchasesMap[userId] = [];
          }
          
          // Calculate available sessions correctly
          final totalSessions = purchaseData['totalSessions'] as int? ?? 0;
          final bookedSessions = purchaseData['bookedSessions'] as int? ?? 0;
          final availableSessions = totalSessions - bookedSessions;
          
          userPurchasesMap[userId]!.add({
            ...purchaseData,
            'purchaseId': purchaseDoc.id,
            'availableSessions': availableSessions,
            'planIndex': userPurchasesMap[userId]!.length, // Track order
          });
        }
      }

      // If no active clients, show message and return
      if (userPurchasesMap.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No clients with active plans found")),
        );
        return;
      }

      // Fetch only users who have active plans and are clients
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .where(FieldPath.documentId, whereIn: userPurchasesMap.keys.toList())
          .get();

      clients = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        final userId = doc.id;
        final userPurchases = userPurchasesMap[userId] ?? [];
        
        // ✅ FIXED: Sort purchases by purchase date (oldest first) - FIFO
        userPurchases.sort((a, b) {
          final dateA = (a['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime(1970);
          final dateB = (b['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime(1970);
          return dateA.compareTo(dateB);
        });

        // ✅ FIXED: Find the appropriate purchase for this client
        // This automatically progresses through plans as they get filled
        Map<String, dynamic>? selectedPurchase;
        int selectedPurchaseIndex = -1;
        
        for (int i = 0; i < userPurchases.length; i++) {
          final purchase = userPurchases[i];
          final availableSessions = purchase['availableSessions'] as int;
          
          // If this purchase has available sessions, use it
          if (availableSessions > 0) {
            selectedPurchase = purchase;
            selectedPurchaseIndex = i;
            break;
          }
        }
        
        // If no purchase has available sessions, use the first one (for display)
        if (selectedPurchase == null && userPurchases.isNotEmpty) {
          selectedPurchase = userPurchases[0];
          selectedPurchaseIndex = 0;
        }

        // Check if client is already booked for this slot
        final isAlreadyBooked = alreadyBookedClientIds.contains(userId);
        
        return {
          'uid': userId,
          'name': data['name'] ?? 'No name',
          'email': data['email'] ?? '',
          'allPurchases': userPurchases, // All available purchases
          'selectedPurchase': selectedPurchase,
          'selectedPurchaseIndex': selectedPurchaseIndex,
          'availableSessions': selectedPurchase?['availableSessions'] ?? 0,
          'planName': selectedPurchase?['planName'] ?? 'No Plan',
          'isAlreadyBooked': isAlreadyBooked,
          'hasMultiplePlans': userPurchases.length > 1,
        };
      }).toList();

      // Filter out clients with no available sessions (unless they're already booked)
      clients = clients.where((client) {
        final availableSessions = client['availableSessions'] as int;
        final isAlreadyBooked = client['isAlreadyBooked'] as bool;
        // Keep clients who have available sessions OR are already booked (to show them)
        return availableSessions > 0 || isAlreadyBooked;
      }).toList();

      // ✅ FIXED: Initialize selection state - pre-select already booked clients
      selectedClients = {
        for (var c in clients) 
          c['uid']: c['isAlreadyBooked']
      };
      
      // ✅ FIXED: Also pre-populate purchase IDs for already booked clients
      for (var client in clients) {
        if (client['isAlreadyBooked'] as bool) {
          selectedPurchaseIds[client['uid']] = client['selectedPurchase']?['purchaseId'];
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching active clients: $e")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Manage Slot Bookings",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E))),
                  const SizedBox(height: 8),
                  Text("Time: ${docId.split('|')[1]}",
                      style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  
                  const SizedBox(height: 20),
                  const Text("Manage Client Bookings:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    width: double.maxFinite,
                    child: clients.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 48, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  "No clients with available sessions",
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: clients.length,
                            itemBuilder: (context, index) {
                              final client = clients[index];
                              final availableSessions = client['availableSessions'] as int;
                              final planName = client['planName'] as String;
                              final isAlreadyBooked = client['isAlreadyBooked'] as bool;
                              final hasMultiplePlans = client['hasMultiplePlans'] as bool;
                              final allPurchases = client['allPurchases'] as List<Map<String, dynamic>>;
                              
                              return CheckboxListTile(
                                title: Row(
                                  children: [
                                    Text(client['name']),
                                    if (isAlreadyBooked) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                    ],
                                    if (hasMultiplePlans) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.layers, color: Colors.blue, size: 16),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(client['email']),
                                    Text(
                                      '$availableSessions session${availableSessions != 1 ? 's' : ''} available in $planName',
                                      style: TextStyle(
                                        color: availableSessions > 0 ? Colors.green : Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (hasMultiplePlans) 
                                      Text(
                                        '${allPurchases.length} active plan${allPurchases.length != 1 ? 's' : ''}',
                                        style: const TextStyle(fontSize: 10, color: Colors.blue),
                                      ),
                                  ],
                                ),
                                value: selectedClients[client['uid']] ?? false,
                                onChanged: (v) {
                                  if (v == true && availableSessions <= 0 && !isAlreadyBooked) {
                                    return;
                                  }
                                  
                                  setStateDialog(() {
                                    selectedClients[client['uid']] = v ?? false;
                                    if (v == true) {
                                      // ✅ FIXED: Always use the appropriate purchase (automatically progresses)
                                      selectedPurchaseIds[client['uid']] = client['selectedPurchase']?['purchaseId'];
                                    } else {
                                      selectedPurchaseIds.remove(client['uid']);
                                    }
                                  });
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                                secondary: availableSessions <= 0 
                                  ? const Icon(Icons.warning, color: Colors.red, size: 20)
                                  : null,
                                activeColor: isAlreadyBooked ? Colors.green : const Color(0xFF1C2D5E),
                                checkColor: isAlreadyBooked ? Colors.white : Colors.white,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("CANCEL"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C2D5E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          // ✅ IMMEDIATELY CLOSE THE DIALOG
                          Navigator.pop(context);
                          
                          try {
                            final selectedClientIds = selectedClients.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();
                            
                            // Separate already booked clients from new selections
                            final alreadyBookedClients = selectedClientIds.where((clientId) {
                              final client = clients.firstWhere((c) => c['uid'] == clientId);
                              return client['isAlreadyBooked'] as bool;
                            }).toList();
                            
                            final newClientIds = selectedClientIds.where((clientId) {
                              final client = clients.firstWhere((c) => c['uid'] == clientId);
                              return !(client['isAlreadyBooked'] as bool);
                            }).toList();

                            // Identify clients to be removed (unchecked previously booked clients)
                            final clientsToRemove = clients.where((client) {
                              final wasBooked = client['isAlreadyBooked'] as bool;
                              final isNowSelected = selectedClients[client['uid']] ?? false;
                              return wasBooked && !isNowSelected;
                            }).toList();

                            if (newClientIds.isEmpty && clientsToRemove.isEmpty) {
                              // No changes made
                              return;
                            }

                            final slotRef = FirebaseFirestore.instance
                                .collection('trainer_slots')
                                .doc(docId);

                            // ✅ PROCESS IN BACKGROUND AFTER DIALOG CLOSES
                            await FirebaseFirestore.instance.runTransaction((txn) async {
                              final snap = await txn.get(slotRef);
                              List bookedBy = [], bookedNames = [], bookedEmails = [], purchaseIds = [];
                              Map<String, dynamic> userPurchaseMap = {};
                              Map<String, dynamic> statusByUser = {};
                              
                              if (snap.exists) {
                                final data = snap.data()!;
                                bookedBy = List.from(data['booked_by'] ?? []);
                                bookedNames = List.from(data['booked_names'] ?? []);
                                bookedEmails = List.from(data['booked_emails'] ?? []);
                                purchaseIds = List.from(data['purchase_ids'] ?? []);
                                userPurchaseMap = Map<String, dynamic>.from(data['user_purchase_map'] ?? {});
                                statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});
                              }

                              // Remove clients that were unchecked
                              for (var client in clientsToRemove) {
                                final clientId = client['uid'];
                                final purchaseId = userPurchaseMap[clientId];
                                
                                // Find and remove from all arrays
                                final index = bookedBy.indexOf(clientId);
                                if (index != -1) {
                                  bookedBy.removeAt(index);
                                  if (index < bookedNames.length) bookedNames.removeAt(index);
                                  if (index < bookedEmails.length) bookedEmails.removeAt(index);
                                  if (index < purchaseIds.length) purchaseIds.removeAt(index);
                                }
                                
                                userPurchaseMap.remove(clientId);
                                statusByUser[clientId] = 'Cancelled';
                                
                                // Decrement booked sessions for removed client
                                if (purchaseId != null) {
                                  await _decrementBookedSessions(purchaseId);
                                }
                              }

                              // Check capacity for new bookings
                              for (var clientId in newClientIds) {
                                if (bookedBy.contains(clientId)) {
                                  throw Exception("Client is already booked");
                                }
                              }
                              
                              if (bookedBy.length + newClientIds.length > slotCapacity) {
                                throw Exception("Not enough capacity");
                              }

                              // Add new clients to booking
                              final newClientsData = clients
                                  .where((c) => newClientIds.contains(c['uid']))
                                  .toList();

                              for (var client in newClientsData) {
                                final clientId = client['uid'];
                                final clientEmail = client['email'];
                                final purchaseId = selectedPurchaseIds[clientId];
                                // Safety check to prevent double booking
                                if (bookedBy.contains(clientId)) {
                                  continue;
                                }
                                // Increment booked sessions BEFORE adding to slot
                                if (purchaseId != null) {
                                  await _incrementBookedSessions(purchaseId);
                                }
                                // --- Ensure both booked_by and booked_emails are updated together ---
                                bookedBy.add(clientId);
                                bookedEmails.add(clientEmail);
                                bookedNames.add(client['name']);
                                purchaseIds.add(purchaseId);
                                userPurchaseMap[clientId] = purchaseId;
                                statusByUser[clientId] = 'Confirmed';
                              }

                              // Parse slot times
                              // Parse slot times
                              final slotTime = docId.split('|')[1];
                              final slotDateTime = _parseSlotDateTime(slotTime, slotDate);
                              final slotEndTime = _parseSlotEndTime(slotTime, slotDate);

                              final fullData = {
                                'booked_by': bookedBy,
                                'booked_names': bookedNames,
                                'booked_emails': bookedEmails,
                                'purchase_ids': purchaseIds,
                                'user_purchase_map': userPurchaseMap,
                                'status_by_user': statusByUser,
                                'booked': bookedBy.length,
                                'capacity': slotCapacity,
                                'trainer_name': 'Kenny Sims',
                                'status': 'Confirmed',
                                'time': slotTime,
                                'trainer_email': 'Kenny@flextraining.co',
                                'date': Timestamp.fromDate(DateTime(
                                  slotDate.year,
                                  slotDate.month,
                                  slotDate.day,
                                  slotDateTime.hour,
                                  slotDateTime.minute,
                                )), // ← REMOVE .toUtc()
                                'slot_end_time': Timestamp.fromDate(DateTime(
                                  slotDate.year,
                                  slotDate.month,
                                  slotDate.day,
                                  slotEndTime.hour,
                                  slotEndTime.minute,
                                )), // ← REMOVE .toUtc()
                                'last_updated': FieldValue.serverTimestamp(),
                                'client_user_ids': bookedBy,
                              };

                              txn.set(slotRef, fullData);
                            });

                            // ✅ SEND EMAIL NOTIFICATIONS FOR NEW BOOKINGS AND CANCELLATIONS
                            try {
                              // Send cancellation emails
                              for (var client in clientsToRemove) {
                                await _sendBookingEmailNotification(
                                  clientEmail: client['email'] as String,
                                  clientName: client['name'] as String,
                                  slotTime: slotTime,
                                  slotDate: slotDate,
                                  action: 'cancelled',
                                );
                              }

                              // Send booking confirmation emails for new bookings
                              final newClientsData = clients
                                  .where((c) => newClientIds.contains(c['uid']))
                                  .toList();
                              for (var client in newClientsData) {
                                await _sendBookingEmailNotification(
                                  clientEmail: client['email'] as String,
                                  clientName: client['name'] as String,
                                  slotTime: slotTime,
                                  slotDate: slotDate,
                                  action: 'booked',
                                );
                              }
// 📧 NEW: Trainer summary email (bookings + cancellations)
                              final trainerNewBookings = newClientsData
                                  .map<Map<String, String>>((client) => {
                                        'name': client['name'] as String? ?? '',
                                        'email': client['email'] as String? ?? '',
                                      })
                                  .toList();

                              final trainerCancelled = clientsToRemove
                                  .map<Map<String, String>>((client) => {
                                        'name': client['name'] as String? ?? '',
                                        'email': client['email'] as String? ?? '',
                                      })
                                  .toList();

                              if (trainerNewBookings.isNotEmpty ||
                                  trainerCancelled.isNotEmpty) {
                                await _sendTrainerUpdateEmail(
                                  slotTime: slotTime,
                                  slotDate: slotDate,
                                  newBookings: trainerNewBookings,
                                  cancelledBookings: trainerCancelled,
                                );
                              }


                            } catch (emailError) {
                              print('⚠️ Email notifications partially failed: $emailError');
                              // Don't show error to user - email failure shouldn't affect booking
                            }

                            // ✅ SHOW SUCCESS MESSAGE AFTER PROCESSING
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Bookings updated successfully"),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              
                              // Refresh the slots data to update UI
                              _listenToDay(_selectedDay);
                            }
                          } catch (e) {
                            // ✅ SHOW ERROR MESSAGE IF SOMETHING FAILS
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        child: const Text("CONFIRM"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isPastSlot(String slotTime, DateTime slotDate) {
    try {
      final now = DateTime.now();

      final today = DateTime(now.year, now.month, now.day);
      final selected = DateTime(slotDate.year, slotDate.month, slotDate.day);

      // ✅ FULL DAY PASSED
      if (selected.isBefore(today)) {
        return true;
      }

      // ✅ FUTURE DATE
      if (selected.isAfter(today)) {
        return false;
      }

      // ✅ TODAY → check slot end time
      final slotEndTime = _parseSlotEndTime(slotTime, slotDate);

      return now.isAfter(slotEndTime);
    } catch (e) {
      return false;
    }
  }

  // ✅ FIXED: Enhanced method to increment booked sessions (matches client-side logic)
  Future<void> _incrementBookedSessions(String purchaseId) async {
    try {
      final purchaseRef = FirebaseFirestore.instance
          .collection('client_purchases')
          .doc(purchaseId);

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(purchaseRef);
        if (!snap.exists) throw Exception("Purchase not found");

        final data = snap.data()!;
        final totalSessions = data['totalSessions'] as int? ?? 0;
        final currentBooked = (data['bookedSessions'] as num?)?.toInt() ?? 0;
        
        // ✅ FIX: Only update booked sessions, NOT used/remaining sessions
        // Used sessions will be updated automatically when session time passes
        final newBookedCount = currentBooked + 1;
        final newAvailableSessions = totalSessions - newBookedCount;

        // ✅ FIX: Update ONLY booked and available sessions (like client side)
        txn.update(purchaseRef, {
          'bookedSessions': newBookedCount,
          'availableSessions': newAvailableSessions,
          // ⚠️ DON'T update usedSessions or remainingSessions here
          // They will be updated when the session actually completes
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      print('✅ Admin updated purchase $purchaseId: Booked +1 session (Available sessions decreased)');
    } catch (e) {
      print('❌ Error updating purchase sessions: $e');
      rethrow;
    }
  }

  Future<void> _decrementBookedSessions(String purchaseId) async {
    try {
      final purchaseRef = FirebaseFirestore.instance
          .collection('client_purchases')
          .doc(purchaseId);

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(purchaseRef);
        if (!snap.exists) {
          print('❌ Purchase document not found: $purchaseId');
          return;
        }

        final data = snap.data()!;
        final totalSessions = data['totalSessions'] as int? ?? 0;
        final currentBooked = (data['bookedSessions'] as num?)?.toInt() ?? 0;
        
        if (currentBooked > 0) {
          final newBookedCount = currentBooked - 1; // ✅ ACTUALLY DECREMENT
          final newAvailableSessions = totalSessions - newBookedCount;

          // ✅ FIX: Update booked and available sessions
          txn.update(purchaseRef, {
            'bookedSessions': newBookedCount,
            'availableSessions': newAvailableSessions,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
          print('✅ Admin decremented purchase $purchaseId: Booked: $newBookedCount, Available: $newAvailableSessions');
        } else {
          print('ℹ️ No booked sessions to decrement for purchase: $purchaseId');
        }
      });
    } catch (e) {
      print('❌ Error decrementing purchase sessions: $e');
      rethrow; // Important: rethrow to handle in calling method
    }
  }

  void _cancelBookingDialog(String docId, Map<String, dynamic> slotData) {
    final bookedNames = List<String>.from(slotData['booked_names'] ?? []);
    final bookedUids = List<String>.from(slotData['booked_by'] ?? []);
    final purchaseIds = List<String>.from(slotData['purchase_ids'] ?? []);
    final userPurchaseMap = Map<String, dynamic>.from(slotData['user_purchase_map'] ?? {});
    final bookedEmails = List<String>.from(slotData['booked_emails'] ?? []);

    // Add validation to prevent errors if arrays are empty or mismatched
    if (bookedNames.isEmpty || bookedUids.isEmpty || bookedNames.length != bookedUids.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Invalid booking data")),
      );
      return;
    }

    final Map<String, bool> selectedClients = {
      for (var i = 0; i < bookedUids.length; i++) 
        bookedUids[i]: false
    };

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("Cancel Bookings"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Time: ${docId.split('|')[1]}"),
                  const SizedBox(height: 16),
                  const Text("Select Clients to Cancel:"),
                  const SizedBox(height: 8),
                  ...bookedNames.asMap().entries.map((entry) {
                    final index = entry.key;
                    final name = entry.value;
                    final clientId = bookedUids[index];
                    final clientEmail = index < bookedEmails.length ? bookedEmails[index] : '';
                    
                    return CheckboxListTile(
                      title: Text(name),
                      subtitle: clientEmail.isNotEmpty ? Text(clientEmail) : null,
                      value: selectedClients[clientId] ?? false,
                      onChanged: (value) {
                        if (index >= 0 && index < bookedUids.length) {
                          setStateDialog(() {
                            selectedClients[clientId] = value ?? false;
                          });
                        }
                      },
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1C2D5E), // App primary blue
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () async {
                  // ✅ IMMEDIATELY CLOSE THE DIALOG
                  Navigator.pop(context);
                  
                  try {
                    final selectedClientIds = selectedClients.entries
                        .where((e) => e.value)
                        .map((e) => e.key)
                        .toList();

                    if (selectedClientIds.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please select at least one client")),
                      );
                      return;
                    }

                    final slotRef = FirebaseFirestore.instance
                        .collection('trainer_slots')
                        .doc(docId);

                    // ✅ PROCESS IN BACKGROUND AFTER DIALOG CLOSES
                    await FirebaseFirestore.instance.runTransaction((txn) async {
                      final snap = await txn.get(slotRef);
                      if (!snap.exists) throw Exception("Slot not found");

                      final data = snap.data()!;
                      List bookedBy = List.from(data['booked_by'] ?? []);
                      List bookedNames = List.from(data['booked_names'] ?? []);
                      List bookedEmails = List.from(data['booked_emails'] ?? []);
                      List purchaseIds = List.from(data['purchase_ids'] ?? []);
                      Map<String, dynamic> userPurchaseMap = Map<String, dynamic>.from(data['user_purchase_map'] ?? {});
                      Map<String, dynamic> statusByUser = Map<String, dynamic>.from(data['status_by_user'] ?? {});

                      // Safe removal using indices
                      for (var i = bookedBy.length - 1; i >= 0; i--) {
                        if (selectedClientIds.contains(bookedBy[i])) {
                          final clientId = bookedBy[i];
                          final purchaseId = userPurchaseMap[clientId];
                          final clientName = i < bookedNames.length ? bookedNames[i] : '';
                          final clientEmail = i < bookedEmails.length ? bookedEmails[i] : '';
                          
                          // Remove from arrays
                          if (i < bookedNames.length) bookedNames.removeAt(i);
                          if (i < bookedEmails.length) bookedEmails.removeAt(i);
                          if (i < purchaseIds.length) purchaseIds.removeAt(i);
                          
                          userPurchaseMap.remove(clientId);
                          statusByUser[clientId] = 'Cancelled';
                          bookedBy.removeAt(i);
                          
                          // ✅ DECREMENT BOOKED SESSIONS
                          if (purchaseId != null) {
                            try {
                              await _decrementBookedSessions(purchaseId.toString());
                              print('✅ Successfully decremented sessions for client: $clientId');
                            } catch (e) {
                              print('❌ Failed to decrement sessions for client $clientId: $e');
                            }
                          }
                        }
                      }

                      txn.set(
                        slotRef,
                        {
                          'booked_by': bookedBy,
                          'booked_names': bookedNames,
                          'booked_emails': bookedEmails,
                          'purchase_ids': purchaseIds,
                          'user_purchase_map': userPurchaseMap,
                          'status_by_user': statusByUser,
                          'booked': bookedBy.length,
                          'last_updated': FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true),
                      );
                    });

                    // ✅ SEND CANCELLATION EMAIL NOTIFICATIONS
                                       // ✅ SEND CANCELLATION EMAIL NOTIFICATIONS
                    try {
                      final slotTime = docId.split('|')[1];

                      // For trainer summary
                      final List<Map<String, String>> trainerCancelled = [];

                      for (var clientId in selectedClientIds) {
                        final clientIndex = bookedUids.indexOf(clientId);
                        if (clientIndex != -1 &&
                            clientIndex < bookedNames.length &&
                            clientIndex < bookedEmails.length) {
                          final name = bookedNames[clientIndex];
                          final email = bookedEmails[clientIndex];

                          // Client email
                          await _sendBookingEmailNotification(
                            clientEmail: email,
                            clientName: name,
                            slotTime: slotTime,
                            slotDate: _selectedDay,
                            action: 'cancelled',
                          );

                          // Add to trainer summary
                          trainerCancelled.add({
                            'name': name,
                            'email': email,
                          });
                        }
                      }

                      // 📧 NEW: Trainer summary email (only cancellations here)
                      if (trainerCancelled.isNotEmpty) {
                        await _sendTrainerUpdateEmail(
                          slotTime: slotTime,
                          slotDate: _selectedDay,
                          newBookings: const <Map<String, String>>[],
                          cancelledBookings: trainerCancelled,
                        );
                      }
                    } catch (emailError) {

                      print('⚠️ Email notifications partially failed: $emailError');
                      // Don't show error to user - email failure shouldn't affect cancellation
                    }

                    // ✅ SHOW SUCCESS MESSAGE AND UPDATE UI
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Cancelled successfully"),
                          backgroundColor: Colors.green,
                        ),
                      );
                      
                      // ✅ IMMEDIATELY REFRESH THE UI
                      _listenToDay(_selectedDay);
                    }
                  } catch (e) {
                    // ✅ SHOW ERROR MESSAGE IF SOMETHING FAILS
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error: $e"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text("CONFIRM CANCEL"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final slotLabels = generateHourlySlots(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Trainer Schedule",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C2D5E),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar, color: Colors.white),
            tooltip: 'Manage Schedule',
            onPressed: _showManageScheduleDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TableCalendar(
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                onDaySelected: (day, _) {
                  setState(() {
                    _selectedDay = day;
                    _focusedDay = day;
                  });
                  _listenToDay(day);
                },
                headerStyle: const HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  leftChevronIcon: Icon(Icons.chevron_left, color: Color(0xFF1C2D5E)),
                  rightChevronIcon: Icon(Icons.chevron_right, color: Color(0xFF1C2D5E)),
                  headerMargin: EdgeInsets.only(bottom: 8),
                ),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: const Color(0xFF1C2D5E).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: Color(0xFF1C2D5E),
                    shape: BoxShape.circle,
                  ),
                  weekendTextStyle: const TextStyle(color: Colors.black),
                  outsideDaysVisible: false,
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20, color: Color(0xFF1C2D5E)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: slotLabels.length,
                  itemBuilder: (context, index) {
                    final time = slotLabels[index];
                    final docId = "$dateKey|$time";
                    final data = _firestoreSlots[docId];
                    final isFull = data != null && (data['booked_by']?.length ?? 0) >= slotCapacity;
                    final bookedNames = List<String>.from(data?['booked_names'] ?? []);
                    final bookedCount = bookedNames.length;
                    final hasBookings = bookedCount > 0;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  // Replace the availability indicator part with:
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _isPastSlot(slotLabels[index], _selectedDay) ? Colors.orange : 
                                                isFull ? Colors.red : Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isPastSlot(slotLabels[index], _selectedDay) ? "Unavailable" : 
                                        isFull ? "Fully Booked" : "Available",
                                        style: TextStyle(
                                          color: _isPastSlot(slotLabels[index], _selectedDay) ? Colors.orange : 
                                                isFull ? Colors.red : Colors.green,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "$bookedCount / $slotCapacity",
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  if (bookedNames.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () => _showScheduledSlotViewDialog(docId),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.blue, width: 0.5),
                                        ),
                                        child: Text(
                                          "👥 ${bookedNames.join(', ')}",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            
                            const SizedBox(width: 12),
                            if (hasBookings && !_isPastSlot(slotLabels[index], _selectedDay))
                              IconButton(
                                icon: const Icon(Icons.visibility, color: Color(0xFF1C2D5E)),
                                onPressed: () => _showScheduledSlotViewDialog(docId),
                                tooltip: "View bookings",
                              ),
                            if (hasBookings && !_isPastSlot(slotLabels[index], _selectedDay))
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => _cancelBookingDialog(docId, data!),
                                tooltip: "Cancel bookings",
                              ),
                            ElevatedButton(
                              onPressed: () {
                                final isPastSlot = _isPastSlot(slotLabels[index], _selectedDay);
                                if (isPastSlot) {
                                  _showPastSlotViewDialog(docId);
                                } else if (hasBookings) {
                                  _showScheduledSlotViewDialog(docId);
                                } else if (!isFull) {
                                  _bookForClientDialog(docId);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isPastSlot(slotLabels[index], _selectedDay) ? Colors.orange : 
                                              isFull ? Colors.grey[300] : const Color(0xFF1C2D5E),
                                foregroundColor: _isPastSlot(slotLabels[index], _selectedDay) ? Colors.white :
                                              isFull ? Colors.grey : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                _isPastSlot(slotLabels[index], _selectedDay) ? "VIEW" :
                                hasBookings ? "BOOKINGS" :
                                isFull ? "FULL" : "BOOK"
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}