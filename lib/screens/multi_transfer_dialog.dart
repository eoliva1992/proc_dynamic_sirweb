import 'dart:async';
import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import '../services/backup_service.dart';
import '../services/transfer_service.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/app_toast.dart';

enum _Status { pending, backingUp, transferring, done, error }

class _AmbienteState {
  final String ambiente;
  _Status status = _Status.pending;
  String? message;
  _AmbienteState(this.ambiente);
}

class MultiTransferDialog extends StatefulWidget {
  final Procedimiento sourceProc;
  final String sourceCode;
  final String sourceAmbiente;
  final List<String> targetAmbientes;
  final String cdUsuario;

  const MultiTransferDialog({
    super.key,
    required this.sourceProc,
    required this.sourceCode,
    required this.sourceAmbiente,
    required this.targetAmbientes,
    required this.cdUsuario,
  });

  @override
  State<MultiTransferDialog> createState() => _MultiTransferDialogState();
}

class _MultiTransferDialogState extends State<MultiTransferDialog> {
  late final List<_AmbienteState> _states;
  bool _askingBackup = true;
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _states = widget.targetAmbientes.map(_AmbienteState.new).toList();
  }

  Future<void> _start({required bool withBackup}) async {
    setState(() {
      _askingBackup = false;
      _running = true;
    });

    for (final state in _states) {
      if (withBackup) {
        if (!mounted) return;
        setState(() => state.status = _Status.backingUp);
        await _tryBackup(state.ambiente);
      }

      if (!mounted) return;
      setState(() => state.status = _Status.transferring);
      final result = await TransferService.transfer(
        cdProcedimiento: widget.sourceProc.cdProcedimiento,
        sourceCode: widget.sourceCode,
        inConfiguracion: widget.sourceProc.inConfiguracion,
        cdUsuario: widget.cdUsuario,
        targetAmbiente: state.ambiente,
      );
      if (!mounted) return;
      setState(() {
        state.status = result.success ? _Status.done : _Status.error;
        state.message = result.message;
      });
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _done = true;
    });

    final errors = _states.where((s) => s.status == _Status.error).length;
    if (errors == 0) {
      AppToast.success(
        'Transferencia completada a ${_states.length} ambiente(s)',
      );
    } else {
      AppToast.warning(
        '$errors error(es) durante la transferencia — revisá los detalles',
      );
    }
  }

  Future<void> _tryBackup(String targetAmbiente) async {
    // Delegate to BackupService which generates the proper Oracle SQL script
    await BackupService.exportar(
      widget.sourceProc,
      targetAmbiente,
      widget.cdUsuario,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isDark, cs),
            if (_askingBackup) _buildBackupQuestion(cs) else _buildProgress(cs),
            _buildFooter(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          const Icon(Icons.send_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Transferencia múltiple',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${widget.sourceProc.cdProcedimiento} · ${widget.sourceAmbiente} → ${widget.targetAmbientes.join(', ')}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupQuestion(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Desea hacer backup de los procedimientos actuales en los ambientes destino antes de transferir?',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Se abrirá un selector de archivo por cada ambiente que tenga el procedimiento.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _start(withBackup: false),
                icon: const Icon(Icons.skip_next, size: 14),
                label: const Text(
                  'No, omitir backup',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _start(withBackup: true),
                icon: const Icon(Icons.save_alt, size: 14),
                label: const Text(
                  'Sí, hacer backup primero',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(children: _states.map((s) => _buildRow(s, cs)).toList()),
    );
  }

  Widget _buildRow(_AmbienteState s, ColorScheme cs) {
    final color = AmbienteSelector.colorForAmbiente(s.ambiente);
    Widget icon;
    String label;
    switch (s.status) {
      case _Status.pending:
        icon = Icon(
          Icons.circle_outlined,
          size: 16,
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
        );
        label = 'Pendiente';
      case _Status.backingUp:
        icon = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.amber,
          ),
        );
        label = 'Guardando backup…';
      case _Status.transferring:
        icon = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        );
        label = 'Transfiriendo…';
      case _Status.done:
        icon = const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Colors.green,
        );
        label = s.message ?? 'Completado';
      case _Status.error:
        icon = const Icon(Icons.error_rounded, size: 16, color: Colors.red);
        label = s.message ?? 'Error';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Text(
            s.ambiente,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_done)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            )
          else if (!_running)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
        ],
      ),
    );
  }
}
