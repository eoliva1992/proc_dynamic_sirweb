import 'procedimiento.dart';

enum BulkBackupSource { schema, dynamicProcedure }

class BulkBackupItem {
  final String name;
  final String type;
  final String owner;
  final BulkBackupSource source;
  final Procedimiento? procedimiento;

  const BulkBackupItem({
    required this.name,
    required this.type,
    this.owner = '',
    required this.source,
    this.procedimiento,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'owner': owner,
    'source': source.name,
  };

  factory BulkBackupItem.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final type = json['type'];
    final sourceName = json['source'];
    if (name is! String ||
        name.trim().isEmpty ||
        type is! String ||
        type.trim().isEmpty ||
        sourceName is! String) {
      throw const FormatException('Referencia de backup inválida');
    }
    final source = BulkBackupSource.values
        .where((value) => value.name == sourceName)
        .firstOrNull;
    if (source == null) {
      throw FormatException('Origen de backup desconocido: $sourceName');
    }
    final owner = json['owner'];
    if (owner != null && owner is! String) {
      throw const FormatException('Owner de backup inválido');
    }
    return BulkBackupItem(
      name: name,
      type: type,
      owner: owner as String? ?? '',
      source: source,
    );
  }

  String get category {
    if (source == BulkBackupSource.dynamicProcedure) {
      return 'procedure-dynamic';
    }
    return switch (type.toUpperCase()) {
      'PROCEDURE' => 'procedures',
      'FUNCTION' => 'functions',
      'PACKAGE' => 'packages',
      'TYPE' => 'types',
      'TABLE' => 'tables',
      'VIEW' => 'views',
      _ => type.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
    };
  }

  String get id => '${source.name}|${type.toUpperCase()}|${name.toUpperCase()}';

  @override
  bool operator ==(Object other) => other is BulkBackupItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class BulkBackupConfig {
  final bool includeSpec;
  final bool includeBody;
  final bool includeTableComments;
  final bool includeGrants;
  final bool includeSynonyms;

  const BulkBackupConfig({
    this.includeSpec = true,
    this.includeBody = true,
    this.includeTableComments = true,
    this.includeGrants = false,
    this.includeSynonyms = false,
  });

  Map<String, dynamic> toJson() => {
    'includeSpec': includeSpec,
    'includeBody': includeBody,
    'includeTableComments': includeTableComments,
    'includeGrants': includeGrants,
    'includeSynonyms': includeSynonyms,
  };

  factory BulkBackupConfig.fromJson(Map<String, dynamic> json) {
    bool read(String key, bool fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! bool) throw FormatException('Configuración inválida: $key');
      return value;
    }

    return BulkBackupConfig(
      includeSpec: read('includeSpec', true),
      includeBody: read('includeBody', true),
      includeTableComments: read('includeTableComments', true),
      includeGrants: read('includeGrants', false),
      includeSynonyms: read('includeSynonyms', false),
    );
  }
}
