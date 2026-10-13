import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/note.dart';
import 'package:proc_dynamic_sirweb/providers/procedimientos_provider.dart';
import 'package:proc_dynamic_sirweb/services/note_service.dart';
import 'package:proc_dynamic_sirweb/services/notification_service.dart';
import 'package:proc_dynamic_sirweb/services/snippet_service.dart';

void main() {
  group('Note Serialization & Validation Safeguards', () {
    test(
      'toCreateJson sends non-empty whitespace fallback if content is empty',
      () {
        final note = Note(
          id: '',
          title: 'Mi Nota',
          content: '',
          ownerUser: 'EOLIVA',
        );
        final json = note.toCreateJson();
        expect(json['title'], 'Mi Nota');
        expect(json['content'], ' ');
        expect(json['tags'], isNull);
      },
    );

    test(
      'toUpdateJson sends non-empty whitespace fallback if content is whitespace',
      () {
        final note = Note(
          id: '123',
          title: 'Mi Nota',
          content: '   \n\t  ',
          ownerUser: 'EOLIVA',
          version: 2,
        );
        final json = note.toUpdateJson(requestingUser: 'EOLIVA');
        expect(json['title'], 'Mi Nota');
        expect(json['content'], ' ');
        expect(json['requestingUser'], 'EOLIVA');
        expect(json['version'], 2);
      },
    );
  });

  group('NoteService reset and synchronization on user switch', () {
    test(
      'resetForUser updates currentUser and closes registered callbacks',
      () {
        var closedA = false;
        var closedB = false;

        void closerA() => closedA = true;
        void closerB() => closedB = true;

        NoteService.registerCloser(closerA);
        NoteService.registerCloser(closerB);

        NoteService.resetForUser('NUEVO_USUARIO');

        expect(NoteService.currentUser, 'NUEVO_USUARIO');
        expect(closedA, isTrue);
        expect(closedB, isTrue);

        // Subsequent reset should have cleared the list of closers
        closedA = false;
        NoteService.resetForUser('OTRO_USUARIO');
        expect(closedA, isFalse);
      },
    );

    test(
      'procedimientosProvider.setCdUsuario triggers NoteService, SnippetService and NotificationService reset',
      () {
        procedimientosProvider.setCdUsuario('USER_TEST_123');

        expect(NoteService.currentUser, 'USER_TEST_123');
        expect(SnippetService.currentUser, 'USER_TEST_123');
        expect(NotificationService.instance.currentUser, 'USER_TEST_123');
      },
    );
  });
}
