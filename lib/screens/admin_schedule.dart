// admin_schedule.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminScheduleScreen extends StatefulWidget {
  const AdminScheduleScreen({super.key});

  @override
  State<AdminScheduleScreen> createState() => _AdminScheduleScreenState();
}

class _AdminScheduleScreenState extends State<AdminScheduleScreen> {
  final List<String> timeSlots = [
    '5:30 AM', '6:00 AM', '6:30 AM', '7:00 AM', '7:30 AM', '8:00 AM',
    '8:30 AM', '9:00 AM', '9:30 AM', '10:00 AM', '10:30 AM', '11:00 AM',
    '4:30 PM', '5:00 PM', '5:30 PM', '6:00 PM', '6:30 PM', '7:00 PM',
  ];

  final Set<String> selectedSlots = {};
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadExistingSlots();
  }

  Future<void> _loadExistingSlots() async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final doc = await FirebaseFirestore.instance
        .collection('trainer_slots')
        .doc(formattedDate)
        .get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        selectedSlots.clear();
        selectedSlots.addAll(data.keys);
      });
    }
  }

  Future<void> _saveSlots() async {
    final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    final data = {
      for (var slot in selectedSlots)
        slot: {
          'capacity': 6,
          'bookedBy': [],
          'status': 'available',
        },
    };
    await FirebaseFirestore.instance.collection('trainer_slots').doc(formattedDate).set(data);
  }

  void _toggleSlot(String slot) {
    setState(() {
      if (selectedSlots.contains(slot)) {
        selectedSlots.remove(slot);
      } else {
        selectedSlots.add(slot);
      }
    });
  }

  void _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (date != null) {
      setState(() {
        selectedDate = date;
      });
      _loadExistingSlots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('EEE, MMM d, yyyy').format(selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Schedule'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await _saveSlots();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Schedule saved!')),
                );
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          ListTile(
            title: Text('Date: $formatted'),
            trailing: const Icon(Icons.calendar_month),
            onTap: _pickDate,
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: timeSlots.length,
              itemBuilder: (context, index) {
                final slot = timeSlots[index];
                return CheckboxListTile(
                  title: Text(slot),
                  value: selectedSlots.contains(slot),
                  onChanged: (_) => _toggleSlot(slot),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
