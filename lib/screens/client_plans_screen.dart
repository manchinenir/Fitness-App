// client_plans_screen.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
 
class ClientPlansScreen extends StatefulWidget {
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
 
  @override
  void initState() {
    super.initState();
    _loadPurchasedPlans();
  }
 
  Future<void> _loadPurchasedPlans() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _purchasedPlans = prefs.getStringList('purchasedPlans') ?? [];
    });
  }
 
  Future<void> _buyPlan(String title) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _purchasedPlans.add(title);
    });
    await prefs.setStringList('purchasedPlans', _purchasedPlans);
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
      body: ListView.separated(
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
              boxShadow: [
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
                  child: Icon(FontAwesomeIcons.dumbbell, color: Color(0xFF1C2D5E)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['title']!,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.w500),
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                isPurchased
                    ? const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Purchased', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      )
                    : ElevatedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              backgroundColor: const Color(0xFFF9F5FF),
                              title: const Text('Confirm Purchase'),
                              content: Text('Are you sure you want to buy ${plan['title']} for ${plan['price']}?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF1C2D5E))),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1C2D5E),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _buyPlan(plan['title']!);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${plan['title']} purchased successfully!')),
                                    );
                                  },
                                  child: const Text(
                                    'Confirm',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C2D5E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
 