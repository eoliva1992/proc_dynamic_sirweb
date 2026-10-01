import 'bulk_backup_item.dart';

enum BatchTransferStatus { pending, running, success, error }

/// Resultado de transferir [item] a [targetAmbiente]. Una misma selección
/// genera un resultado por cada combinación elemento×destino.
class BatchTransferResult {
  final BulkBackupItem item;
  final String targetAmbiente;
  final BatchTransferStatus status;
  final String? message;

  const BatchTransferResult({
    required this.item,
    required this.targetAmbiente,
    this.status = BatchTransferStatus.pending,
    this.message,
  });

  BatchTransferResult copyWith({
    BatchTransferStatus? status,
    String? message,
  }) => BatchTransferResult(
    item: item,
    targetAmbiente: targetAmbiente,
    status: status ?? this.status,
    message: message ?? this.message,
  );

  bool get isPending => status == BatchTransferStatus.pending;
  bool get isRunning => status == BatchTransferStatus.running;
  bool get isSuccess => status == BatchTransferStatus.success;
  bool get isError => status == BatchTransferStatus.error;

  /// Identifica el par elemento+destino para actualizar el resultado in-place.
  String get key => '${item.id}|$targetAmbiente';
}
