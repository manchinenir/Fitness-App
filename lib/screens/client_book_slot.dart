// client_book_slot.dart
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
  DateTime? _selectedDate = DateTime.now();
  final int slotCapacity = 6;
  final String trainerName = 'Kenny Sims';

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

  List<String> generateHourlySlots(String start, String end) {
    List<String> slots = [];
    DateFormat format = DateFormat("HH:mm");
    DateTime startTime = format.parse(start);
    DateTime endTime = format.parse(end);
    while (startTime.isBefore(endTime)) {
      final endSlot = startTime.add(const Duration(hours: 1));
      slots.add('${DateFormat.jm().format(startTime)} - ${DateFormat.jm().format(endSlot)}');
      startTime = endSlot;
    }
    return slots;
  }

  List<String> getSlotsForDay(DateTime date) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final selectedMidnight = DateTime(date.year, date.month, date.day);
    final allowDate = DateTime(2025, 6, 19);
    if (selectedMidnight.isBefore(todayMidnight) && !isSameDay(date, allowDate)) {
      return [];
    }
    final weekday = DateFormat('EEEE').format(date);
    final blocks = availabilityMap[weekday] ?? [];
    List<String> result = [];
    for (final b in blocks) {
      result.addAll(generateHourlySlots(b['start']!, b['end']!));
    }
    return result;
  }

  Future<Map<String, String>> getSlotStatuses(DateTime date, List<String> slots) async {
    Map<String, String> statuses = {};
    final currentUser = FirebaseAuth.instance.currentUser;
    final dateKey = DateFormat('yyyy-MM-dd').format(date);

    for (String time in slots) {
      final docId = "$dateKey|$time";
      final doc = await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).get();
      if (!doc.exists) {
        statuses[time] = 'available';
      } else {
        List bookedBy = doc['booked_by'] ?? [];
        if (bookedBy.contains(currentUser?.uid)) {
          statuses[time] = 'booked';
        } else if (bookedBy.length >= slotCapacity) {
          statuses[time] = 'full';
        } else {
          statuses[time] = 'available';
        }
      }
    }
    return statuses;
  }

  void showSlotPopup(String time) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final docId = "$dateKey|$time";
    final doc = await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).get();
    final isAlreadyBooked = doc.exists && (doc['booked_by'] ?? []).contains(currentUser?.uid);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isAlreadyBooked ? 'Cancel Slot' : 'Book Slot'),
        content: Text(isAlreadyBooked
            ? 'Do you want to cancel this booking at $time?'
            : 'Do you want to proceed to book this slot at $time?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (isAlreadyBooked) {
                await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).update({
                  'booked_by': FieldValue.arrayRemove([currentUser?.uid])
                });
                setState(() {});
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BookingConfirmationPage(
                      selectedDate: _selectedDate!,
                      selectedTime: time,
                      trainerName: trainerName,
                      slotCapacity: slotCapacity,
                    ),
                  ),
                ).then((_) => setState(() {}));
              }
            },
            child: Text(isAlreadyBooked ? 'Cancel Booking' : 'Proceed'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> slots = _selectedDate == null ? [] : getSlotsForDay(_selectedDate!);
    final dateLabel = _selectedDate == null ? '' : DateFormat('EEEE, MMMM d').format(_selectedDate!);

    return Scaffold(
      appBar: AppBar(title: const Text("Book Slots")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TableCalendar(
                firstDay: DateTime.utc(2023, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDate,
                selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
                onDaySelected: (day, _) {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final allowedDate = DateTime(2025, 6, 19);

                  if (!day.isBefore(today) || isSameDay(day, allowedDate)) {
                    setState(() {
                      _selectedDate = day;
                      _focusedDate = day;
                    });
                  }
                },
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final allowedDate = DateTime(2025, 6, 19);

                    if (day.isBefore(today) && !isSameDay(day, allowedDate)) {
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
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                ),
              ),
            ),
            if (_selectedDate != null) ...[
              Text(
                dateLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (slots.isEmpty)
                const Text("No available slots for this date."),
              if (slots.isNotEmpty)
                FutureBuilder<Map<String, String>>(
                  future: getSlotStatuses(_selectedDate!, slots),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final statuses = snapshot.data!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 3.2,
                        ),
                        itemCount: slots.length,
                        itemBuilder: (context, index) {
                          final time = slots[index];
                          final status = statuses[time] ?? 'available';

                          Color bgColor;
                          Color textColor;
                          switch (status) {
                            case 'booked':
                              bgColor = Colors.green.shade100;
                              textColor = Colors.green;
                              break;
                            case 'full':
                              bgColor = Colors.grey.shade300;
                              textColor = Colors.grey;
                              break;
                            default:
                              bgColor = Colors.white;
                              textColor = Colors.blue;
                          }

                          return OutlinedButton(
                            onPressed: status == 'full' ? null : () => showSlotPopup(time),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: bgColor,
                              side: BorderSide(color: textColor, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              const SizedBox(height: 30),
            ]
          ],
        ),
      ),
    );
  }
}
