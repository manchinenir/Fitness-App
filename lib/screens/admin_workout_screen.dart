import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminWorkoutScreen extends StatefulWidget {
  const AdminWorkoutScreen({super.key});

  @override
  State<AdminWorkoutScreen> createState() => _AdminWorkoutScreenState();
}

class _AdminWorkoutScreenState extends State<AdminWorkoutScreen> with SingleTickerProviderStateMixin {
  // Color Scheme
  final Color _primaryColor = const Color(0xFF6C5CE7); // Purple
  final Color _secondaryColor = const Color(0xFF00CEFF); // Cyan
  final Color _accentColor = const Color(0xFFFD79A8); // Pink
  final Color _successColor = const Color(0xFF00B894); // Green
  final Color _cardColor = Colors.white;
  final Color _selectedCardColor = const Color(0xFFF5F6FA); // Light grey

  // App state
  late TabController _tabController;
  final List<String> _workoutTypes = ['Standard', 'Custom'];
  int _selectedWorkoutType = 0;
  
  // Client selection
  List<String> _selectedClientIds = [];
  bool _isLoadingClients = false;
  
  // Standard workouts
  String? _selectedStandardTemplate;
  final Map<String, List<String>> _standardWorkouts = {
    'Upper Body Strength & Core': [
      'Standing DB Shoulder Press 3x12',
      'DB Chest Press 3x15',
      'Body Weight Dips 3x20',
      'Sit Ups 3x15',
      'Single Arm DB Rows 3x15',
      'DB Hammer Curls 3x12'
    ],
    'Legs Blast': [
      'Leg Extensions 3x20',
      'Leg curl machine 3x15',
      'Leg Press 3x15',
      'Barbell Squat 3x10',
      'Dumbbell RDLs 3x15'
    ],
    'High Intensity Circuit': [
      'High Plank Jacks 3x45 secs',
      'V Sit Russian Twist 3x45 secs',
      'Dumbbell Incline Press 3x20 (40lbs)',
      'Dumbbell Goblet Squat 3x20 (40lbs)',
      'Jumping Jack 3x45 secs',
      'Standing Dumbbell Shoulder Press 3x20 (25lbs)'
    ]
  };
  
  // Custom workouts
  final List<String> _muscleGroups = [
    'Back', 'Chest', 'Legs', 'Shoulder', 'Triceps', 'Biceps'
  ];
  final Map<String, IconData> _muscleGroupIcons = {
    'Back': Icons.accessibility_new,
    'Chest': Icons.fitness_center,
    'Legs': Icons.directions_run,
    'Shoulder': Icons.arrow_upward,
    'Triceps': Icons.open_with,
    'Biceps': Icons.fitness_center
  };
  final Map<String, List<String>> _selectedCustomWorkouts = {};
  final Map<String, List<String>> _predefinedWorkouts = {
    'Back': [
      'Deadlift',
      'Pull-Up',
      'Bent Over Row',
      'Lat Pulldown',
      'Back Extension',
      'Single Arm Row'
    ],
    'Chest': [
      'Seated Fly Machine/Peck Deck 4x20',
      'Hammer Strength Incline Press 4x15',
      'Hammer Strength Decline 3x20',
      'Dumbbell Close Grip Press Flat Bench 3x15',
      'Cable Cross Over 3x20'
    ],
    'Legs': [
      'Leg Extensions 3x20',
      'Leg curl machine 3x15',
      'Leg Press 3x15',
      'Barbell Squat 3x10',
      'Dumbbell RDLs 3x15'
    ],
    'Shoulder': [
      'Standing DB Shoulder Press 3x12',
      'Overhead Press',
      'Lateral Raise',
      'Front Raise',
      'Arnold Press'
    ],
    'Triceps': [
      'Tricep Push Downs 3x20',
      'Dips 3x20',
      'Close Grip Bench Press',
      'Rope Pushdown',
      'Overhead Tricep Extension'
    ],
    'Biceps': [
      'Easy bar curls 3x15',
      'Cable Straight bar Curls 3x20',
      'Single Arm Dumbbell Preacher Curls 3x12 each arm',
      'DB Hammer Curls 3x12'
    ]
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _muscleGroups.length, vsync: this);
    // Initialize selected custom workouts
    for (var group in _muscleGroups) {
      _selectedCustomWorkouts[group] = [];
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectClients() async {
    setState(() => _isLoadingClients = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .get();

      final selected = await showDialog<List<String>>(
        context: context,
        builder: (context) => ClientSelectionDialog(
          clients: snapshot.docs,
          initiallySelected: _selectedClientIds,
          primaryColor: _primaryColor,
        ),
      );

      if (selected != null) {
        setState(() => _selectedClientIds = selected);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load clients: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    } finally {
      setState(() => _isLoadingClients = false);
    }
  }

  Future<void> _assignWorkouts() async {
    if (_selectedClientIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Confirm Workout Assignment',
        message: 'Assign ${_getWorkoutCount()} exercises to ${_selectedClientIds.length} clients?',
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (confirmed != true) return;

    try {
      final assignedAt = Timestamp.now();
      final trainerName = 'Kenny Sims'; // Replace with actual trainer

      final workoutData = {
        'assigned_at': assignedAt,
        'trainer': trainerName,
        'clients': _selectedClientIds,
        'type': _workoutTypes[_selectedWorkoutType].toLowerCase(),
        'workouts': _getWorkoutMap(),
      };

      final workoutRef = await FirebaseFirestore.instance
          .collection('workouts')
          .add(workoutData);

      // Assign to each client
      final batch = FirebaseFirestore.instance.batch();
      for (final clientId in _selectedClientIds) {
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(clientId)
            .collection('workouts')
            .doc(workoutRef.id);
        batch.set(ref, workoutData);
      }
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Workouts assigned successfully!'),
          backgroundColor: _successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      // Reset selections
      setState(() {
        if (_selectedWorkoutType == 0) {
          _selectedStandardTemplate = null;
        } else {
          for (var group in _muscleGroups) {
            _selectedCustomWorkouts[group] = [];
          }
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign workouts: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  Map<String, dynamic> _getWorkoutMap() {
    if (_selectedWorkoutType == 0) {
      return {_selectedStandardTemplate!: _standardWorkouts[_selectedStandardTemplate]!};
    } else {
      return Map.fromEntries(
        _selectedCustomWorkouts.entries.where((e) => e.value.isNotEmpty),
      );
    }
  }

  int _getWorkoutCount() {
    if (_selectedWorkoutType == 0) {
      return _selectedStandardTemplate != null 
          ? _standardWorkouts[_selectedStandardTemplate]!.length 
          : 0;
    } else {
      return _selectedCustomWorkouts.values.fold(
        0, (total, exercises) => total + exercises.length);
    }
  }

  Widget _buildStandardWorkouts() {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _standardWorkouts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final name = _standardWorkouts.keys.elementAt(index);
              final exercises = _standardWorkouts[name]!;
              return _WorkoutTemplateCard(
                name: name,
                exercises: exercises,
                isSelected: _selectedStandardTemplate == name,
                onSelect: () => setState(() => _selectedStandardTemplate = name),
                primaryColor: _primaryColor,
                selectedCardColor: _selectedCardColor,
                cardColor: _cardColor,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildCustomWorkouts() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: _primaryColor,
            unselectedLabelColor: Colors.grey[600],
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(width: 3, color: _primaryColor),
              insets: const EdgeInsets.symmetric(horizontal: 16),
            ),
            tabs: _muscleGroups.map((group) => Tab(
              icon: Icon(_muscleGroupIcons[group]),
              text: group,
            )).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _muscleGroups.map((group) {
              return _MuscleGroupWorkouts(
                group: group,
                exercises: _predefinedWorkouts[group]!,
                selected: _selectedCustomWorkouts[group]!,
                onSelect: (exercise, selected) {
                  setState(() {
                    if (selected) {
                      _selectedCustomWorkouts[group]!.add(exercise);
                    } else {
                      _selectedCustomWorkouts[group]!.remove(exercise);
                    }
                  });
                },
                primaryColor: _primaryColor,
                selectedCardColor: _selectedCardColor,
                cardColor: _cardColor,
              );
            }).toList(),
          ),
        ),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final isEnabled = _selectedClientIds.isNotEmpty && 
        ((_selectedWorkoutType == 0 && _selectedStandardTemplate != null) ||
         (_selectedWorkoutType == 1 && _getWorkoutCount() > 0));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.send, size: 20),
          label: const Text('Assign Workouts', style: TextStyle(fontSize: 16)),
          onPressed: isEnabled ? _assignWorkouts : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled ? _primaryColor : Colors.grey[400],
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Assign Workouts', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Container(
            color: _primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.category, size: 20, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      'Workout Type:',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ToggleButtons(
                        isSelected: List.generate(
                          _workoutTypes.length, 
                          (index) => _selectedWorkoutType == index),
                        onPressed: (index) {
                          setState(() => _selectedWorkoutType = index);
                        },
                        selectedColor: _primaryColor,
                        fillColor: Colors.white,
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        constraints: const BoxConstraints(minHeight: 36),
                        children: _workoutTypes
                            .map((type) => Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(type),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      icon: _isLoadingClients
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _primaryColor,
                              ),
                            )
                          : const Icon(Icons.people_alt, size: 20),
                      label: Text(
                        _selectedClientIds.isEmpty
                            ? 'Select Clients'
                            : '${_selectedClientIds.length} client(s) selected',
                        style: TextStyle(
                          color: _selectedClientIds.isEmpty 
                              ? Colors.grey[600] 
                              : _primaryColor,
                        ),
                      ),
                      onPressed: _selectClients,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        side: BorderSide(
                          color: _selectedClientIds.isEmpty 
                              ? Colors.grey[300]! 
                              : _primaryColor,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (_selectedClientIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 8),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.orange[400]),
                            const SizedBox(width: 8),
                            Text(
                              'Please select at least one client',
                              style: TextStyle(
                                color: Colors.orange[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _selectedWorkoutType == 0 
                  ? _buildStandardWorkouts() 
                  : _buildCustomWorkouts(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutTemplateCard extends StatelessWidget {
  final String name;
  final List<String> exercises;
  final bool isSelected;
  final VoidCallback onSelect;
  final Color primaryColor;
  final Color selectedCardColor;
  final Color cardColor;

  const _WorkoutTemplateCard({
    required this.name,
    required this.exercises,
    required this.isSelected,
    required this.onSelect,
    required this.primaryColor,
    required this.selectedCardColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? selectedCardColor : cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.grey[200]!,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? primaryColor : Colors.grey[400]!,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check, size: 16, color: primaryColor)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? primaryColor : Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...exercises.map((exercise) => Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•', style: TextStyle(color: primaryColor)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        exercise,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuscleGroupWorkouts extends StatelessWidget {
  final String group;
  final List<String> exercises;
  final List<String> selected;
  final Function(String, bool) onSelect;
  final Color primaryColor;
  final Color selectedCardColor;
  final Color cardColor;

  const _MuscleGroupWorkouts({
    required this.group,
    required this.exercises,
    required this.selected,
    required this.onSelect,
    required this.primaryColor,
    required this.selectedCardColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: exercises.length,
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        final isSelected = selected.contains(exercise);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            elevation: isSelected ? 2 : 0,
            color: isSelected ? selectedCardColor : cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: isSelected ? primaryColor : Colors.grey[200]!,
                width: isSelected ? 1 : 0.5,
              ),
            ),
            child: CheckboxListTile(
              title: Text(
                exercise,
                style: TextStyle(
                  color: isSelected ? primaryColor : Colors.grey[800],
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
              value: isSelected,
              onChanged: (value) => onSelect(exercise, value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        );
      },
    );
  }
}

class ClientSelectionDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> clients;
  final List<String> initiallySelected;
  final Color primaryColor;

  const ClientSelectionDialog({
    super.key,
    required this.clients,
    required this.initiallySelected,
    required this.primaryColor,
  });

  @override
  State<ClientSelectionDialog> createState() => _ClientSelectionDialogState();
}

class _ClientSelectionDialogState extends State<ClientSelectionDialog> {
  late Set<String> _selectedIds;
  TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _filteredClients = [];

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initiallySelected);
    _filteredClients = widget.clients;
    _searchController.addListener(_filterClients);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterClients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredClients = widget.clients.where((client) {
        final data = client.data() as Map<String, dynamic>;
        final name = data['name']?.toString().toLowerCase() ?? '';
        return name.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Clients',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search clients',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: widget.primaryColor),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredClients.length,
                itemBuilder: (context, index) {
                  final client = _filteredClients[index];
                  final data = client.data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'Unnamed Client';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                      child: CheckboxListTile(
                        title: Text(name),
                        value: _selectedIds.contains(client.id),
                        onChanged: (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedIds.add(client.id);
                            } else {
                              _selectedIds.remove(client.id);
                            }
                          });
                        },
                        activeColor: widget.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selectedIds.toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final Color primaryColor;
  final Color accentColor;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.primaryColor,
    this.accentColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}