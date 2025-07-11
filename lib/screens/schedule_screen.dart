import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'client_book_slot.dart'; // Make sure this import path is correct

class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _pastSlots = [];
  List<Map<String, dynamic>> _upcomingSlots = [];

  @override
  void initState() {
    super.initState();
    _fetchBookedSlots();
  }

  Future<void> _fetchBookedSlots() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final querySnapshot = await _firestore
          .collection('trainer_slots')
          .where('booked_by', arrayContains: user.uid)
          .get();

      final now = DateTime.now();
      List<Map<String, dynamic>> past = [];
      List<Map<String, dynamic>> upcoming = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        DateTime date;
        if (data['date'] is Timestamp) {
          final utcDate = (data['date'] as Timestamp).toDate();
          date = DateTime(utcDate.year, utcDate.month, utcDate.day);
        } else if (data['date'] is DateTime) {
          date = data['date'] as DateTime;
        } else if (data['date'] is String) {
          date = DateTime.parse(data['date'] as String);
        } else {
          date = DateTime.now(); // Fallback to current date if parsing fails
        }

        final slot = {
          'id': doc.id, // Store the document ID for cancellation
          'date': date,
          'time': data['time'] ?? '',
          'trainer': data['trainer_name'] ?? 'Unknown Trainer',
          'status': data['status'] ?? 'Confirmed',
          'docRef': doc.reference, // Pass the DocumentReference for easy cancellation
        };

        // Determine if the slot is in the past or upcoming
        // Compare only date parts for past/upcoming classification
        if (date.isBefore(DateTime(now.year, now.month, now.day))) {
          past.add(slot);
        } else {
          upcoming.add(slot);
        }
      }

      setState(() {
        _pastSlots = past;
        _upcomingSlots = upcoming;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching slots: ${e.toString()}')),
      );
    }
  }

  Future<void> _cancelBooking(DocumentReference docRef) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (!doc.exists) throw Exception('Slot not found');

        List bookedBy = List.from(doc['booked_by'] ?? []);
        List bookedNames = List.from(doc['booked_names'] ?? []);
        List bookedEmails = List.from(doc['booked_emails'] ?? []);

        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final userEmail = userDoc['email'] ?? '';
        final userName = userDoc['name'] ?? 'Client';

        // Remove the current user's booking information
        bookedBy.removeWhere((uid) => uid == user.uid);
        bookedNames.removeWhere((name) => name == userName);
        bookedEmails.removeWhere((email) => email == userEmail);

        transaction.update(docRef, {
          'booked': bookedBy.length, // Update the number of booked slots
          'booked_by': bookedBy,
          'booked_names': bookedNames,
          'booked_emails': bookedEmails,
        });
      });

      await _fetchBookedSlots(); // Re-fetch to update UI
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: ${e.toString()}')),
      );
    }
  }

  void _showCancelDialog(DocumentReference docRef) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelBooking(docRef);
            },
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // New reschedule logic: Navigate to the booking page with the slot data
  void _rescheduleBooking(Map<String, dynamic> slot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientBookSlot(
          rescheduleSlot: slot, // Pass the entire slot data for rescheduling
        ),
      ),
    ).then((_) {
      // This .then() block executes when you return from ClientBookSlot.
      // We refetch the sessions to reflect any changes (e.g., if a reschedule was completed).
      _fetchBookedSlots();
    });
  }

  Widget _buildSlotCard(Map<String, dynamic> slot, {bool isPast = false}) {
    final dateStr = DateFormat('EEEE, MMMM d').format(slot['date']);
    final time = slot['time'];
    final status = slot['status'] ?? 'Confirmed';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    slot['trainer'],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                  ),
                ),
                if (!isPast) ...[ // Only show reschedule/cancel for upcoming slots
                  TextButton(
                    onPressed: () => _rescheduleBooking(slot),
                    child: const Text('Reschedule', style: TextStyle(color: Colors.orange)),
                  ),
                  TextButton(
                    onPressed: () => _showCancelDialog(slot['docRef']),
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'Cancelled' ? Colors.red : Colors.green, // Status display
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.grey, size: 18),
                const SizedBox(width: 8),
                Text(dateStr, style: const TextStyle(color: Colors.black87, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey, size: 18),
                const SizedBox(width: 8),
                Text(time, style: const TextStyle(color: Colors.black87, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _exportToPDF() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('My Schedule - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}')),
          if (_upcomingSlots.isNotEmpty) ...[
            pw.Header(level: 1, child: pw.Text('Upcoming Sessions')),
            ..._upcomingSlots.map((slot) => pw.Paragraph(text: '📅 ${DateFormat('EEEE, MMMM d').format(slot['date'])} - ${slot['time']} with ${slot['trainer']} (${slot['status']})')),
            pw.SizedBox(height: 16),
          ],
          if (_pastSlots.isNotEmpty) ...[
            pw.Header(level: 1, child: pw.Text('Past Sessions')),
            ..._pastSlots.map((slot) => pw.Paragraph(text: '🕒 ${DateFormat('EEEE, MMMM d').format(slot['date'])} - ${slot['time']} with ${slot['trainer']} (${slot['status']})')),
          ],
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FA),
        appBar: AppBar(
          title: const Text('My Scheduled Sessions'),
          backgroundColor: const Color(0xFF1C2D5E),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _exportToPDF,
              tooltip: 'Export to PDF',
            )
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _upcomingSlots.isEmpty
                      ? const Center(child: Text('No upcoming sessions'))
                      : RefreshIndicator(
                          onRefresh: _fetchBookedSlots,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _upcomingSlots.length,
                            itemBuilder: (context, index) => _buildSlotCard(_upcomingSlots[index]),
                          ),
                        ),
                  _pastSlots.isEmpty
                      ? const Center(child: Text('No past sessions'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pastSlots.length,
                          itemBuilder: (context, index) => _buildSlotCard(_pastSlots[index], isPast: true),
                        ),
                ],
              ),
      ),
    );
  }
}