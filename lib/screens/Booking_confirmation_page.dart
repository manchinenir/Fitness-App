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

  const BookingConfirmationPage({
    Key? key,
    required this.selectedDate,
    required this.selectedTime,
    required this.trainerName,
    required this.slotCapacity,
    this.rescheduleSlot,
  }) : super(key: key);

  @override
  State<BookingConfirmationPage> createState() => _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  bool _loading = false;
  bool _success = false;

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

    try {
      // Get canonical name/email to store in arrays
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName = userDoc.data()?['name'] ?? 'Client';
      final userEmail = userDoc.data()?['email'] ?? '';

      // New slot doc id
      final dateKey = DateFormat('yyyy-MM-dd').format(widget.selectedDate);
      final newDocId = "$dateKey|${widget.selectedTime}";
      final newRef = FirebaseFirestore.instance.collection('trainer_slots').doc(newDocId);

      // Parse start time to DateTime
      final startTimeRaw = widget.selectedTime.split(' - ').first.trim();
      final parsedStart = DateFormat.jm().parseLoose(startTimeRaw);
      final fullDateTime = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        parsedStart.hour,
        parsedStart.minute,
      );

      // Old slot (if rescheduling)
      final String? oldDocId = widget.rescheduleSlot != null
          ? (widget.rescheduleSlot!['id'] as String?)
          : null;
      final oldRef = (oldDocId != null && oldDocId.isNotEmpty)
          ? FirebaseFirestore.instance.collection('trainer_slots').doc(oldDocId)
          : null;

      await FirebaseFirestore.instance.runTransaction((txn) async {
        // ----- READS FIRST -----
        final newSnap = await txn.get(newRef);

        DocumentSnapshot<Map<String, dynamic>>? oldSnap;
        if (oldRef != null) {
          oldSnap = await txn.get(oldRef);
        }

        // ----- PREP MUTATIONS (NEW) -----
        List bookedByNew = [];
        List bookedNamesNew = [];
        List bookedEmailsNew = [];

        if (newSnap.exists) {
          final d = newSnap.data() as Map<String, dynamic>;
          bookedByNew     = List.from(d['booked_by'] ?? []);
          bookedNamesNew  = List.from(d['booked_names'] ?? []);
          bookedEmailsNew = List.from(d['booked_emails'] ?? []);
        }

        final alreadyInNew = bookedByNew.contains(user.uid);
        if (!alreadyInNew && bookedByNew.length >= widget.slotCapacity) {
          throw Exception('This slot is full.');
        }
        if (!alreadyInNew) {
          bookedByNew.add(user.uid);
          bookedNamesNew.add(userName);
          bookedEmailsNew.add(userEmail);
        }

        // ----- PREP MUTATIONS (OLD) -----
        List? bookedByOld, bookedNamesOld, bookedEmailsOld;
        if (oldSnap != null && oldSnap.exists) {
          final od = oldSnap.data() as Map<String, dynamic>;
          bookedByOld     = List.from(od['booked_by'] ?? []);
          bookedNamesOld  = List.from(od['booked_names'] ?? []);
          bookedEmailsOld = List.from(od['booked_emails'] ?? []);

          final idx = bookedByOld.indexOf(user.uid);
          if (idx != -1) {
            bookedByOld.removeAt(idx);
            if (idx < bookedNamesOld.length)  bookedNamesOld.removeAt(idx);
            if (idx < bookedEmailsOld.length) bookedEmailsOld.removeAt(idx);
          }
        }

        // ----- WRITES AFTER ALL READS -----
        txn.set(newRef, {
          'date': Timestamp.fromDate(fullDateTime),
          'time': widget.selectedTime,
          'trainer_name': widget.trainerName,
          'capacity': widget.slotCapacity,
          'booked': bookedByNew.length,
          'booked_by': bookedByNew,
          'booked_names': bookedNamesNew,
          'booked_emails': bookedEmailsNew,
          'last_updated': FieldValue.serverTimestamp(),
          'status_by_user': {
            user.uid: widget.rescheduleSlot != null ? 'Rescheduled' : 'Confirmed'
          },
        }, SetOptions(merge: true));

        if (oldRef != null && oldSnap != null && oldSnap.exists) {
          txn.update(oldRef, {
            'booked': bookedByOld!.length,
            'booked_by': bookedByOld,
            'booked_names': bookedNamesOld,
            'booked_emails': bookedEmailsOld,
            'last_updated': FieldValue.serverTimestamp(),
            'status_by_user': { user.uid: 'Cancelled' },
          });
        }
      });

      setState(() {
        _loading = false;
        _success = true;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
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
                    const Icon(Icons.calendar_today, size: 50, color: Color(0xFF1C2D5E)),
                    const SizedBox(height: 16),
                    Text(
                      widget.rescheduleSlot != null ? 'Reschedule Appointment' : 'Confirm Appointment',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C2D5E),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow(Icons.person, 'Trainer:', widget.trainerName),
                    _buildDetailRow(Icons.calendar_month, 'Date:',
                        DateFormat('EEEE, MMMM d').format(widget.selectedDate)),
                    _buildDetailRow(Icons.access_time, 'Time:', widget.selectedTime),
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.rescheduleSlot != null ? 'CONFIRM RESCHEDULE' : 'CONFIRM BOOKING',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
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
              isReschedule ? 'Reschedule Confirmed!' : 'Booking Confirmed!',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1C2D5E),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildSuccessDetailRow('Trainer:', widget.trainerName),
                    const Divider(height: 24),
                    _buildSuccessDetailRow(
                        'Date:', DateFormat('EEEE, MMMM d').format(widget.selectedDate)),
                    const Divider(height: 24),
                    _buildSuccessDetailRow('Time:', widget.selectedTime),
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
                  padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
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
