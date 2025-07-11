//Booking_Conformation_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
 
class BookingConfirmationPage extends StatefulWidget {
  final DateTime selectedDate;
  final String selectedTime;
  final String trainerName;
  final int slotCapacity;
 
  const BookingConfirmationPage({
    super.key,
    required this.selectedDate,
    required this.selectedTime,
    required this.trainerName,
    required this.slotCapacity,
  });
 
  @override
  State<BookingConfirmationPage> createState() => _BookingConfirmationPageState();
}
 
class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  bool _loading = false;
  bool _showSuccess = false;
 Future<void> _bookSlot() async {
  setState(() => _loading = true);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    // Normalize date to midnight to avoid timezone/timezone offset issues
    DateTime normalizedDate = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );

    final formattedDate = DateFormat('yyyy-MM-dd').format(normalizedDate);
    final docId = '$formattedDate|${widget.selectedTime}';
    final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final doc = await transaction.get(docRef);

      if (!doc.exists) {
        // Slot does not exist: create it with the first booking
        transaction.set(docRef, {
          'date': Timestamp.fromDate(normalizedDate),
          'time': widget.selectedTime,
          'booked': 1,
          'booked_by': [user.uid],
          'booked_names': [userDoc['name'] ?? 'Client'],
          'booked_emails': [userDoc['email'] ?? ''],
          'capacity': widget.slotCapacity,
          'trainer_name': widget.trainerName,
          'created_at': Timestamp.now(),
        });
      } else {
        final data = doc.data()!;
        final currentBooked = data['booked'] ?? 0;
        final bookedBy = List.from(data['booked_by'] ?? []);
        final capacity = data['capacity'] ?? widget.slotCapacity;

        if (bookedBy.contains(user.uid)) {
          throw Exception('You already booked this slot.');
        }
        if (currentBooked >= capacity) {
          throw Exception('Slot is full.');
        }

        // Update existing slot: increment booked count, add client info
        transaction.update(docRef, {
          'booked': FieldValue.increment(1),
          'booked_by': FieldValue.arrayUnion([user.uid]),
          'booked_names': FieldValue.arrayUnion([userDoc['name'] ?? 'Client']),
          'booked_emails': FieldValue.arrayUnion([userDoc['email'] ?? '']),
        });
      }
    });

    setState(() {
      _loading = false;
      _showSuccess = true;
    });
  } catch (e) {
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Confirmation'),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
      ),
      body: _showSuccess
          ? _buildSuccessUI()
          : _buildConfirmationUI(),
    );
  }
 
  Widget _buildConfirmationUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Trainer: ${widget.trainerName}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              'Date: ${DateFormat('EEEE, MMMM d').format(widget.selectedDate)}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text('Time: ${widget.selectedTime}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 32),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _bookSlot,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200, 50),
                      backgroundColor: const Color(0xFF1C2D5E),
                    ),
                    child: const Text('Confirm Booking',
                        style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildSuccessUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text('Booking Confirmed!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Trainer: ${widget.trainerName}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Date: ${DateFormat('EEEE, MMMM d').format(widget.selectedDate)}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text('Time: ${widget.selectedTime}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            const Text('Confirmation email has been sent',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(200, 50),
              ),
              child: const Text('Done',
                  style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}