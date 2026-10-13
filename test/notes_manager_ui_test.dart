import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:proc_dynamic_sirweb/models/note.dart';
import 'package:proc_dynamic_sirweb/widgets/notes/notes_manager_overlay.dart';
import 'package:proc_dynamic_sirweb/widgets/notes/share_note_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NotesBrowserDialog UI/UX components test', () {
    testWidgets(
      'Renders header with PRO HUB badge, sidebar navigation and search bar',
      (tester) async {
        // Configuramos ventana con tamaño de escritorio
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        bool closed = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: NotesBrowserDialog(close: ([_]) => closed = true),
            ),
          ),
        );

        // Esperar que construya el widget
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Header
        expect(find.text('Notas Adhesivas'), findsOneWidget);
        expect(find.text('PRO HUB'), findsOneWidget);

        // Sidebar & Toolbar buttons (puede existir en sidebar y toolbar)
        expect(find.text('Nueva nota'), findsAtLeastNWidgets(1));
        expect(find.text('Todas las notas'), findsOneWidget);
        expect(find.text('Mis notas'), findsOneWidget);
        expect(find.text('Compartidas'), findsOneWidget);
        expect(find.text('ETIQUETAS'), findsOneWidget);

        // Toolbar de búsqueda y ordenamiento
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Más recientes'), findsOneWidget);
        expect(find.byTooltip('Vista tarjetas'), findsOneWidget);
        expect(find.byTooltip('Vista lista'), findsOneWidget);
        expect(find.byTooltip('Importar Snippet como Nota'), findsOneWidget);
        expect(
          find.byTooltip('Exportar notas visibles (JSON)'),
          findsOneWidget,
        );

        // Paleta de colores en sidebar
        expect(find.text('COLORES'), findsOneWidget);

        // Botón cerrar
        final closeBtn = find.byTooltip('Cerrar (Esc)');
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'Sidebar behaves as an overlay drawer without displacing main content',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(body: NotesBrowserDialog(close: ([_]) {})),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Inicialmente el sidebar drawer está cerrado
        final toggleBtn = find.byTooltip('Abrir navegación y filtros (Ctrl+B)');
        expect(toggleBtn, findsOneWidget);

        // Abrir sidebar
        await tester.tap(toggleBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Debe verse el botón de cerrar drawer y el tooltip actualizado
        expect(find.byTooltip('Cerrar navegación (Ctrl+B)'), findsOneWidget);
        expect(find.text('NAVEGACIÓN'), findsOneWidget);

        // Cerrar con el botón chevron interno
        final closeChevron = find.byTooltip('Ocultar panel (Esc)');
        expect(closeChevron, findsOneWidget);
        await tester.tap(closeChevron);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Debe volver a estar cerrado
        expect(
          find.byTooltip('Abrir navegación y filtros (Ctrl+B)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Toggling view mode updates SharedPreferences preference', (
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
          theme: ThemeData.light(),
          home: Scaffold(body: NotesBrowserDialog(close: ([_]) {})),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Cambiar a vista lista
      final listBtn = find.byTooltip('Vista lista');
      expect(listBtn, findsOneWidget);
      await tester.tap(listBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notes_browser_view_mode'), 'list');

      // Volver a vista tarjetas
      final gridBtn = find.byTooltip('Vista tarjetas');
      expect(gridBtn, findsOneWidget);
      await tester.tap(gridBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(prefs.getString('notes_browser_view_mode'), 'grid');
    });

    testWidgets(
      'ShareNoteDialog renders professional layout with user input and close button',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        bool closed = false;
        final dummyNote = Note(
          id: 'test-123',
          title: 'Nota de Proyecto',
          content: 'Detalles de la nota',
          ownerUser: 'ADMIN',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(
              body: ShareNoteDialog(
                note: dummyNote,
                currentUser: 'ADMIN',
                close: ([_]) => closed = true,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Compartir nota'), findsOneWidget);
        expect(find.text('Nota de Proyecto'), findsOneWidget);
        expect(find.text('Accesos actuales'), findsOneWidget);
        expect(find.text('Invitar usuarios'), findsOneWidget);
        expect(find.text('Compartir accesos'), findsOneWidget);
        expect(find.text('Lectura'), findsWidgets);
        expect(find.text('Edición'), findsWidgets);

        // Togglear selector segmentado a Edición
        final edicionBtn = find.text('Edición').first;
        await tester.tap(edicionBtn);
        await tester.pump();

        final closeBtn = find.byTooltip('Cerrar (Esc)');
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        expect(closed, isTrue);
      },
    );

    test('NotesFilterScope and enum values are defined correctly', () {
      expect(NotesFilterScope.values.length, 3);
      expect(NotesSortOption.values.length, 3);
      expect(NotesViewMode.values.length, 2);
    });
  });
}
