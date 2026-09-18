import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proc_dynamic_sirweb/models/bulk_backup_item.dart';
import 'package:proc_dynamic_sirweb/services/bulk_backup_selection_service.dart';

void main() {
  test('persists favorites for multiple selected objects', () async {
    SharedPreferences.setMockInitialValues({});
    final service = BulkBackupSelectionService();
    const items = [
      BulkBackupItem(
        name: 'T1',
        type: 'TABLE',
        owner: 'APP',
        source: BulkBackupSource.schema,
      ),
      BulkBackupItem(
        name: 'P1',
        type: 'PROCEDURE',
        owner: 'APP',
        source: BulkBackupSource.schema,
      ),
    ];

    await service.setFavoriteItems(items, favorite: true);
    expect(await service.getFavoriteIds(), {items[0].id, items[1].id});

    await service.setFavoriteItems([items[0]], favorite: false);
    expect(await service.getFavoriteIds(), {items[1].id});
  });

  test('round trip preserves references and configuration', () {
    final list = BulkBackupSelectionList(
      name: 'Críticos',
      savedAt: DateTime.utc(2026, 9, 17),
      savedFromAmbiente: 'QA',
      config: const BulkBackupConfig(
        includeSpec: false,
        includeBody: false,
        includeTableComments: true,
        includeGrants: true,
        includeSynonyms: true,
      ),
      items: const [
        BulkBackupItem(
          name: 'T1',
          type: 'TABLE',
          owner: 'APP',
          source: BulkBackupSource.schema,
        ),
        BulkBackupItem(
          name: 'P1',
          type: 'PROCEDURE_DYNAMIC',
          source: BulkBackupSource.dynamicProcedure,
        ),
      ],
    );

    final decoded = BulkBackupSelectionService.decode(
      BulkBackupSelectionService.encode(list),
    );
    expect(decoded.name, 'Críticos');
    expect(decoded.savedFromAmbiente, 'QA');
    expect(decoded.items.map((item) => item.id), [
      'schema|TABLE|T1',
      'dynamicProcedure|PROCEDURE_DYNAMIC|P1',
    ]);
    expect(decoded.config.includeSpec, isFalse);
    expect(decoded.config.includeGrants, isTrue);
    expect(decoded.config.includeSynonyms, isTrue);
  });

  test('deduplicates references while preserving the first item', () {
    final list = BulkBackupSelectionList(
      name: 'Duplicados',
      savedAt: DateTime.now(),
      savedFromAmbiente: 'Desa',
      config: const BulkBackupConfig(),
      items: const [
        BulkBackupItem(
          name: 'T1',
          type: 'table',
          owner: 'OLD',
          source: BulkBackupSource.schema,
        ),
        BulkBackupItem(
          name: 't1',
          type: 'TABLE',
          owner: 'NEW',
          source: BulkBackupSource.schema,
        ),
      ],
    );
    expect(list.items, hasLength(1));
    expect(list.items.single.owner, 'OLD');
  });

  test('rejects unknown format and version', () {
    expect(
      () => BulkBackupSelectionService.decode('{"format":"other","version":1}'),
      throwsFormatException,
    );
    expect(
      () => BulkBackupSelectionService.decode(
        '{"format":"bulk-backup-selection","version":99}',
      ),
      throwsFormatException,
    );
  });
}
