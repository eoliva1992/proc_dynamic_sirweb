import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/note.dart';
import 'package:proc_dynamic_sirweb/services/note_service.dart';
import 'package:proc_dynamic_sirweb/widgets/notes/note_editor_window.dart';
import 'package:proc_dynamic_sirweb/widgets/notes/notes_manager_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Note Copy Actions Test', () {
    testWidgets('NotesBrowserDialog mounts and initializes copy features', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NotesBrowserDialog(close: ([_]) {})),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verificamos que la interfaz principal de notas carga correctamente
      expect(find.text('Notas Adhesivas'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('NoteEditorWindow has copy button with multiple format options', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final note = Note(
        id: 'note-1',
        title: 'Prueba Copia',
        content: '# Subtitulo\nTexto para copiar',
        ownerUser: 'TEST_USER',
        tags: ['demo'],
      );
      final item = NoteListItem(note: note, accessLevel: NoteAccessLevel.owner);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () {
                    showNoteEditorWindow(ctx, item: item);
                  },
                  child: const Text('Abrir Editor'),
                );
              },
            ),
          ),
        ),
      );

      // Abrir editor
      await tester.tap(find.text('Abrir Editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verificar que el botón de copiar existe
      final copyBtn = find.byTooltip('Copiar nota (Markdown, Texto, JSON)');
      expect(copyBtn, findsOneWidget);

      // Presionar botón de copiar para desplegar opciones
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      // Debe mostrar las 3 opciones de copiado
      expect(find.text('Copiar como Markdown'), findsOneWidget);
      expect(find.text('Copiar como Texto plano'), findsOneWidget);
      expect(find.text('Copiar como JSON'), findsOneWidget);

      // Seleccionar Markdown sin advertencia de solapamiento en el test headless
      await tester.tap(find.text('Copiar como Markdown'), warnIfMissed: false);
      await tester.pumpAndSettle();
    });
  });
}
