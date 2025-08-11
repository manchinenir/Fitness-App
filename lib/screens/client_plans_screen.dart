import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientPlansScreen extends StatefulWidget {
  const ClientPlansScreen({super.key});

  @override
  State<ClientPlansScreen> createState() => _ClientPlansScreenState();
}

class _ClientPlansScreenState extends State<ClientPlansScreen> {
  final List<Map<String, String>> plans = [
    {'title': 'Personal Training', 'subtitle': '8 sessions/month (1 hour)', 'price': '\$200'},
    {'title': 'Group Fitness', 'subtitle': 'Drop-In Group Training', 'price': '\$30'},
    {'title': 'Youth Strength & Agility', 'subtitle': 'Private (1 hour)', 'price': '\$40'},
    {'title': 'Youth Strength & Agility', 'subtitle': 'Group Training (1 hour)', 'price': '\$25'},
    {'title': 'Semi-Private', 'subtitle': '4/month', 'price': '\$185'},
    {'title': 'Semi-Private', 'subtitle': '8/month', 'price': '\$375'},
    {'title': 'Semi-Private', 'subtitle': '12/month', 'price': '\$560'},
    {'title': 'Drop-In Semi-Private', 'subtitle': '', 'price': '\$50'},
    {'title': '6-Week Meal Plan', 'subtitle': '', 'price': '\$100'},
  ];

  List<String> _purchasedPlans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchasedPlans();
  }

  Future<void> _loadPurchasedPlans() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _purchasedPlans = [];
          _isLoading = false;
        });
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('purchased_plans')
          .where('isActive', isEqualTo: true)
          .get();

      setState(() {
        _purchasedPlans = snapshot.docs
            .map((doc) => doc.data()['planTitle'] as String)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _purchasedPlans = [];
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading plans: ${e.toString()}')),
        );
      }
    }
  }

  /// ✅ Full plan detail, revenue, subtitle, and live update support!
  Future<void> _buyPlan(Map<String, String> plan) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to purchase plans')),
        );
        return;
      }

      // Convert "$200" → 200.0 (numeric, for revenue calculation)
      final priceStr = plan['price']?.replaceAll('\$', '') ?? '0';
      final priceDouble = double.tryParse(priceStr) ?? 0;

      // For live update and multiple purchases, append unique time to doc ID
      final docId = '${plan['title']!.replaceAll(' ', '').toLowerCase()}${DateTime.now().millisecondsSinceEpoch}';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('purchased_plans')
          .doc(docId)
          .set({
        'planTitle': plan['title'],
        'planSubtitle': plan['subtitle'],
        'price': priceDouble,
        'purchaseDate': DateTime.now(),
        'isActive': true,
        'userId': user.uid,
      });

      setState(() {
        _purchasedPlans.add(plan['title']!);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error purchasing plan: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2D5E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Training Plans & Pricing',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: plans.length,
             separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final plan = plans[index];
                final isPurchased = _purchasedPlans.contains(plan['title']);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Icon(FontAwesomeIcons.dumbbell,
                            color: Color(0xFF1C2D5E)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan['title']!,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            if (plan['subtitle']!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  plan['subtitle']!,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              plan['price']!,
                              style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      isPurchased
                          ? const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Purchased',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold)),
                            )
                          : ElevatedButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    backgroundColor: const Color(0xFFF9F5FF),
                                    title: const Text('Confirm Purchase'),
                                    content: Text(
                                        'Are you sure you want to buy ${plan['title']} for ${plan['price']}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                        child: const Text('Cancel',
                                            style: TextStyle(
                                                color: Color(0xFF1C2D5E))),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF1C2D5E),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                        onPressed: () async {
                                          Navigator.of(ctx).pop();
                                          await _buyPlan(plan); // ✅ send full map
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        '${plan['title']} purchased successfully!')));
                                          }
                                        },
                                        child: const Text(
                                          'Confirm',
                                          style:
                                              TextStyle(color: Colors.white),
                                        ),
                                      )
                                    ],
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1C2D5E),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text(
                                'Buy',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                    ],
                  ),
                );
              },
            ),
    );
  }
}