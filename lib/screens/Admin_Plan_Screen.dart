import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  _PlansScreenState createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controllers for form fields
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _sessionsController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Selected values for dropdowns
  String _selectedCategory = 'Semi Private Monthly Plans';
  String _selectedStatus = 'Active';
  String _selectedFilterCategory = 'Semi Private Monthly Plans';

  // Current editing index (-1 means adding new plan)
  int _editingIndex = -1;
  String? _editingDocId; // Store document ID for editing

  // Plans data - now populated from Firestore
  List<Map<String, dynamic>> _plans = [];

  // Plan categories
  final List<String> _categories = [
    'Semi Private Monthly Plans',
    'Semi Private Bi Weekly Plans',
    'Semi Private Day Pass',
    'Group Training or Class',
    'Strength & Agility Session (High School Athlete)',
    'Strength & Agility Session (Kids)',
    'Athletic Performance (Adult)',
  ];

  // Status options
  final List<String> _statusOptions = ['Active', 'Inactive'];

  // Track expanded plan cards
  int? _expandedPlanIndex;

  @override
  void initState() {
    super.initState();
    _loadInitialPlans();
  }

  // Load initial plans to Firestore (always overwrite)
  Future<void> _loadInitialPlans() async {
    try {
      // Initial plans data
      List<Map<String, dynamic>> initialPlans = [
        {
          'name': '4 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 4,
          'price': 185.0,
          'status': 'Active',
          'description': '4 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '8 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 8,
          'price': 375.0,
          'status': 'Active',
          'description': '8 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '12 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 12,
          'price': 500.0,
          'status': 'Active',
          'description': '12 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '16 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 16,
          'price': 600.0,
          'status': 'Active',
          'description': '16 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '4 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 4,
          'price': 94.0,
          'status': 'Active',
          'description': '4 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '8 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 8,
          'price': 187.0,
          'status': 'Active',
          'description': '8 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '12 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 12,
          'price': 260.0,
          'status': 'Active',
          'description': '12 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '16 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 16,
          'price': 310.0,
          'status': 'Active',
          'description': '16 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Day Pass',
          'category': 'Semi Private Day Pass',
          'sessions': 1,
          'price': 40.0,
          'status': 'Active',
          'description': 'Single day pass for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Group Training',
          'category': 'Group Training or Class',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Single session for group training or class',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'High School Athlete',
          'category': 'Strength & Agility Session (High School Athlete)',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Strength and agility session for high school athletes',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Kids Session',
          'category': 'Strength & Agility Session (Kids)',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Strength and agility session for kids',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Athletic Performance Adult',
          'category': 'Athletic Performance (Adult)',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Athletic performance training for adults',
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      WriteBatch batch = _firestore.batch();
      final colRef = _firestore.collection('plans');
      final existing = await colRef.get();
      for (var doc in existing.docs) {
        batch.delete(doc.reference);
      }
      for (var plan in initialPlans) {
        batch.set(colRef.doc(), plan);
      }
      await batch.commit();
      print('Initial plans loaded to Firestore');
    } catch (e) {
      print('Error loading initial plans: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _sessionsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _nameController.clear();
    _priceController.clear();
    _sessionsController.clear();
    _descriptionController.clear();
    _selectedCategory = 'Semi Private Monthly Plans';
    _selectedStatus = 'Active';
    _editingIndex = -1;
    _editingDocId = null;
  }

  void _showAddEditDialog({int? index}) {
    if (index != null) {
      _editingIndex = index;
      final plan = _plans[index];
      _editingDocId = plan['docId'];
      _nameController.text = plan['name'];
      _priceController.text = plan['price'].toString();
      _sessionsController.text = plan['sessions'].toString();
      _descriptionController.text = plan['description'];
      _selectedCategory = plan['category'];
      _selectedStatus = plan['status'];
    } else {
      _clearForm();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Align(
          alignment: Alignment.center,
          child: FractionallySizedBox(
            widthFactor: 0.9,
            child: AlertDialog(
              insetPadding: EdgeInsets.zero,
              scrollable: true,
              title: Text(
                _editingIndex == -1 ? 'Add New Plan' : 'Edit Plan',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00BCD4),
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Plan Name *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.fitness_center),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter plan name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: _categories.map((String category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(category, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedCategory = newValue!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _sessionsController,
                        decoration: const InputDecoration(
                          labelText: 'Number of Sessions *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.numbers),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter number of sessions';
                          }
                          int? sessions = int.tryParse(value);
                          if (sessions == null || sessions <= 0) {
                            return 'Please enter a valid number of sessions';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price (\$) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter price';
                          }
                          double? price = double.tryParse(value);
                          if (price == null || price <= 0) {
                            return 'Please enter a valid price';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Status *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.toggle_on),
                        ),
                        items: _statusOptions.map((String status) {
                          return DropdownMenuItem<String>(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedStatus = newValue!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter description';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _clearForm();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _savePlan();
                      Navigator.of(context).pop();
                      _clearForm();
                    }
                  },
                  child: Text(_editingIndex == -1 ? 'Add Plan' : 'Update Plan'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Save plan to Firestore
  Future<void> _savePlan() async {
    try {
      final planData = {
        'name': _nameController.text.trim(),
        'category': _selectedCategory,
        'sessions': int.parse(_sessionsController.text),
        'price': double.parse(_priceController.text),
        'status': _selectedStatus,
        'description': _descriptionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_editingIndex == -1) {
        // Add new plan
        planData['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('plans').add(planData);
        _showSnackBar('Plan added successfully!');
      } else {
        // Update existing plan
        if (_editingDocId != null) {
          await _firestore.collection('plans').doc(_editingDocId).update(planData);
          _showSnackBar('Plan updated successfully!');
        }
      }
    } catch (e) {
      _showSnackBar('Error saving plan: $e');
      print('Error saving plan: $e');
    }
  }

  // Delete plan from Firestore
  Future<void> _deletePlan(int index) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Plan'),
          content: Text('Are you sure you want to delete "${_plans[index]['name']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  String? docId = _plans[index]['docId'];
                  if (docId != null) {
                    await _firestore.collection('plans').doc(docId).delete();
                    _showSnackBar('Plan deleted successfully!');
                  }
                } catch (e) {
                  _showSnackBar('Error deleting plan: $e');
                  print('Error deleting plan: $e');
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Plans Management'),
        backgroundColor: const Color(0xFF1C2D5E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1C2D5E), Color(0xFF26C6DA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fitness Plans',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Manage your fitness training plans and pricing',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            // Add Plan Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddEditDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Plan'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),

            // Dynamic Category Filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('plans').snapshots(),
                builder: (ctx, snap) {
                  final all = snap.data?.docs.map((d) {
                        final m = d.data()! as Map<String, dynamic>;
                        m['docId'] = d.id;
                        return m;
                      }).toList() ??
                      [];
                  _plans = all;
                  final cats = [
                    'Semi Private Monthly Plans',
                    'Semi Private Bi Weekly Plans',
                    'Semi Private Day Pass',
                    'Group Training or Class',
                    'Strength & Agility Session (High School Athlete)',
                    'Strength & Agility Session (Kids)',
                    'Athletic Performance (Adult)',
                  ];
                  return DropdownButtonFormField<String>(
                    value: _selectedFilterCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category Filter',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.filter_list),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: cats
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedFilterCategory = v!;
                      _expandedPlanIndex = null;
                    }),
                    isExpanded: true,
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Plans List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('plans').snapshots(),
                builder: (ctx, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  final visible = docs
                      .map((d) {
                        final m = d.data()! as Map<String, dynamic>;
                        m['docId'] = d.id;
                        return m;
                      })
                      .where((p) =>
                          p['category'] == _selectedFilterCategory && p['status'] == 'Active')
                      .toList();

                  late List<Map<String, dynamic>> ordered;
                  if (_selectedFilterCategory == 'Semi Private Monthly Plans' ||
                      _selectedFilterCategory == 'Semi Private Bi Weekly Plans') {
                    final order = [4, 8, 12, 16];
                    ordered = order
                        .map((s) => visible.firstWhere((p) => p['sessions'] == s,
                            orElse: () => <String, dynamic>{}))
                        .where((p) => p.isNotEmpty)
                        .toList();
                  } else {
                    ordered = visible;
                  }

                  if (ordered.isEmpty) {
                    return Center(child: Text('No $_selectedFilterCategory available'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: ordered.length,
                    itemBuilder: (c, i) {
                      final plan = ordered[i];
                      final expanded = _expandedPlanIndex == i;
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            onTap: () => setState(() => _expandedPlanIndex = expanded ? null : i),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          '${plan['sessions']} sessions a month',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '\$${(plan['price'] as num).toStringAsFixed(2)}',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                                    ],
                                  ),
                                  if (expanded) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      plan['description'] ?? '',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            final idx = _plans.indexWhere((p) => p['docId'] == plan['docId']);
                                            _showAddEditDialog(index: idx);
                                          },
                                          icon: const Icon(Icons.edit, size: 18),
                                          label: const Text('Edit'),
                                        ),
                                        const SizedBox(width: 4),
                                        TextButton.icon(
                                          onPressed: () {
                                            final idx = _plans.indexWhere((p) => p['docId'] == plan['docId']);
                                            _deletePlan(idx);
                                          },
                                          icon: const Icon(Icons.delete, size: 18),
                                          label: const Text('Delete'),
                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}