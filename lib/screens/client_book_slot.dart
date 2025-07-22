import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'booking_confirmation_page.dart'; // Make sure this import path is correct

class ClientBookSlot extends StatefulWidget {
  // Add an optional parameter to receive the slot being rescheduled
  final Map<String, dynamic>? rescheduleSlot;

  const ClientBookSlot({Key? key, this.rescheduleSlot}) : super(key: key);

  @override
  State<ClientBookSlot> createState() => _ClientBookSlotState();
}

class _ClientBookSlotState extends State<ClientBookSlot> {
  DateTime _focusedDate = DateTime.now();
  DateTime? _selectedDate;
  final int slotCapacity = 6;
  final String trainerName = 'Kenny Sims'; // This should ideally come from the trainer's profile or be passed.
  bool _isLoading = false;

  final Map<String, List<Map<String, String>>> availabilityMap = {
    'Monday': [
      {'start': '05:30', 'end': '11:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Tuesday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Wednesday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Thursday': [
      {'start': '05:30', 'end': '09:00'},
      {'start': '16:30', 'end': '19:00'},
    ],
    'Friday': [
      {'start': '05:30', 'end': '11:00'},
    ],
    'Saturday': [
      {'start': '05:30', 'end': '11:00'},
    ],
    'Sunday': [
      {'start': '05:30', 'end': '11:00'},
    ],
  };

  @override
  void initState() {
    super.initState();
    // If rescheduleSlot is provided, set the initial date to the old slot's date.
    // Otherwise, default to today.
    if (widget.rescheduleSlot != null) {
      _selectedDate = widget.rescheduleSlot!['date'];
      _focusedDate = widget.rescheduleSlot!['date'];
    } else {
      _selectedDate = DateTime.now();
    }
  }

  List<String> generateHourlySlots(String start, String end, DateTime day) {
    List<String> slots = [];
    DateFormat format = DateFormat("HH:mm");
    DateTime slotStart = DateTime(day.year, day.month, day.day,
        format.parse(start).hour, format.parse(start).minute);
    DateTime slotEnd = DateTime(day.year, day.month, day.day,
        format.parse(end).hour, format.parse(end).minute);

    while (slotStart.isBefore(slotEnd)) {
      final nextHour = slotStart.add(const Duration(hours: 1));
      slots.add('${DateFormat.jm().format(slotStart)} - ${DateFormat.jm().format(nextHour)}');
      slotStart = nextHour;
    }
    return slots;
  }

  List<String> getSlotsForDay(DateTime date) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final selectedMidnight = DateTime(date.year, date.month, date.day);

    // Disable past dates
    if (selectedMidnight.isBefore(todayMidnight)) return [];

    final weekday = DateFormat('EEEE').format(date);
    final blocks = availabilityMap[weekday] ?? [];
    List<String> result = [];

    for (final block in blocks) {
      if (isSameDay(date, now)) {
        // For today, only show future slots
        DateTime currentTime = now;
        DateTime blockEnd = DateTime(date.year, date.month, date.day,
            int.parse(block['end']!.split(':')[0]), int.parse(block['end']!.split(':')[1]));
        if (blockEnd.isAfter(currentTime)) {
          DateTime adjustedStart = currentTime.isAfter(DateTime(date.year, date.month, date.day,
                      int.parse(block['start']!.split(':')[0]), int.parse(block['start']!.split(':')[1])))
              ? currentTime
              : DateTime(date.year, date.month, date.day,
                      int.parse(block['start']!.split(':')[0]), int.parse(block['start']!.split(':')[1]));
          result.addAll(generateHourlySlots(
              DateFormat("HH:mm").format(adjustedStart), block['end']!, date));
        }
      } else {
        // For future days, show all available slots for the day
        result.addAll(generateHourlySlots(block['start']!, block['end']!, date));
      }
    }
    return result;
  }

  bool _isDateDisabled(DateTime date) {
    final today = DateTime.now();
    // Disable dates before today (midnight)
    return date.isBefore(DateTime(today.year, today.month, today.day));
  }

  Future<Map<String, Map<String, dynamic>>> getSlotStatuses(DateTime date, List<String> slots) async {
    Map<String, Map<String, dynamic>> statuses = {};
    final currentUser = FirebaseAuth.instance.currentUser;
    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    for (String time in slots) {
      final docId = "$dateKey|$time";
      final doc = await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).get();
      if (!doc.exists) {
        statuses[time] = {'isFull': false, 'isBookedByUser': false};
      } else {
        List bookedBy = doc['booked_by'] ?? [];
        statuses[time] = {
          'isFull': bookedBy.length >= slotCapacity,
          'isBookedByUser': bookedBy.contains(currentUser?.uid),
        };
      }
    }
    return statuses;
  }

  // Refactored _cancelBooking to use a docId string directly
 Future<void> _cancelBooking(String docId, {bool suppressError = false}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  if (!suppressError) setState(() => _isLoading = true);
  
  try {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
      final doc = await transaction.get(docRef);

      if (!doc.exists) {
        if (!suppressError) throw Exception('Slot document not found');
        return; // skip gracefully
      }

      List bookedBy = List.from(doc['booked_by'] ?? []);
      List bookedNames = List.from(doc['booked_names'] ?? []);
      List bookedEmails = List.from(doc['booked_emails'] ?? []);

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
          
      final userEmail = userDoc['email'] ?? '';
      final userName = userDoc['name'] ?? 'Client';

      final userIndex = bookedBy.indexOf(currentUser.uid);
      if (userIndex == -1) {
        if (!suppressError) throw Exception('No booking found for current user');
        return;
      }

      bookedBy.removeAt(userIndex);
      bookedNames.removeAt(userIndex);
      bookedEmails.removeAt(userIndex);

      transaction.update(docRef, {
        'booked': bookedBy.length,
        'booked_by': bookedBy,
        'booked_names': bookedNames,
        'booked_emails': bookedEmails,
        'last_updated': FieldValue.serverTimestamp(),
      });
    });

    if (!suppressError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }

    if (!suppressError) setState(() {});
  } catch (e) {
    if (!suppressError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel booking: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (!suppressError) debugPrint('Cancellation error: $e');
  } finally {
    if (!suppressError) setState(() => _isLoading = false);
  }
}


  void showSlotPopup(String time) async {
  if (_isLoading) return;
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in to book slots')),
    );
    return;
  }

  final selectedDate = _selectedDate ?? _focusedDate;
  final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
  final docId = "$dateKey|$time";
  final doc = await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).get();
  final isBookedByUser = doc.exists && (doc['booked_by'] ?? []).contains(currentUser.uid);
  final isFull = doc.exists && (doc['booked_by'] ?? []).length >= slotCapacity;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isBookedByUser ? 'Cancel Slot' : isFull ? 'Slot Full' : 'Book Slot'),
      content: Text(isBookedByUser
          ? 'Do you want to cancel this booking at $time?'
          : isFull
              ? 'This slot is already full'
              : 'Do you want to proceed to book this slot at $time?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('No'),
        ),
        if (!isFull || isBookedByUser)
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              if (isBookedByUser) {
                // Just cancel
                await _cancelBooking(docId);
              } else {
                // Proceed to Booking Confirmation Page first (don't cancel old yet)
               
// In showSlotPopup method, update the BookingConfirmationPage navigation:
final result = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => BookingConfirmationPage(
      selectedDate: selectedDate,
      selectedTime: time,
      trainerName: trainerName,
      slotCapacity: slotCapacity,
      rescheduleSlot: widget.rescheduleSlot, // Pass the reschedule slot
    ),
  ),
);

if (widget.rescheduleSlot != null) {
  final oldDocId = widget.rescheduleSlot!['id'];
  await _cancelBooking(oldDocId, suppressError: true); // ✅ Important change
}


                setState(() {});
              }
            },
            child: Text(isBookedByUser ? 'Cancel Booking' : 'Proceed'),
          ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final selectedDate = _selectedDate ?? _focusedDate;
    final slots = getSlotsForDay(selectedDate);
    final dateLabel = DateFormat('EEEE, MMMM d').format(selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Book Appointment"),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: TableCalendar(
                          firstDay: DateTime.now().subtract(const Duration(days: 365)),
                          lastDay: DateTime(DateTime.now().year + 2, 12, 31),
                          focusedDay: _focusedDate,
                          selectedDayPredicate: (day) => isSameDay(day, selectedDate),
                          onDaySelected: (day, _) {
                            if (_isDateDisabled(day)) return; // Prevent selecting past dates

                            // Update selected and focused dates on day selection
                            final today = DateTime.now();
                            setState(() {
                              if (isSameDay(day, today)) {
                                _selectedDate = DateTime.now(); // Force refresh for today's slots
                              } else {
                                _selectedDate = day;
                              }
                              _focusedDate = day;
                            });
                          },
                          calendarBuilders: CalendarBuilders(
                            // Custom builder for disabled (past) dates
                            defaultBuilder: (context, day, _) {
                              final today = DateTime.now();
                              if (day.isBefore(DateTime(today.year, today.month, today.day))) {
                                return Center(
                                  child: Text(
                                    '${day.day}',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                );
                              }
                              return null; // Use default builder for other days
                            },
                          ),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            titleTextStyle: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                          ),
                          calendarStyle: const CalendarStyle(
                            todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                            selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekdayStyle: TextStyle(color: Colors.black87),
                            weekendStyle: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(dateLabel,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E))),
                  const SizedBox(height: 12),
                  if (slots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Text("No available slots remaining for today",
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ),
                  if (slots.isNotEmpty)
                    FutureBuilder<Map<String, Map<String, dynamic>>>(
                      future: getSlotStatuses(selectedDate, List<String>.from(slots)),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                           return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                          );
                        }
                        final statuses = snapshot.data ?? {};
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: GridView.builder(
                            shrinkWrap: true, // Allows GridView inside SingleChildScrollView
                            physics: const NeverScrollableScrollPhysics(), // Disables GridView's own scrolling
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 3,
                            ),
                            itemCount: slots.length,
                            itemBuilder: (context, index) {
                              final time = slots[index];
                              final slotInfo = statuses[time] ?? {'isFull': false, 'isBookedByUser': false};
                              final isDisabled = slotInfo['isFull'] && !slotInfo['isBookedByUser']; // A slot is disabled if it's full AND the current user hasn't booked it
                              final isBookedByUser = slotInfo['isBookedByUser'];

                              return ElevatedButton(
                                onPressed: isDisabled ? null : () => showSlotPopup(time), // Disable button if slot is full and not booked by user
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: isDisabled
                                      ? Colors.grey[200] // Light grey for disabled
                                      : isBookedByUser
                                          ? Colors.green[50] // Light green for user's booked slot
                                          : Colors.white, // White for available
                                  foregroundColor: isDisabled
                                      ? Colors.grey // Dark grey for disabled text
                                      : isBookedByUser
                                          ? Colors.green[800] // Dark green for user's booked slot text
                                          : const Color(0xFF1C2D5E), // Primary color for available text
                                  side: BorderSide(
                                    color: isDisabled
                                        ? Colors.grey // Grey border for disabled
                                        : isBookedByUser
                                            ? Colors.green // Green border for user's booked slot
                                            : const Color(0xFF1C2D5E), // Primary color border for available
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: Text(
                                  time,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}