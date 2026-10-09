import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Registra la app en el menú "Abrir con" de Windows para .sql/.txt.
///
/// Escribe únicamente en `HKEY_CURRENT_USER` (sin instalador, sin permisos de
/// administrador) y solo agrega la app a `OpenWithList` — nunca toca el valor
/// por defecto de `.sql`/`.txt`, para no reemplazar la app predeterminada
/// (p. ej. Notepad para `.txt`).
abstract final class FileAssociationService {
  static const _prefsKey = 'file_assoc_registered_v2';
  static const _appExeName = 'proc_dynamic_sirweb.exe';
  static const _friendlyName = 'Proc Dynamic SIRWeb';

  static Future<void> registerOpenWithIfNeeded() async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) == true) return;

    final exePath = Platform.resolvedExecutable;
    final commands = [
      [
        'add',
        r'HKCU\Software\Classes\Applications\' + _appExeName + r'\shell\open\command',
        '/ve',
        '/d',
        '"$exePath" "%1"',
        '/f',
      ],
      [
        'add',
        r'HKCU\Software\Classes\Applications\' + _appExeName,
        '/v',
        'FriendlyAppName',
        '/d',
        _friendlyName,
        '/f',
      ],
      [
        'add',
        r'HKCU\Software\Classes\.sql\OpenWithList\' + _appExeName,
        '/f',
      ],
      [
        'add',
        r'HKCU\Software\Classes\.txt\OpenWithList\' + _appExeName,
        '/f',
      ],
      [
        'add',
        r'HKCU\Software\Classes\.yaml\OpenWithList\' + _appExeName,
        '/f',
      ],
      [
        'add',
        r'HKCU\Software\Classes\.yml\OpenWithList\' + _appExeName,
        '/f',
      ],
    ];

    try {
      var allOk = true;
      for (final args in commands) {
        final result = await Process.run('reg', args);
        if (result.exitCode != 0) {
          allOk = false;
          debugPrint('[FileAssociationService] reg ${args.join(' ')} -> ${result.stderr}');
        }
      }
      if (allOk) await prefs.setBool(_prefsKey, true);
    } catch (e) {
      debugPrint('[FileAssociationService] No se pudo registrar la asociación: $e');
    }
  }
}
