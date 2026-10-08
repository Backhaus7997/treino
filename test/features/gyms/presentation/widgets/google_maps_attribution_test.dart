import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/presentation/widgets/google_maps_attribution.dart';

void main() {
  testWidgets('muestra la marca «Google Maps» tal cual', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GoogleMapsAttribution())),
    );
    expect(find.text('Google Maps'), findsOneWidget);
  });
}
