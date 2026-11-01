import 'package:flutter_test/flutter_test.dart';
import 'package:proc_dynamic_sirweb/models/table_metadata.dart';
import 'package:proc_dynamic_sirweb/services/server_config_service.dart';
import 'package:proc_dynamic_sirweb/services/table_metadata_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService().setBaseUrl('http://localhost:5000');
    TableMetadataService().invalidate();
  });

  group('TableMetadataService Tests', () {
    test('ConstraintType mapping from Oracle code', () {
      expect(ConstraintType.fromOracleCode('P'), ConstraintType.primaryKey);
      expect(ConstraintType.fromOracleCode('R'), ConstraintType.foreignKey);
      expect(ConstraintType.fromOracleCode('U'), ConstraintType.unique);
      expect(ConstraintType.fromOracleCode('C'), ConstraintType.check);
      expect(ConstraintType.fromOracleCode('X'), ConstraintType.other);
      expect(ConstraintType.primaryKey.shortCode, 'PK');
      expect(ConstraintType.foreignKey.shortCode, 'FK');
    });

    test('TableIndexInfo columnsFormatted handles ASC and DESC', () {
      const idx = TableIndexInfo(
        name: 'IDX_CLIENTES_01',
        uniqueness: 'UNIQUE',
        indexType: 'NORMAL',
        status: 'VALID',
        columns: [
          TableIndexColumnInfo(
            columnName: 'ID',
            columnPosition: 1,
            descend: 'ASC',
          ),
          TableIndexColumnInfo(
            columnName: 'FECHA',
            columnPosition: 2,
            descend: 'DESC',
          ),
        ],
      );

      expect(idx.isUnique, isTrue);
      expect(idx.isValid, isTrue);
      expect(idx.columnsFormatted, 'ID, FECHA DESC');
    });

    test('TableTriggerInfo status isEnabled check', () {
      const trig1 = TableTriggerInfo(
        name: 'TRG_BI_CLIENTE',
        triggerType: 'BEFORE EACH ROW',
        triggeringEvent: 'INSERT',
        status: 'ENABLED',
        owner: 'SYSTEM',
      );
      const trig2 = TableTriggerInfo(
        name: 'TRG_BU_CLIENTE',
        triggerType: 'BEFORE EACH ROW',
        triggeringEvent: 'UPDATE',
        status: 'DISABLED',
        owner: 'SYSTEM',
      );

      expect(trig1.isEnabled, isTrue);
      expect(trig2.isEnabled, isFalse);
    });

    test('TableConstraintInfo isEnabled check and FK reference metadata', () {
      const pk = TableConstraintInfo(
        name: 'PK_CLIENTES',
        type: ConstraintType.primaryKey,
        status: 'ENABLED',
        columns: ['ID_CLIENTE'],
      );
      const fk = TableConstraintInfo(
        name: 'FK_VENTAS_CLIENTE',
        type: ConstraintType.foreignKey,
        status: 'DISABLED',
        columns: ['ID_CLIENTE'],
        rTableName: 'CLIENTES',
        rConstraintName: 'PK_CLIENTES',
      );

      expect(pk.isEnabled, isTrue);
      expect(fk.isEnabled, isFalse);
      expect(fk.rTableName, 'CLIENTES');
      expect(fk.rConstraintName, 'PK_CLIENTES');
    });
  });
}
