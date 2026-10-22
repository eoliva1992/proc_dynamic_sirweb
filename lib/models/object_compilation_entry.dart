/// Modelo para registrar el resultado de compilación de un objeto de esquema
/// (Oracle Package, Procedure, Function, Trigger, Type, View, etc.).
library;

enum ObjectCompilationStatus { running, success, error }

class ObjectCompilationEntry {
  final int id;
  final DateTime timestamp;
  final String objectName;
  final String objectType;
  final String? part; // 'SPEC', 'BODY', null
  final String ambiente;
  final ObjectCompilationStatus status;
  final int durationMs;
  final int errorCount;
  final int warningCount;
  final String? message;

  const ObjectCompilationEntry({
    required this.id,
    required this.timestamp,
    required this.objectName,
    required this.objectType,
    this.part,
    required this.ambiente,
    required this.status,
    required this.durationMs,
    this.errorCount = 0,
    this.warningCount = 0,
    this.message,
  });

  String get targetTitle => part != null
      ? '$objectType $objectName ($part)'
      : '$objectType $objectName';
}
