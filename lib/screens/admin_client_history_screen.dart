// ================================
// admin_client_history_screen.dart
// View Workout History per Client (Admin) + Re-send Button
// ================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminClientHistoryScreen extends StatefulWidget {
  const AdminClientHistoryScreen({super.key});

  @override
  State<AdminClientHistoryScreen> createState() => _AdminClientHistoryScreenState();
}

class _AdminClientHistoryScreenState extends State<AdminClientHistoryScreen> {
  String? selectedClientId;
  String? selectedClientName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Client Workout History"),
        backgroundColor: const Color(0xFF1C2D5E),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildClientDropdown(),
          const SizedBox(height: 12),
          Expanded(
            child: selectedClientId == null
                ? const Center(child: Text('Please select a client.'))
                : _buildWorkoutHistoryList(),
          )
        ],
      ),
    );
  }

  Widget _buildClientDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'client')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const CircularProgressIndicator();
          }

          final clients = snapshot.data!.docs;
          return DropdownButtonFormField<String>(
            value: selectedClientId,
            decoration: const InputDecoration(
              labelText: "Select Client",
              border: OutlineInputBorder(),
            ),
            items: clients.map((doc) {
              final clientName = doc.data().toString().contains('name') ? doc['name'] : 'Unnamed';
              return DropdownMenuItem(
                value: doc.id,
                child: Text(clientName),
              );
            }).toList(),
            onChanged: (value) {
              final selectedDoc = clients.firstWhere((doc) => doc.id == value);
              setState(() {
                selectedClientId = value;
                selectedClientName = selectedDoc.data().toString().contains('name') ? selectedDoc['name'] : 'Unnamed';
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildWorkoutHistoryList() {
    final workoutStream = FirebaseFirestore.instance
        .collection('client_workouts')
        .doc(selectedClientId)
        .collection('workouts')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: workoutStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No workout history found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final date = doc['date'] ?? '';
            final trainer = doc['trainer'] ?? '';
            final workouts = Map<String, dynamic>.from(doc['workouts']);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📅 $date', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Trainer: $trainer'),
                    const SizedBox(height: 10),
                    ...workouts.entries.map((entry) {
                      final category = entry.key;
                      final List exercises = entry.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$category:', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ...exercises.map((e) => Text('- $e')).toList(),
                          const SizedBox(height: 8),
                        ],
                      );
                    }),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Re-send Workout'),
                      onPressed: () async {
                        final newDate = DateTime.now();
                        final formattedDate = "${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}";

                        await FirebaseFirestore.instance
                            .collection('client_workouts')
                            .doc(selectedClientId)
                            .collection('workouts')
                            .add({
                          'date': formattedDate,
                          'trainer': trainer,
                          'workouts': workouts,
                          'timestamp': FieldValue.serverTimestamp(),
                          'hasNewWorkout': true,
                        });

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(selectedClientId)
                            .update({'hasNewWorkout': true});

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Workout re-sent successfully.')),
                        );
                      },
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}