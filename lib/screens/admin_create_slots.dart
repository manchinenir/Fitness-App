import 'dart:async';
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

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _dayListener;

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
    _listenToDay(_selectedDay);
  }

  @override
  void dispose() {
    _dayListener?.cancel();
    super.dispose();
  }

  // -------- Real-time day listener (the important bit) --------
  void _listenToDay(DateTime date) {
    _dayListener?.cancel();

    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final col = FirebaseFirestore.instance.collection('trainer_slots');

    _dayListener = col
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: '$dateKey|')
        .where(FieldPath.documentId, isLessThan: '$dateKey|z')
        .snapshots()
        .listen((snap) {
      final Map<String, dynamic> slots = {
        for (final doc in snap.docs) doc.id: doc.data()
      };
      if (mounted) {
        setState(() => _firestoreSlots = slots);
      }
    }, onError: (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error listening slots: $e')),
      );
    });
  }

  List<String> generateHourlySlots(DateTime date) {
    final String weekday = DateFormat('EEEE').format(date);
    final blocks = availabilityMap[weekday] ?? [];
    final slotLabels = <String>[];

    for (var block in blocks) {
      final startTime = DateFormat("HH:mm").parse(block['start']!);
      final endTime = DateFormat("HH:mm").parse(block['end']!);

      DateTime currentSlot = DateTime(
        date.year, date.month, date.day, startTime.hour, startTime.minute,
      );

      final slotEnd = DateTime(
        date.year, date.month, date.day, endTime.hour, endTime.minute,
      );

      while (currentSlot.isBefore(slotEnd)) {
        final nextSlot = currentSlot.add(const Duration(hours: 1));
        final label =
            "${DateFormat.jm().format(currentSlot)} - ${DateFormat.jm().format(nextSlot)}";
        slotLabels.add(label);
        currentSlot = nextSlot;
      }
    }
    return slotLabels;
  }

  void _bookForClientDialog(String docId) async {
    List<Map<String, dynamic>> clients = [];
    Map<String, bool> selectedClients = {};

    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();
      clients = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'name': data['name'] ?? 'No name',
          'email': data['email'] ?? '',
        };
      }).toList();
      selectedClients = {for (var c in clients) c['uid']: false};
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching users: $e")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Book Slot for Clients",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E))),
                  const SizedBox(height: 8),
                  Text("Time: ${docId.split('|')[1]}",
                      style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 20),
                  const Text("Select Clients:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    width: double.maxFinite,
                    child: ListView.builder(
                      itemCount: clients.length,
                      itemBuilder: (context, index) {
                        final client = clients[index];
                        return CheckboxListTile(
                          title: Text(client['name']),
                          subtitle: Text(client['email']),
                          value: selectedClients[client['uid']] ?? false,
                          onChanged: (v) {
                            setStateDialog(() {
                              selectedClients[client['uid']] = v ?? false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("CANCEL"),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C2D5E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          try {
                            final selectedClientIds = selectedClients.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();
                            if (selectedClientIds.isEmpty) {
                              throw Exception("Please select at least one client");
                            }

                            final selectedClientsData = clients
                                .where((c) => selectedClientIds.contains(c['uid']))
                                .toList();

                            final slotRef = FirebaseFirestore.instance
                                .collection('trainer_slots')
                                .doc(docId);

                            await FirebaseFirestore.instance.runTransaction((txn) async {
                              final snap = await txn.get(slotRef);
                              List bookedBy = [], bookedNames = [], bookedEmails = [];
                              if (snap.exists) {
                                final data = snap.data()!;
                                bookedBy = List.from(data['booked_by'] ?? []);
                                bookedNames = List.from(data['booked_names'] ?? []);
                                bookedEmails = List.from(data['booked_emails'] ?? []);

                                for (var client in selectedClientsData) {
                                  if (bookedBy.contains(client['uid'])) {
                                    throw Exception("${client['name']} is already booked");
                                  }
                                }
                                if (bookedBy.length + selectedClientIds.length > slotCapacity) {
                                  throw Exception("Not enough capacity");
                                }
                              }

                              for (var client in selectedClientsData) {
                                bookedBy.add(client['uid']);
                                bookedNames.add(client['name']);
                                bookedEmails.add(client['email']);
                              }

                              final fullData = {
                                'booked_by': bookedBy,
                                'booked_names': bookedNames,
                                'booked_emails': bookedEmails,
                                'booked': bookedBy.length,
                                'capacity': slotCapacity,
                                'trainer_name': 'Kenny Sims',
                                'status': 'Confirmed',
                                'time': docId.split('|')[1],
                                'date': Timestamp.fromDate(DateTime(
                                  _selectedDay.year, _selectedDay.month, _selectedDay.day,
                                )),
                                'date_time': Timestamp.fromDate(_selectedDay),
                                'last_updated': FieldValue.serverTimestamp(),
                              };

                              // set (overwrite) to keep slot doc sane
                              txn.set(slotRef, fullData);
                            });

                            // nudge user docs so their listeners fire
                            for (var clientId in selectedClientIds) {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(clientId)
                                  .update({'last_updated': FieldValue.serverTimestamp()});
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              // No need to manually refresh: listener will update UI
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Booked successfully"), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                            );
                          }
                        },
                        child: const Text("CONFIRM"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  

  void _cancelBookingDialog(String docId, Map<String, dynamic> slotData) {
  final bookedNames = List<String>.from(slotData['booked_names'] ?? []);
  final bookedUids = List<String>.from(slotData['booked_by'] ?? []);

  // Add validation to prevent errors if arrays are empty or mismatched
  if (bookedNames.isEmpty || bookedUids.isEmpty || bookedNames.length != bookedUids.length) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Error: Invalid booking data")),
    );
    return;
  }

  final Map<String, bool> selectedClients = {
    for (var i = 0; i < bookedUids.length; i++) 
      bookedUids[i]: false
  };

  showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setStateDialog) {
        return AlertDialog(
          title: const Text("Cancel Bookings"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Time: ${docId.split('|')[1]}"),
                const SizedBox(height: 16),
                const Text("Select Clients to Cancel:"),
                const SizedBox(height: 8),
                ...bookedNames.asMap().entries.map((entry) {
                  final index = entry.key;
                  final name = entry.value;
                  return CheckboxListTile(
                    title: Text(name),
                    value: selectedClients[bookedUids[index]] ?? false,
                    onChanged: (value) {
                      if (index >= 0 && index < bookedUids.length) {
                        setStateDialog(() {
                          selectedClients[bookedUids[index]] = value ?? false;
                        });
                      }
                    },
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                try {
                  final selectedClientIds = selectedClients.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .toList();

                  if (selectedClientIds.isEmpty) {
                    throw Exception("Please select at least one client");
                  }

                  final slotRef = FirebaseFirestore.instance
                      .collection('trainer_slots')
                      .doc(docId);

                  await FirebaseFirestore.instance.runTransaction((txn) async {
                    final snap = await txn.get(slotRef);
                    if (!snap.exists) throw Exception("Slot not found");

                    final data = snap.data()!;
                    List bookedBy = List.from(data['booked_by'] ?? []);
                    List bookedNames = List.from(data['booked_names'] ?? []);
                    List bookedEmails = List.from(data['booked_emails'] ?? []);

                    // Safe removal using indices
                    for (var i = bookedBy.length - 1; i >= 0; i--) {
                      if (selectedClientIds.contains(bookedBy[i])) {
                        if (i < bookedNames.length) bookedNames.removeAt(i);
                        if (i < bookedEmails.length) bookedEmails.removeAt(i);
                        bookedBy.removeAt(i);
                      }
                    }

                    txn.set(
                      slotRef,
                      {
                        'booked_by': bookedBy,
                        'booked_names': bookedNames,
                        'booked_emails': bookedEmails,
                        'booked': bookedBy.length,
                        'last_updated': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );
                  });

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Cancelled successfully"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Error: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text("CONFIRM CANCEL"),
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
        title: const Text("Trainer Schedule",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C2D5E),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
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
                  // switch listener to the newly selected day
                  _listenToDay(day);
                },
                headerStyle: const HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  leftChevronIcon: Icon(Icons.chevron_left, color: Color(0xFF1C2D5E)),
                  rightChevronIcon: Icon(Icons.chevron_right, color: Color(0xFF1C2D5E)),
                  headerMargin: EdgeInsets.only(bottom: 8),
                ),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: const Color(0xFF1C2D5E).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: Color(0xFF1C2D5E),
                    shape: BoxShape.circle,
                  ),
                  weekendTextStyle: const TextStyle(color: Colors.black),
                  outsideDaysVisible: false,
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20, color: Color(0xFF1C2D5E)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C2D5E)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: slotLabels.length,
                  itemBuilder: (context, index) {
                    final time = slotLabels[index];
                    final docId = "$dateKey|$time";
                    final data = _firestoreSlots[docId];
                    final isFull = data != null && (data['booked_by']?.length ?? 0) >= slotCapacity;
                    final bookedNames = List<String>.from(data?['booked_names'] ?? []);
                    final bookedCount = bookedNames.length;
                    final hasBookings = bookedCount > 0;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
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
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: isFull ? Colors.red : Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isFull ? "Fully Booked" : "Available",
                                        style: TextStyle(color: isFull ? Colors.red : Colors.green),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "$bookedCount / $slotCapacity",
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  if (bookedNames.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Clients: ${bookedNames.join(', ')}",
                                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (hasBookings)
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: () => _cancelBookingDialog(docId, data!),
                                tooltip: "Cancel bookings",
                              ),
                            ElevatedButton(
                              onPressed: isFull ? null : () => _bookForClientDialog(docId),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isFull ? Colors.grey[300] : const Color(0xFF1C2D5E),
                                foregroundColor: isFull ? Colors.grey : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(isFull ? "FULL" : "BOOK"),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
