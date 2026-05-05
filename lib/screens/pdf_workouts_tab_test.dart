// dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform/platform.dart';

import 'package:flex_facility_app/screens/pdf_workouts_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDFWorkoutsTab widget tests', () {
    testWidgets('shows loading indicator on first frame', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: PDFWorkoutsTab()));

      // initial state shows loading spinner and label
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading PDF workouts...'), findsOneWidget);
    });
  });

  group('SubscriptionPaymentPage widget tests', () {
    final samplePlan = {
      'docId': 'pdf_subscription_monthly',
      'name': 'PDF Workouts Monthly Subscription',
      'category': 'PDF Access',
      'sessions': 1,
      'price': 9.99,
      'description': 'Unlimited access to all PDF workouts for 30 days',
      'type': 'subscription',
    };

    testWidgets('renders subscription summary and payment options', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionPaymentPage(
            plan: samplePlan,
            squareApplicationId: 'test-app-id',
            squareLocationId: 'test-location-id',
          ),
        ),
      );

      // allow first frame to build
      await tester.pumpAndSettle();

      // AppBar title
      expect(find.text('Subscription Payment'), findsOneWidget);

      // Plan name and description
      expect(find.text(samplePlan['name'] as String), findsOneWidget);
      expect(find.textContaining('Unlimited access'), findsOneWidget);

      // Price text / summary
      expect(find.text('\$${(samplePlan['price'] as double).toStringAsFixed(2)}/month'), findsOneWidget);

      // Payment method card
      expect(find.text('Credit/Debit Card'), findsOneWidget);
      expect(find.text('Secure payment via Square (opens in browser)'), findsOneWidget);

      // Primary subscribe button with formatted text
      final subscribeText = 'Subscribe \$${(samplePlan['price'] as double).toStringAsFixed(2)}/month';
      expect(find.widgetWithText(ElevatedButton, subscribeText), findsOneWidget);

      // Apple Pay presence depends on platform; on typical test environments (Linux/Mac CI) Platform.isIOS is false.
      // Ensure that if not iOS, Apple Pay tile does not appear.
      final localPlatform = LocalPlatform();
      if (!localPlatform.isIOS) {
        expect(find.text('Apple Pay'), findsNothing);
      }
    });
  });
}