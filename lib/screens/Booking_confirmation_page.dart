import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class BookingConfirmationPage extends StatefulWidget {
  final DateTime selectedDate;
  final String selectedTime;
  final String trainerName;
  final int slotCapacity;
  final Map<String, dynamic>? rescheduleSlot;
  final String purchaseId;
  final Map<String, dynamic> purchaseData;

  const BookingConfirmationPage({
    Key? key,
    required this.selectedDate,
    required this.selectedTime,
    required this.trainerName,
    required this.slotCapacity,
    this.rescheduleSlot,
    required this.purchaseId,
    required this.purchaseData,
  }) : super(key: key);

  @override
  State<BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  bool _loading = false;
  bool _success = false;
  Map<String, dynamic>? _activePlan;

  @override
  void initState() {
    super.initState();
    _loadActivePlan();
  }

  Future<void> _loadActivePlan() async {
    final status = widget.purchaseData['status'] ?? 'inactive';
    final totalSessions = widget.purchaseData['totalSessions'] ?? 0;
    final bookedSessions = widget.purchaseData['bookedSessions'] ?? 0;
    final availableSessions = totalSessions - bookedSessions;

    setState(() {
      _activePlan = {
        'planName': widget.purchaseData['planName'] ?? 'General Training',
        'planId': widget.purchaseData['planId'] ?? 'general',
        'purchaseId': widget.purchaseId,
        'remainingSessions': widget.purchaseData['remainingSessions'] ?? 0,
        'totalSessions': totalSessions,
        'bookedSessions': bookedSessions,
        'availableSessions': availableSessions,
        'price': widget.purchaseData['price'] ?? 0.0,
        'status': status,
      };
    });

    print('🎯 Booking Confirmation - Active Plan Loaded:');
    print('   Plan Name: ${_activePlan!['planName']}');
    print('   Purchase ID: ${_activePlan!['purchaseId']}');
    print('   Total Sessions: ${_activePlan!['totalSessions']}');
    print('   Booked Sessions: ${_activePlan!['bookedSessions']}');
    print('   Available Sessions: ${_activePlan!['availableSessions']}');
    print('   Status: $status');
  }

  Future<void> _confirmBooking() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to continue')),
      );
      return;
    }

    // ✅ ALLOW RESCHEDULE WITHOUT ACTIVE PLAN
    bool isReschedule = widget.rescheduleSlot != null;

    if (isReschedule) {
      // For reschedule, proceed even without active plan
      await _processRescheduleWithoutPlan(user);
      return;
    }

    // ✅ Enhanced validation for NEW bookings only
    if (_activePlan == null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('No active plan found. Please purchase a plan first.')),
      );
      return;
    }

    final remainingSessions = _activePlan!['remainingSessions'] as int;
    final purchaseId = _activePlan!['purchaseId'] as String;

    if (remainingSessions <= 0) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('No remaining sessions in your active plan.')),
      );
      return;
    }

    // ✅ Validate purchase document exists before proceeding (for new bookings)
    try {
      final purchaseDoc = await FirebaseFirestore.instance
          .collection('client_purchases')
          .doc(purchaseId)
          .get();

      if (!purchaseDoc.exists) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Purchase record not found. Please contact support.')),
        );
        return;
      }

      final purchaseData = purchaseDoc.data();
      final actualRemaining =
          purchaseData?['remainingSessions'] as int? ?? 0;

      if (actualRemaining <= 0) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'No remaining sessions available. Please refresh and try again.')),
        );
        return;
      }

      print('✅ Pre-validation passed:');
      print('   Purchase ID: $purchaseId');
      print('   Remaining Sessions: $actualRemaining');

      await _processBooking(user, purchaseId, isReschedule: false);
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Validation error: ${e.toString()}')),
      );
      return;
    }
  }

  // NEW METHOD: Handle reschedule without requiring active plan
  Future<void> _processRescheduleWithoutPlan(User user) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName = userDoc.data()?['name'] ?? 'Client';
      final userEmail = userDoc.data()?['email'] ?? '';

      final dateKey = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final newDocId = "$dateKey|${widget.selectedTime}";
      final newRef =
          FirebaseFirestore.instance.collection('trainer_slots').doc(newDocId);

      final startTimeRaw = widget.selectedTime.split(' - ').first.trim();
      final parsedStart = DateFormat.jm().parseLoose(startTimeRaw);
      final fullDateTime = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        parsedStart.hour,
        parsedStart.minute,
      );

      final String? oldDocId = widget.rescheduleSlot?['id'] as String?;
      final oldRef = (oldDocId != null && oldDocId.isNotEmpty)
          ? FirebaseFirestore.instance
              .collection('trainer_slots')
              .doc(oldDocId)
          : null;

      await FirebaseFirestore.instance.runTransaction((txn) async {
        print(
            '🔄 Starting RESCHEDULE transaction (no active plan):');
        print('   New Slot ID: $newDocId');
        print('   Old Slot ID: $oldDocId');

        final newSnap = await txn.get(newRef);
        DocumentSnapshot<Map<String, dynamic>>? oldSnap;
        if (oldRef != null) oldSnap = await txn.get(oldRef);

        // ----- NEW SLOT -----
        List bookedByNew = [];
        List bookedNamesNew = [];
        List bookedEmailsNew = [];
        List purchaseIdsNew = [];
        Map<String, dynamic> userPurchaseMapNew = {};

        if (newSnap.exists) {
          final d = newSnap.data() as Map<String, dynamic>;
          bookedByNew = List.from(d['booked_by'] ?? []);
          bookedNamesNew = List.from(d['booked_names'] ?? []);
          bookedEmailsNew = List.from(d['booked_emails'] ?? []);
          purchaseIdsNew = List.from(d['purchase_ids'] ?? []);
          userPurchaseMapNew =
              Map<String, dynamic>.from(d['user_purchase_map'] ?? {});
        }

        final alreadyInNew = bookedByNew.contains(user.uid);
        if (!alreadyInNew &&
            bookedByNew.length >= widget.slotCapacity) {
          throw Exception('This slot is full.');
        }

        // ----- OLD SLOT (for reschedule) -----
        List? bookedByOld, bookedNamesOld, bookedEmailsOld,
            purchaseIdsOld;
        Map<String, dynamic>? userPurchaseMapOld;
        String? oldPurchaseId;

        if (oldSnap != null && oldSnap.exists) {
          final od = oldSnap.data() as Map<String, dynamic>;
          bookedByOld = List.from(od['booked_by'] ?? []);
          bookedNamesOld = List.from(od['booked_names'] ?? []);
          bookedEmailsOld = List.from(od['booked_emails'] ?? []);
          purchaseIdsOld = List.from(od['purchase_ids'] ?? []);
          userPurchaseMapOld =
              Map<String, dynamic>.from(od['user_purchase_map'] ?? {});

          final idx = bookedByOld.indexOf(user.uid);
          if (idx != -1) {
            oldPurchaseId =
                userPurchaseMapOld[user.uid] as String?;

            // Get user data from old slot before removing
            final oldUserName =
                idx < bookedNamesOld.length ? bookedNamesOld[idx] : userName;
            final oldUserEmail =
                idx < bookedEmailsOld.length ? bookedEmailsOld[idx] : userEmail;

            bookedByOld.removeAt(idx);
            if (idx < bookedNamesOld.length) {
              bookedNamesOld.removeAt(idx);
            }
            if (idx < bookedEmailsOld.length) {
              bookedEmailsOld.removeAt(idx);
            }
            if (idx < purchaseIdsOld.length) {
              purchaseIdsOld.removeAt(idx);
            }
            userPurchaseMapOld.remove(user.uid);

            // Add to new slot using data from old slot
            if (!alreadyInNew) {
              bookedByNew.add(user.uid);
              bookedNamesNew.add(oldUserName);
              bookedEmailsNew.add(oldUserEmail);
              if (oldPurchaseId != null) {
                purchaseIdsNew.add(oldPurchaseId);
                userPurchaseMapNew[user.uid] = oldPurchaseId;
              }
            }
          }
        }

        // ----- WRITE SLOT UPDATES -----
        txn.set(
          newRef,
          {
            'date': Timestamp.fromDate(fullDateTime),
            'time': widget.selectedTime,
            'trainer_name': widget.trainerName,
            'trainer_email': 'srihemaparvathaneni@gmail.com', 
            'capacity': widget.slotCapacity,
            'booked': bookedByNew.length,
            'booked_by': bookedByNew,
            'booked_names': bookedNamesNew,
            'booked_emails': bookedEmailsNew,
            'purchase_ids': purchaseIdsNew,
            'user_purchase_map': userPurchaseMapNew,
            'last_updated': FieldValue.serverTimestamp(),
            'status_by_user': {user.uid: 'Rescheduled'},
            // Use plan info from old slot if available, otherwise use defaults
            'planName':
                widget.rescheduleSlot?['planName'] ?? 'General Training',
            'planId': widget.rescheduleSlot?['planId'] ?? 'general',
          },
          SetOptions(merge: true),
        );

        if (oldRef != null && oldSnap != null && oldSnap.exists) {
          txn.update(oldRef, {
            'booked': bookedByOld!.length,
            'booked_by': bookedByOld,
            'booked_names': bookedNamesOld,
            'booked_emails': bookedEmailsOld,
            'purchase_ids': purchaseIdsOld,
            'user_purchase_map': userPurchaseMapOld,
            'last_updated': FieldValue.serverTimestamp(),
            'status_by_user': {user.uid: 'Cancelled'},
          });
        }
      });

      // 📧 NEW: notify trainer about reschedule
      try {
        await _sendTrainerNotificationEmail(
          action: 'Rescheduled',
          clientName: userName,
          clientEmail: userEmail,
          date: widget.selectedDate,
          time: widget.selectedTime,
          oldSlotInfo: oldDocId, // e.g. "2025-11-13|5:30 AM - 6:30 AM"
        );
      } catch (emailError) {
        print('⚠️ Trainer email (reschedule) failed: $emailError');
      }

      setState(() {
        _loading = false;
        _success = true;
      });

      print('✅ Reschedule completed successfully without active plan!');
    } catch (e) {
      setState(() => _loading = false);
      print('❌ Reschedule error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reschedule error: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // CHANGE THIS: Update the method to accept isReschedule parameter
  // CHANGE THIS: Update the method to NOT decrement remaining sessions during booking
  Future<void> _processBooking(
    User user,
    String purchaseId, {
    bool isReschedule = false,
  }) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName = userDoc.data()?['name'] ?? 'Client';
      final userEmail = userDoc.data()?['email'] ?? '';

      final planName = _activePlan!['planName'] as String;
      final planId = _activePlan!['planId'] as String;

      final dateKey = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final newDocId = "$dateKey|${widget.selectedTime}";
      final newRef =
          FirebaseFirestore.instance.collection('trainer_slots').doc(newDocId);

      final startTimeRaw = widget.selectedTime.split(' - ').first.trim();
      final parsedStart = DateFormat.jm().parseLoose(startTimeRaw);
      final fullDateTime = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        parsedStart.hour,
        parsedStart.minute,
      );

      final String? oldDocId = widget.rescheduleSlot?['id'] as String?;
      final oldRef = (oldDocId != null && oldDocId.isNotEmpty)
          ? FirebaseFirestore.instance
              .collection('trainer_slots')
              .doc(oldDocId)
          : null;

      String? oldPurchaseId;
      bool isRescheduleLocal = widget.rescheduleSlot != null;

      await FirebaseFirestore.instance.runTransaction((txn) async {
        print('🚀 Starting booking transaction:');
        print('   New Slot ID: $newDocId');
        print('   Purchase ID: $purchaseId');
        print('   Plan: $planName');
        print('   Is Reschedule: $isRescheduleLocal');

        final newSnap = await txn.get(newRef);

        DocumentSnapshot<Map<String, dynamic>>? oldSnap;
        if (oldRef != null) oldSnap = await txn.get(oldRef);

        // ----- NEW SLOT -----
        List bookedByNew = [];
        List bookedNamesNew = [];
        List bookedEmailsNew = [];
        List purchaseIdsNew = [];
        Map<String, dynamic> userPurchaseMapNew = {};

        if (newSnap.exists) {
          final d = newSnap.data() as Map<String, dynamic>;
          bookedByNew = List.from(d['booked_by'] ?? []);
          bookedNamesNew = List.from(d['booked_names'] ?? []);
          bookedEmailsNew = List.from(d['booked_emails'] ?? []);
          purchaseIdsNew = List.from(d['purchase_ids'] ?? []);
          userPurchaseMapNew =
              Map<String, dynamic>.from(d['user_purchase_map'] ?? {});
        }

        final alreadyInNew = bookedByNew.contains(user.uid);
        if (!alreadyInNew &&
            bookedByNew.length >= widget.slotCapacity) {
          throw Exception('This slot is full.');
        }

        if (!alreadyInNew) {
          bookedByNew.add(user.uid);
          bookedNamesNew.add(userName);
          bookedEmailsNew.add(userEmail);
          purchaseIdsNew.add(purchaseId);
          userPurchaseMapNew[user.uid] = purchaseId;
        }

        // ----- OLD SLOT (for reschedule) -----
        List? bookedByOld, bookedNamesOld, bookedEmailsOld,
            purchaseIdsOld;
        Map<String, dynamic>? userPurchaseMapOld;

        if (oldSnap != null && oldSnap.exists) {
          final od = oldSnap.data() as Map<String, dynamic>;
          bookedByOld = List.from(od['booked_by'] ?? []);
          bookedNamesOld = List.from(od['booked_names'] ?? []);
          bookedEmailsOld = List.from(od['booked_emails'] ?? []);
          purchaseIdsOld = List.from(od['purchase_ids'] ?? []);
          userPurchaseMapOld =
              Map<String, dynamic>.from(od['user_purchase_map'] ?? {});

          final idx = bookedByOld.indexOf(user.uid);
          if (idx != -1) {
            oldPurchaseId =
                userPurchaseMapOld[user.uid] as String?;

            bookedByOld.removeAt(idx);
            if (idx < bookedNamesOld.length) {
              bookedNamesOld.removeAt(idx);
            }
            if (idx < bookedEmailsOld.length) {
              bookedEmailsOld.removeAt(idx);
            }
            if (idx < purchaseIdsOld.length) {
              purchaseIdsOld.removeAt(idx);
            }
            userPurchaseMapOld.remove(user.uid);
          }
        }

        // ✅ FIX: Update booked sessions and recalculate available sessions
        if (!isRescheduleLocal) {
          final purchaseRef = FirebaseFirestore.instance
              .collection('client_purchases')
              .doc(purchaseId);

          final purchaseSnap = await txn.get(purchaseRef);
          if (purchaseSnap.exists) {
            final purchaseData = purchaseSnap.data()!;
            final currentBooked =
                (purchaseData['bookedSessions'] as num?)?.toInt() ??
                    0;
            final totalSessions =
                (purchaseData['totalSessions'] as num?)?.toInt() ??
                    0;

            // ✅ CRITICAL FIX: Calculate available sessions from total - booked
            final newBookedCount = currentBooked + 1;
            final newAvailableSessions =
                totalSessions - newBookedCount;

            // ✅ Validate available sessions
            if (newAvailableSessions < 0) {
              throw Exception(
                  'No available sessions in the selected plan.');
            }

            // ✅ FIX: Update both booked sessions AND recalculate available sessions
            txn.update(purchaseRef, {
              'bookedSessions': newBookedCount,
              'availableSessions': newAvailableSessions,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            print(
                '📊 Updated sessions for NEW booking. Booked: $newBookedCount, Available: $newAvailableSessions, Total: $totalSessions');
          } else {
            throw Exception('Purchase plan not found.');
          }
        } else {
          print(
              '🔄 Reschedule detected - NOT updating session counts');
        }

        // ----- WRITE SLOT UPDATES -----
        txn.set(
          newRef,
          {
            'date': Timestamp.fromDate(fullDateTime),
            'time': widget.selectedTime,
            'trainer_name': widget.trainerName,
            'capacity': widget.slotCapacity,
            'booked': bookedByNew.length,
            'trainer_email': 'srihemaparvathaneni@gmail.com', 
            'booked_by': bookedByNew,
            'booked_names': bookedNamesNew,
            'booked_emails': bookedEmailsNew,
            'purchase_ids': purchaseIdsNew,
            'user_purchase_map': userPurchaseMapNew,
            'last_updated': FieldValue.serverTimestamp(),
            'status_by_user': {
              user.uid: isRescheduleLocal ? 'Rescheduled' : 'Confirmed'
            },
            'planName': planName,
            'planId': planId,
          },
          SetOptions(merge: true),
        );

        if (oldRef != null && oldSnap != null && oldSnap.exists) {
          txn.update(oldRef, {
            'booked': bookedByOld!.length,
            'booked_by': bookedByOld,
            'booked_names': bookedNamesOld,
            'booked_emails': bookedEmailsOld,
            'purchase_ids': purchaseIdsOld,
            'user_purchase_map': userPurchaseMapOld,
            'last_updated': FieldValue.serverTimestamp(),
            'status_by_user': {user.uid: 'Cancelled'},
          });
        }
      });

      // 📧 NEW: notify trainer about NEW booking or reschedule
      try {
        await _sendTrainerNotificationEmail(
          action: isRescheduleLocal ? 'Rescheduled' : 'Booked',
          clientName: userName,
          clientEmail: userEmail,
          date: widget.selectedDate,
          time: widget.selectedTime,
          oldSlotInfo: isRescheduleLocal ? oldDocId : null,
        );
      } catch (emailError) {
        print('⚠️ Trainer email (booking) failed: $emailError');
      }

      setState(() {
        _loading = false;
        _success = true;
      });

      print(
          '✅ ${isRescheduleLocal ? 'Reschedule' : 'Booking'} completed successfully!');
    } catch (e) {
      setState(() => _loading = false);
      print(
          '❌ ${widget.rescheduleSlot != null ? 'Reschedule' : 'Booking'} error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${widget.rescheduleSlot != null ? 'Reschedule' : 'Booking'} error: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Booking Confirmation"),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _success ? _buildSuccessUI() : _buildConfirmationUI(),
    );
  }

  // In BookingConfirmationPage, add this to track booked sessions
  Future<void> _updateBookedSessionsCount(
      String purchaseId, int change) async {
    try {
      final purchaseRef = FirebaseFirestore.instance
          .collection('client_purchases')
          .doc(purchaseId);

      await purchaseRef.update({
        'bookedSessions': FieldValue.increment(change),
        'availableSessions': FieldValue.increment(-change),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print(
          '📊 Updated booked sessions: $change for purchase $purchaseId');
    } catch (e) {
      print('❌ Error updating booked sessions');
    }
  }

  // 📧 NEW: Trainer notification email
  Future<void> _sendTrainerNotificationEmail({
    required String action, // 'Booked' or 'Rescheduled'
    required String clientName,
    required String clientEmail,
    required DateTime date,
    required String time,
    String? oldSlotInfo,
  }) async {
    try {
      // 🔧 TODO: Replace with Kenny’s real email
      const String trainerEmail = 'srihemaparvathaneni@gmail.com';

      final trainerName = widget.trainerName;
      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(date);

      final String subject = action == 'Rescheduled'
          ? 'Session rescheduled - $dateStr'
          : 'New session booked - $dateStr';

      final StringBuffer textBuffer = StringBuffer()
        ..writeln('Hello $trainerName,')
        ..writeln()
        ..writeln(
            '$clientName ($clientEmail) has just ${action.toLowerCase()} a training session.')
        ..writeln()
        ..writeln('Date: $dateStr')
        ..writeln('Time: $time');

      if (oldSlotInfo != null && oldSlotInfo.isNotEmpty) {
        textBuffer.writeln('Previous slot: $oldSlotInfo');
      }

      textBuffer
        ..writeln()
        ..writeln('— Flex Facility App');

      final StringBuffer htmlBuffer = StringBuffer()
        ..writeln('<html><body>')
        ..writeln('<h2>Training Session $action</h2>')
        ..writeln('<p>Hello $trainerName,</p>')
        ..writeln(
            '<p><strong>$clientName</strong> ($clientEmail) has just ${action.toLowerCase()} a training session.</p>')
        ..writeln('<h3>Session Details</h3>')
        ..writeln('<ul>')
        ..writeln('<li><strong>Date:</strong> $dateStr</li>')
        ..writeln('<li><strong>Time:</strong> $time</li>')
        ..writeln('</ul>');

      if (oldSlotInfo != null && oldSlotInfo.isNotEmpty) {
        htmlBuffer.writeln(
            '<p><strong>Previous slot:</strong> $oldSlotInfo</p>');
      }

      htmlBuffer
        ..writeln('<p>— Flex Facility App</p>')
        ..writeln('</body></html>');

      final emailData = {
        'to': trainerEmail,
        'message': {
          'subject': subject,
          'text': textBuffer.toString(),
          'html': htmlBuffer.toString(),
        },
        'type': 'trainer_booking_notification',
        'timestamp': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('mail').add(emailData);
      print('✅ Trainer notification email queued for $trainerEmail');
    } catch (e) {
      print('❌ Error sending trainer notification email: $e');
      // Don’t rethrow – we never want email failure to break booking flow
    }
  }

  Widget _buildConfirmationUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 50, color: Color(0xFF1C2D5E)),
                    const SizedBox(height: 16),
                    Text(
                      widget.rescheduleSlot != null
                          ? 'Reschedule Appointment'
                          : 'Confirm Appointment',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C2D5E),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow(
                        Icons.person, 'Trainer:', widget.trainerName),
                    _buildDetailRow(
                        Icons.calendar_month,
                        'Date:',
                        DateFormat('EEEE, MMMM d')
                            .format(widget.selectedDate)),
                    _buildDetailRow(
                        Icons.access_time, 'Time:', widget.selectedTime),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _confirmBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.rescheduleSlot != null
                          ? Colors.orange.shade700
                          : const Color(0xFF1C2D5E),
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.rescheduleSlot != null
                          ? 'CONFIRM RESCHEDULE'
                          : 'CONFIRM BOOKING',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessUI() {
    final bool isReschedule = widget.rescheduleSlot != null;
    final newRemainingSessions =
        (_activePlan?['remainingSessions'] as int? ?? 1) - 1;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(20),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 80,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isReschedule
                  ? 'Reschedule Confirmed!'
                  : 'Booking Confirmed!',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C2D5E),
              ),
            ),
            const SizedBox(height: 16),

            // Updated session count after booking - ONLY show for normal bookings, not reschedules
            if (_activePlan != null && !isReschedule) ...[
              Card(
                elevation: 2,
                margin:
                    const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildSuccessDetailRow(
                          'Plan:', _activePlan!['planName'] as String),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        'Sessions Remaining:',
                        '${(_activePlan!['availableSessions'] as int) - 1} of ${_activePlan!['totalSessions']}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              elevation: 2,
              margin:
                  const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildSuccessDetailRow(
                        'Trainer:', widget.trainerName),
                    const Divider(height: 16),
                    _buildSuccessDetailRow(
                        'Date:',
                        DateFormat('EEEE, MMMM d')
                            .format(widget.selectedDate)),
                    const Divider(height: 16),
                    _buildSuccessDetailRow(
                        'Time:', widget.selectedTime),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C2D5E),
                  padding:
                      const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'DONE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A confirmation has been sent to your email',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
      IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessDetailRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
