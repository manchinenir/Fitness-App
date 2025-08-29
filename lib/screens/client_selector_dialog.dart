import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientSelectorDialog extends StatefulWidget {
  @override
  _ClientSelectorDialogState createState() => _ClientSelectorDialogState();
}

class _ClientSelectorDialogState extends State<ClientSelectorDialog> {
  final Set<String> selectedClientIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select Clients"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final clients = snapshot.data!.docs;

            return ListView.builder(
              itemCount: clients.length,
              itemBuilder: (context, index) {
                final client = clients[index];
                final data = client.data() as Map<String, dynamic>;
                final clientId = client.id;
                final name = data['name'] ?? 'Unnamed';
                final email = data['email'] ?? '';

                return CheckboxListTile(
                  value: selectedClientIds.contains(clientId),
                  title: Text(name),
                  subtitle: Text(email),
                  onChanged: (selected) {
                    setState(() {
                      if (selected!) {
                        selectedClientIds.add(clientId);
                      } else {
                        selectedClientIds.remove(clientId);
                      }
                    });
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            if (selectedClientIds.isNotEmpty) {
              Navigator.of(context).pop(selectedClientIds.toList());
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select at least one client')),
              );
            }
          },
          child: const Text("Assign"),
        ),
      ],
    );
  }
}
