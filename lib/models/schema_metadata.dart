import 'package:flutter/material.dart';

enum CompletionKind { table, view, column, procedure, function, package, keyword }

class ColumnInfo {
  final String name;
  final String dataType;
  const ColumnInfo({required this.name, required this.dataType});

  factory ColumnInfo.fromJson(Map<String, dynamic> json) => ColumnInfo(
        name: ((json['COLUMN_NAME'] ?? json['column_name']) as String? ?? '').toUpperCase(),
        dataType: (json['DATA_TYPE'] ?? json['data_type']) as String? ?? '',
      );
}

class ObjectInfo {
  final String name;
  final String type;
  const ObjectInfo({required this.name, required this.type});
}

class SchemaMetadata {
  final List<String> tables;
  final List<String> views;
  final List<ObjectInfo> objects;
  final Map<String, List<ColumnInfo>> cachedColumns;

  const SchemaMetadata({
    required this.tables,
    required this.views,
    required this.objects,
    this.cachedColumns = const {},
  });

  SchemaMetadata copyWithColumns(String table, List<ColumnInfo> cols) {
    final updated = Map<String, List<ColumnInfo>>.from(cachedColumns);
    updated[table.toUpperCase()] = cols;
    return SchemaMetadata(
      tables: tables,
      views: views,
      objects: objects,
      cachedColumns: updated,
    );
  }
}

class CompletionItem {
  final String label;
  final String detail;
  final CompletionKind kind;

  const CompletionItem({
    required this.label,
    required this.detail,
    required this.kind,
  });

  IconData get icon => switch (kind) {
        CompletionKind.table => Icons.table_chart,
        CompletionKind.view => Icons.table_rows,
        CompletionKind.column => Icons.view_column,
        CompletionKind.procedure => Icons.code,
        CompletionKind.function => Icons.functions,
        CompletionKind.package => Icons.folder_special,
        CompletionKind.keyword => Icons.text_fields,
      };

  Color get color => switch (kind) {
        CompletionKind.table => Colors.blue,
        CompletionKind.view => Colors.cyan,
        CompletionKind.column => Colors.green,
        CompletionKind.procedure => Colors.orange,
        CompletionKind.function => Colors.purple,
        CompletionKind.package => Colors.brown,
        CompletionKind.keyword => Colors.grey,
      };
}
