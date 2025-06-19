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
  DateTime? _selectedDay;
  List<Map<String, dynamic>> _bookings = [];

  Future<void> _fetchBookings(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('date', isGreaterThanOrEqualTo: startOfDay)
        .where('date', isLessThan: endOfDay)
        .get();

    setState(() {
      _bookings = snapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
    });
  }

  void _deleteSlot(String docId) async {
    await FirebaseFirestore.instance.collection('trainer_slots').doc(docId).delete();
    if (_selectedDay != null) {
      _fetchBookings(_selectedDay!);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _fetchBookings(_selectedDay!);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    return Scaffold(
      appBar: AppBar(title: const Text("Admin Slot Manager")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TableCalendar(
              firstDay: todayMidnight,
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _fetchBookings(selectedDay);
              },
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false, // 🔥 Removed format toggle (Month/2 weeks)
                titleCentered: true,
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  if (day.isBefore(todayMidnight)) {
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
            ),
          ),
          if (_selectedDay != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Bookings for ${DateFormat('yyyy-MM-dd').format(_selectedDay!)}:',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: _bookings.isEmpty
                ? const Center(child: Text("No bookings found."))
                : ListView.builder(
                    itemCount: _bookings.length,
                    itemBuilder: (context, index) {
                      final booking = _bookings[index];
                      final docId = booking['docId'] ?? '';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text("Time: ${booking['time']}"),
                          subtitle: Text(
                            "Booked: ${booking['booked'] ?? 0}/${booking['capacity'] ?? 6}\nClients: ${(booking['booked_names'] as List).join(", ")}",
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteSlot(docId),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
