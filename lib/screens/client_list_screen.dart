import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:percent_indicator/percent_indicator.dart';

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2D5E),
        title: const Text('Client List', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              _buildClientHeader(),
              const SizedBox(height: 8),
              _buildSearchBar(),
              const SizedBox(height: 8),
              _buildClientList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final count = snapshot.data!.docs.length;
        final percent = (count / 100).clamp(0.0, 1.0); // Reference max: 100

        return CircularPercentIndicator(
          radius: 70.0,
          lineWidth: 12.0,
          percent: percent,
          animation: true,
          center: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.group, size: 24, color: Colors.green),
              Text('$count', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text("Clients", style: TextStyle(fontSize: 12)),
            ],
          ),
          progressColor: Colors.green,
          backgroundColor: Colors.grey.shade300,
          circularStrokeCap: CircularStrokeCap.round,
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TextField(
        onChanged: (value) => setState(() => searchQuery = value.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search by name or email',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildClientList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final allClients = snapshot.data!.docs;
        final filteredClients = allClients.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final email = (data['email'] ?? '').toString().toLowerCase();
          return name.contains(searchQuery) || email.contains(searchQuery);
        }).toList();

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredClients.length,
          itemBuilder: (context, index) {
            final doc = filteredClients[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name']?.toString().trim().isNotEmpty == true ? data['name'] : 'No Name';
            final email = data['email'] ?? 'No Email';
            final phone = data['phone'] ?? 'No Phone';

            return Card(
              color: Colors.white,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(name),
                subtitle: Text('Email: $email\nPhone: $phone'),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editClient(doc.id, data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmDelete(doc.id),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _editClient(String docId, Map<String, dynamic> currentData) {
    final nameController = TextEditingController(text: currentData['name'] ?? '');
    final phoneController = TextEditingController(text: currentData['phone'] ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('users').doc(docId).update({
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                });
                Navigator.pop(context);
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error saving client: $e'),
                  backgroundColor: Colors.red,
                ));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Client?'),
        content: const Text('Are you sure you want to delete this client?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('users').doc(docId).delete();
                Navigator.pop(context);
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error deleting client: $e'),
                  backgroundColor: Colors.red,
                ));
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
