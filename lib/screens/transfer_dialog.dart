import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import '../widgets/ambiente_selector.dart';
import 'transfer_diff_page.dart';
import 'multi_transfer_dialog.dart';

/// Entry point: environment selector for transfer.
/// Pushes TransferDiffPage for single target, shows MultiTransferDialog for multiple.
class TransferDialog extends StatefulWidget {
  final Procedimiento sourceProc;
  final String sourceCode;
  final String sourceAmbiente;
  final String cdUsuario;
  // Called just before pushing the diff route — used to suspend the main editor
  final Future<void> Function()? onBeforePush;
  // Called after the diff route returns — used to resume the main editor
  final VoidCallback? onAfterReturn;

  const TransferDialog({
    super.key,
    required this.sourceProc,
    required this.sourceCode,
    required this.sourceAmbiente,
    required this.cdUsuario,
    this.onBeforePush,
    this.onAfterReturn,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final Set<String> _selected = {};

  List<String> get _targets => AmbienteSelector.ambientes
      .where((a) => a != widget.sourceAmbiente)
      .toList();

  Future<void> _continue() async {
    if (_selected.isEmpty || !mounted) return;
    // Capture all state before pop — context is deactivated once the dialog dismisses
    final nav = Navigator.of(context);
    final rootCtx = nav.context;
    final single = _selected.length == 1;
    final targetAmbiente = _selected.first;
    final targets = _selected.toList();
    nav.pop();
    // Let the pop animation settle before pushing the next route
    await Future<void>.delayed(Duration.zero);
    if (single) {
      await widget.onBeforePush?.call();
      await nav.push(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => TransferDiffPage(
            sourceProc: widget.sourceProc,
            sourceCode: widget.sourceCode,
            sourceAmbiente: widget.sourceAmbiente,
            targetAmbiente: targetAmbiente,
            cdUsuario: widget.cdUsuario,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      widget.onAfterReturn?.call();
    } else {
      await showDialog<void>(
        context: rootCtx,
        barrierDismissible: false,
        builder: (_) => MultiTransferDialog(
          sourceProc: widget.sourceProc,
          sourceCode: widget.sourceCode,
          sourceAmbiente: widget.sourceAmbiente,
          targetAmbientes: targets,
          cdUsuario: widget.cdUsuario,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isDark, cs),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transferir ${widget.sourceProc.cdProcedimiento}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seleccioná uno o más ambientes destino:',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            ..._targets.map((a) {
              final color = AmbienteSelector.colorForAmbiente(a);
              return CheckboxListTile(
                value: _selected.contains(a),
                dense: true,
                title: Text(
                  a,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                secondary: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(a);
                  } else {
                    _selected.remove(a);
                  }
                }),
              );
            }),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty ? null : _continue,
                    icon: const Icon(Icons.send, size: 14),
                    label: Text(
                      _selected.length > 1
                          ? 'Transferir (${_selected.length})'
                          : 'Continuar',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, ColorScheme cs) {
    final srcColor = AmbienteSelector.colorForAmbiente(widget.sourceAmbiente);
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
          const Text(
            'Transferir a ambiente',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: srcColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: srcColor, width: 0.8),
            ),
            child: Text(
              'Desde: ${widget.sourceAmbiente}',
              style: TextStyle(
                color: srcColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
