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

Future<void> _cancelOldSlot(String docId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
  final doc = await docRef.get();
  if (!doc.exists) return;

  final data = doc.data()!;
  List bookedBy = List.from(data['booked_by'] ?? []);
  List bookedNames = List.from(data['booked_names'] ?? []);
  List bookedEmails = List.from(data['booked_emails'] ?? []);

  if (!bookedBy.contains(user.uid)) {
    print("User not found in previous booking. Skipping cancel step.");
    return; // Don't throw, just skip cancel
  }

  final userEmail = user.email ?? '';
  final userName = user.displayName ?? 'Client';

  await docRef.update({
    'booked': FieldValue.increment(-1),
    'booked_by': FieldValue.arrayRemove([user.uid]),
    'booked_names': FieldValue.arrayRemove([userName]),
    'booked_emails': FieldValue.arrayRemove([userEmail]),
    'last_updated': FieldValue.serverTimestamp(),
  });
}

  Future<void> _confirmBooking() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docId = "${DateFormat('yyyy-MM-dd').format(widget.selectedDate)}|${widget.selectedTime}";
    final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final userName = userDoc['name'] ?? 'Client';
    final userEmail = userDoc['email'] ?? '';

    final startTimeRaw = widget.selectedTime.split(" - ")[0].trim();
    final timeParts = startTimeRaw.split(RegExp(r'[:\s]'));

    int hour = int.parse(timeParts[0]);
    int minute = int.parse(timeParts[1]);
    String amPm = timeParts[2];

    if (amPm == "PM" && hour != 12) hour += 12;
    if (amPm == "AM" && hour == 12) hour = 0;

    final fullDateTime = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      hour,
      minute,
    );

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        List bookedBy = snapshot.exists ? List.from(snapshot['booked_by']) : [];
        List bookedNames = snapshot.exists ? List.from(snapshot['booked_names']) : [];
        List bookedEmails = snapshot.exists ? List.from(snapshot['booked_emails']) : [];

        if (bookedBy.contains(user.uid)) {
          throw Exception('You already booked this slot.');
        }
        if (bookedBy.length >= widget.slotCapacity) {
          throw Exception('This slot is full.');
        }

        bookedBy.add(user.uid);
        bookedNames.add(userName);
        bookedEmails.add(userEmail);

       // In your _confirmBooking function:
final Map<String, dynamic> dataToSave = {
  'date': fullDateTime,
  'time': widget.selectedTime,
  'trainer_name': widget.trainerName,
  'booked': bookedBy.length,
  'booked_by': bookedBy,
  'booked_names': bookedNames,
  'booked_emails': bookedEmails,
  'capacity': widget.slotCapacity,
  'last_updated': FieldValue.serverTimestamp(),
  'is_reschedule': widget.rescheduleSlot != null, // This is the key line
};

        if (widget.rescheduleSlot != null) {
          dataToSave['is_reschedule'] = true;
        }

        transaction.set(docRef, dataToSave, SetOptions(merge: true));
      });

      if (widget.rescheduleSlot != null) {
        final oldDocId = widget.rescheduleSlot!['id'];
        await _cancelOldSlot(oldDocId);
      }

      setState(() {
        _loading = false;
        _success = true;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
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
                      'Date:', 
                      DateFormat('EEEE, MMMM d').format(widget.selectedDate)),
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