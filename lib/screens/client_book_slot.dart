import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'booking_confirmation_page.dart';
 
class ClientBookSlot extends StatefulWidget {
  const ClientBookSlot({Key? key}) : super(key: key);
 
  @override
  State<ClientBookSlot> createState() => _ClientBookSlotState();
}
 
class _ClientBookSlotState extends State<ClientBookSlot> {
  DateTime _focusedDate = DateTime.now();
  DateTime? _selectedDate;
  final int slotCapacity = 6;
  final String trainerName = 'Kenny Sims';
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
    _selectedDate = DateTime.now();
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
 
    if (selectedMidnight.isBefore(todayMidnight)) return [];
 
    final weekday = DateFormat('EEEE').format(date);
    final blocks = availabilityMap[weekday] ?? [];
    List<String> result = [];
 
    for (final block in blocks) {
      if (isSameDay(date, now)) {
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
        result.addAll(generateHourlySlots(block['start']!, block['end']!, date));
      }
    }
    return result;
  }
 
  bool _isDateDisabled(DateTime date) {
    final today = DateTime.now();
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
 
  Future<void> _cancelBooking(String docId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
 
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
        final doc = await transaction.get(docRef);
 
        if (!doc.exists) throw Exception('Slot not found');
 
        List bookedBy = List.from(doc['booked_by'] ?? []);
        List bookedNames = List.from(doc['booked_names'] ?? []);
 
        if (!bookedBy.contains(currentUser.uid)) {
          throw Exception('No booking found to cancel');
        }
 
        int index = bookedBy.indexOf(currentUser.uid);
        bookedBy.removeAt(index);
        bookedNames.removeAt(index);
 
        transaction.update(docRef, {
          'booked': FieldValue.increment(-1),
          'booked_by': bookedBy,
          'booked_names': bookedNames,
        });
      });
 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled successfully')),
      );
 
      setState(() {}); // Refresh slots after cancel
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel booking: ${e.toString()}')),
      );
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
            onPressed: () async {
              Navigator.pop(context);
 
              if (isBookedByUser) {
                await _cancelBooking(docId);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BookingConfirmationPage(
                      selectedDate: selectedDate,
                      selectedTime: time,
                      trainerName: trainerName,
                      slotCapacity: slotCapacity,
                    ),
                  ),
                ).then((_) => setState(() {}));
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
                          lastDay: DateTime.now().add(const Duration(days: 365)),
                          focusedDay: _focusedDate,
                          selectedDayPredicate: (day) => isSameDay(day, selectedDate),
                          onDaySelected: (day, _) {
                            if (_isDateDisabled(day)) return;
                            setState(() {
                              _selectedDate = day;
                              _focusedDate = day; // <- always set to re-enable today
                            });
                          },
                          calendarBuilders: CalendarBuilders(
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
                              return null;
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
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        final statuses = snapshot.data ?? {};
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
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
                              final isDisabled = slotInfo['isFull'] && !slotInfo['isBookedByUser'];
                              final isBookedByUser = slotInfo['isBookedByUser'];
 
                              return ElevatedButton(
                                onPressed: () => showSlotPopup(time),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: isDisabled
                                      ? Colors.grey[200]
                                      : isBookedByUser
                                          ? Colors.green[50]
                                          : Colors.white,
                                  foregroundColor: isDisabled
                                      ? Colors.grey
                                      : isBookedByUser
                                          ? Colors.green[800]
                                          : const Color(0xFF1C2D5E),
                                  side: BorderSide(
                                    color: isDisabled
                                        ? Colors.grey
                                        : isBookedByUser
                                            ? Colors.green
                                            : const Color(0xFF1C2D5E),
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
 