import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
 
class ClientWorkoutScreen extends StatefulWidget {
  const ClientWorkoutScreen({super.key});
 
  @override
  State<ClientWorkoutScreen> createState() => _ClientWorkoutScreenState();
}
 
class _ClientWorkoutScreenState extends State<ClientWorkoutScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final _dateFormatter = DateFormat('MMM d, yyyy');
  final _timeFormatter = DateFormat('hh:mm a');
  final Color _primaryColor = const Color(0xFF1C2D5E);
  final Color _accentColor = Colors.blue[700]!;
  final Color _successColor = Colors.green[700]!;
  final Color _textColor = Colors.blue[900]!;
 
  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return _buildAuthErrorScreen();
    }
 
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "My Workouts",
          style: TextStyle(
            color: Colors.white,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildWorkoutList(),
    );
  }
 
  Widget _buildWorkoutList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('workouts')
          .where('assigned_at', isGreaterThan: Timestamp(0, 0))
          .orderBy('assigned_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          );
        }
 
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }
 
        final workouts = snapshot.data!.docs;
 
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: workouts.length,
          itemBuilder: (context, index) {
            final doc = workouts[index];
            final data = doc.data() as Map<String, dynamic>;
            final workoutMap = data['workouts'] as Map<String, dynamic>;
            final assignedAt = (data['assigned_at'] as Timestamp).toDate();
            final trainerName = data['trainer'] ?? 'Your Trainer';
            final isMostRecent = index == 0;
            final workoutTitle = data['title'] ?? 'Workout Plan ${index + 1}';
            final hasRating = data['rating'] != null;
 
            return _buildWorkoutCard(
              context: context,
              title: workoutTitle,
              assignedAt: assignedAt,
              trainerName: trainerName,
              workoutMap: workoutMap,
              isMostRecent: isMostRecent,
              index: index,
              documentId: doc.id,
              hasRating: hasRating,
              currentRating: hasRating ? data['rating'] : null,
            );
          },
        );
      },
    );
  }
 
  Widget _buildWorkoutCard({
    required BuildContext context,
    required String title,
    required DateTime assignedAt,
    required String trainerName,
    required Map<String, dynamic> workoutMap,
    required bool isMostRecent,
    required int index,
    required String documentId,
    required bool hasRating,
    int? currentRating,
  }) {
    return Card(
      elevation: isMostRecent ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMostRecent ? _accentColor : Colors.grey.withOpacity(0.2),
          width: isMostRecent ? 1.5 : 1,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: isMostRecent,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isMostRecent ? _primaryColor : Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              (index + 1).toString(),
              style: TextStyle(
                color: isMostRecent ? Colors.white : _primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: _textColor),
                const SizedBox(width: 4),
                Text(
                  _dateFormatter.format(assignedAt),
                  style: TextStyle(fontSize: 12, color: _textColor),
                ),
                const SizedBox(width: 8),
                Icon(Icons.access_time, size: 14, color: _textColor),
                const SizedBox(width: 4),
                Text(
                  _timeFormatter.format(assignedAt),
                  style: TextStyle(fontSize: 12, color: _textColor),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14, color: _textColor),
                const SizedBox(width: 4),
                Text(
                  'By: $trainerName',
                  style: TextStyle(fontSize: 12, color: _textColor),
                ),
              ],
            ),
          ],
        ),
        trailing: isMostRecent
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _successColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _successColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: _successColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _showRatingDialog(documentId, currentRating),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasRating ? Icons.star : Icons.star_outline,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          hasRating ? currentRating.toString() : 'Rate',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                ...workoutMap.entries.map((entry) => _buildWorkoutDetails(entry)).toList(),
                if (isMostRecent) _buildStartWorkoutButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildWorkoutDetails(MapEntry<String, dynamic> entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.key.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: _primaryColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...(entry.value as List).map((exercise) {
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: _accentColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      exercise,
                      style: TextStyle(fontSize: 14, height: 1.4, color: _textColor),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
 
  Widget _buildStartWorkoutButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text(
            "BEGIN WORKOUT",
            style: TextStyle(letterSpacing: 0.8),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
          ),
          onPressed: () {
            // Implement workout start
          },
        ),
      ),
    );
  }
 
  Future<void> _showRatingDialog(String workoutId, int? currentRating) async {
    int? selectedRating = currentRating;
   
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Rate this workout"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("How would you rate this workout plan?"),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          selectedRating != null && index < selectedRating!
                            ? Icons.star
                            : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setState(() {
                            selectedRating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                  ),
                  onPressed: selectedRating == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          _submitRating(workoutId, selectedRating!);
                        },
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );
      },
    );
  }
 
  Future<void> _submitRating(String workoutId, int rating) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('workouts')
          .doc(workoutId)
          .update({
            'rating': rating,
            'ratedAt': FieldValue.serverTimestamp(),
          });
 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Thanks for your rating!"),
          backgroundColor: _successColor,
        )
      );
 
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to submit rating: ${e.toString()}"),
          backgroundColor: Colors.red,
        )
      );
    }
  }
 
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center, size: 64, color: _primaryColor),
            const SizedBox(height: 24),
            Text(
              "No Workouts Assigned",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Your trainer hasn't assigned any workouts yet. Check back later or contact your trainer.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _textColor,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: BorderSide(color: _primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () => setState(() {}),
              child: const Text("REFRESH"),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildAuthErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: _primaryColor),
            const SizedBox(height: 24),
            Text(
              "Authentication Required",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Please sign in to access your workout plans",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _textColor,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () {
                // Handle sign in
              },
              child: const Text(
                "SIGN IN",
                style: TextStyle(
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 