import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/deploy_ticket.dart';
import 'package:proc_dynamic_sirweb/services/deploy_ticket_exporter_service.dart';
import 'package:proc_dynamic_sirweb/services/git_repository_config_service.dart';
import 'package:proc_dynamic_sirweb/services/git_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GitService - Formato de Rama Hotfix', () {
    test(
      'formatHotfixBranchName limpia caracteres especiales y formatea yymmdd',
      () {
        final date = DateTime(2026, 10, 27);
        expect(
          GitService.formatHotfixBranchName(
            numeroSolicitud: 'INC-330701',
            date: date,
          ),
          equals('hf_INC330701_261027'),
        );

        expect(
          GitService.formatHotfixBranchName(
            numeroSolicitud: '12345/ABC',
            date: date,
          ),
          equals('hf_12345ABC_261027'),
        );
      },
    );

    test(
      'cleanRemoteErrorMessage traduce adecuadamente los errores de git ls-remote',
      () {
        expect(
          GitService.cleanRemoteErrorMessage('fatal: repository not found'),
          contains('El repositorio no existe'),
        );
        expect(
          GitService.cleanRemoteErrorMessage(
            'fatal: Authentication failed for ...',
          ),
          contains('Error de autenticación'),
        );
        expect(
          GitService.cleanRemoteErrorMessage(
            'fatal: could not read Username for ...',
          ),
          contains('Error de autenticación'),
        );
        expect(
          GitService.cleanRemoteErrorMessage(
            'fatal: Permission denied (publickey)',
          ),
          contains('Permiso denegado'),
        );
        expect(
          GitService.cleanRemoteErrorMessage(
            'fatal: unable to access \'https://foo\': Connection refused',
          ),
          contains('Conexión rechazada'),
        );
      },
    );

    test(
      'validateRemoteAccessToken valida inputs vacíos sin ejecutar proceso',
      () async {
        final res1 = await GitService.validateRemoteAccessToken(
          remoteUrl: '',
          personalAccessToken: 'token',
        );
        expect(res1.isValid, isFalse);
        expect(res1.message, contains('URL del repositorio'));

        final res2 = await GitService.validateRemoteAccessToken(
          remoteUrl: 'https://dev.azure.com/repo',
          personalAccessToken: '',
        );
        expect(res2.isValid, isFalse);
        expect(res2.message, contains('Personal Access Token'));
      },
    );
  });

  group('GitRepositoryConfigService', () {
    test('guarda y recupera rutas de configuración y autenticación', () async {
      SharedPreferences.setMockInitialValues({});
      final service = GitRepositoryConfigService();

      var config = await service.getConfig();
      expect(config.isConfigured, isFalse);
      expect(config.isPushReady, isFalse);

      await service.saveConfig(
        rutaRepositorio: 'https://dev.azure.com/org/proj/_git/repo',
        rutaDirectorioLocal: 'C:\\Git\\Sirweb',
        authType: GitAuthType.token,
        personalAccessToken: 'my_pat_secret',
      );

      config = await service.getConfig();
      expect(config.isConfigured, isTrue);
      expect(config.isPushReady, isTrue);
      expect(
        config.rutaRepositorio,
        'https://dev.azure.com/org/proj/_git/repo',
      );
      expect(config.rutaDirectorioLocal, 'C:\\Git\\Sirweb');
      expect(config.authType, GitAuthType.token);
      expect(config.personalAccessToken, 'my_pat_secret');

      await service.clearConfig();
      config = await service.getConfig();
      expect(config.isConfigured, isFalse);
      expect(config.isPushReady, isFalse);
    });
  });

  group('DeployTicketExporterService - exportarScriptsHotfix', () {
    test(
      'exporta scripts directos sin generar .xlsx ni paseambientescript',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('hotfix_test_');

        try {
          final ticket = DeployTicket(
            numeroSolicitud: '99999',
            tipoSolicitud: 'Hotfix',
            version: 1,
            sql: [
              DeployTicketScript(
                nombre: 'crear_columna',
                contenido: 'ALTER TABLE TEST ADD COL_A VARCHAR2(10);',
              ),
            ],
            bloqueLogico: [
              DeployTicketScript(
                nombre: 'actualizar_flag',
                contenido: 'UPDATE TEST SET COL_A = 1;',
              ),
            ],
          );

          final exporter = DeployTicketExporterService.instance;
          final exported = await exporter.exportarScriptsHotfix(
            ticket: ticket,
            targetDirectoryPath: tempDir.path,
          );

          expect(exported.length, equals(2));

          final fileNames = exported.map((f) => f.nombreArchivo).toList();
          expect(fileNames.any((n) => n.endsWith('.xlsx')), isFalse);
          expect(fileNames.any((n) => n.startsWith('pase_script_')), isFalse);
          expect(fileNames.any((n) => n.contains('crear_columna')), isTrue);
          expect(fileNames.any((n) => n.contains('actualizar_flag')), isTrue);

          // Comprobar que los archivos existen en disco
          for (final item in exported) {
            expect(File(item.rutaCompleta).existsSync(), isTrue);
          }
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    test('createAndCheckoutBranch y resolveDefaultBaseBranch', () async {
      final tempDir = await Directory.systemTemp.createTemp('git_test_');
      try {
        final git = GitService(workingDirectory: tempDir.path);
        await git.runGit(['init', '-b', 'master']);
        await git.runGit(['config', 'user.name', 'Tester']);
        await git.runGit(['config', 'user.email', 'tester@example.com']);

        // Crear commit inicial en master
        final dummyFile = File('${tempDir.path}/README.md');
        await dummyFile.writeAsString('# Test Repo');
        await git.add('README.md');
        await git.commit('initial commit');

        final baseBranch = await git.resolveDefaultBaseBranch();
        expect(baseBranch, equals('master'));

        // Crear rama hotfix desde master
        final branchRes = await git.createAndCheckoutBranch(
          'hf_test_1',
          startPoint: baseBranch,
        );
        expect(branchRes.isSuccess, isTrue);

        final current = await git.getCurrentBranch();
        expect(current, equals('hf_test_1'));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
