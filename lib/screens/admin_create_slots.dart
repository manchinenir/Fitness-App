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
    _fetchFirestoreSlotsForDay(_selectedDay);
  }

  Future<void> _fetchFirestoreSlotsForDay(DateTime date) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('trainer_slots')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: '$dateKey|')
          .where(FieldPath.documentId, isLessThan: '$dateKey|z')
          .get();
      final Map<String, dynamic> slots = {
        for (final doc in snapshot.docs) doc.id: doc.data()
      };
      setState(() => _firestoreSlots = slots);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading slots: $e')),
      );
    }
  }

  List<String> generateHourlySlots(DateTime date) {
    final String weekday = DateFormat('EEEE').format(date);
    final blocks = availabilityMap[weekday] ?? [];
    List<String> slotLabels = [];

    for (var block in blocks) {
      DateTime start = DateFormat("HH:mm").parse(block['start']!);
      DateTime end = DateFormat("HH:mm").parse(block['end']!);
      DateTime slotStart = DateTime(date.year, date.month, date.day, start.hour, start.minute);
      DateTime slotEnd = DateTime(date.year, date.month, date.day, end.hour, end.minute);
      while (slotStart.isBefore(slotEnd)) {
        final next = slotStart.add(const Duration(hours: 1));
        final label = "${DateFormat.jm().format(slotStart)} - ${DateFormat.jm().format(next)}";
        slotLabels.add(label);
        slotStart = next;
      }
    }
    return slotLabels;
  }

  void _bookForClientDialog(String docId) async {
    List<Map<String, String>> clients = [];
    String? selectedClientUid;
    String selectedClientEmail = '';

    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();
      clients = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'name': data.containsKey('name') ? data['name'].toString() : '',
          'email': data.containsKey('email') ? data['email'].toString() : '',
          'uid': doc.id,
        };
      }).toList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching users: $e")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Book for Client"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Slot: ${docId.split('|')[1]}"),
                DropdownButtonFormField<String>(
                  value: selectedClientUid,
                  hint: const Text("Select Client"),
                  items: clients.map((client) {
                    return DropdownMenuItem<String>(
                      value: client['uid'],
                      child: Text(client['name'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (uid) {
                    final selected = clients.firstWhere((c) => c['uid'] == uid);
                    setState(() {
                      selectedClientUid = uid;
                      selectedClientEmail = selected['email'] ?? '';
                    });
                  },
                ),
                const SizedBox(height: 8),
                if (selectedClientUid != null && selectedClientEmail.isNotEmpty)
                  Text("Email: $selectedClientEmail", style: const TextStyle(fontSize: 14)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: selectedClientUid == null
                    ? null
                    : () async {
                        try {
                          final client = clients.firstWhere((c) => c['uid'] == selectedClientUid);
                          final slotRef = FirebaseFirestore.instance.collection('trainer_slots').doc(docId);
                          await FirebaseFirestore.instance.runTransaction((txn) async {
                            final snap = await txn.get(slotRef);
                            List bookedBy = [], bookedNames = [], bookedEmails = [];
                            if (snap.exists) {
                              final data = snap.data()!;
                              bookedBy = List.from(data['booked_by'] ?? []);
                              bookedNames = List.from(data['booked_names'] ?? []);
                              bookedEmails = List.from(data['booked_emails'] ?? []);
                              if (bookedBy.contains(client['uid'])) throw Exception("Already booked");
                              if (bookedBy.length >= slotCapacity) throw Exception("Slot full");
                            }
                            bookedBy.add(client['uid']);
                            bookedNames.add(client['name']);
                            bookedEmails.add(client['email']);

                            txn.set(slotRef, {
                              'booked_by': bookedBy,
                              'booked_names': bookedNames,
                              'booked_emails': bookedEmails,
                              'booked': bookedBy.length,
                              'capacity': slotCapacity,
                              'trainer_name': 'Kenny Sims',
                              'status': 'Confirmed',
                              'time': docId.split('|')[1],
                              'date': Timestamp.fromDate(_selectedDay),
                              'last_updated': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                          });

                          Navigator.pop(context);
                          _fetchFirestoreSlotsForDay(_selectedDay);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Booked successfully"), backgroundColor: Colors.green),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                          );
                        }
                      },
                child: const Text('Book'),
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
        title: const Text("Admin Slot Viewer"),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                _fetchFirestoreSlotsForDay(day);
              },
              headerStyle: const HeaderStyle(titleCentered: true, formatButtonVisible: false),
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                selectedDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
            ),
          ),
          Text(
            " ${DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay)}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1C2D5E)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: slotLabels.length,
              itemBuilder: (context, index) {
                final time = slotLabels[index];
                final docId = "$dateKey|$time";
                final data = _firestoreSlots[docId];
                final isFull = data != null && (data['booked_by']?.length ?? 0) >= slotCapacity;
                final bookedNames = data?['booked_names'] ?? [];
                final bookedCount = bookedNames.length;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              Text("Booked: $bookedCount / $slotCapacity"),
                              if (bookedNames.isNotEmpty)
                                Text("Clients: ${bookedNames.join(', ')}"),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: isFull ? null : () => _bookForClientDialog(docId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isFull ? Colors.grey : const Color(0xFF1C2D5E),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(isFull ? "Full" : "Book"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}