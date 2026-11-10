import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/widgets/constellation_background.dart';
import 'package:proc_dynamic_sirweb/widgets/plantillas/plantillas_browser_dialog.dart';

void main() {
  testWidgets('PlantillasBrowserDialog renders without crashing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlantillasBrowserDialog(close: ([_]) {})),
      ),
    );

    // Initial render
    expect(find.byType(PlantillasBrowserDialog), findsOneWidget);
    expect(find.byType(ConstellationHeader), findsOneWidget);
    expect(find.text('Plantillas de Código'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
