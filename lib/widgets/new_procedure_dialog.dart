import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import '../providers/procedimientos_provider.dart';
import 'config_badge.dart';

class NewProcedureDialog extends StatefulWidget {
  const NewProcedureDialog({super.key});

  @override
  State<NewProcedureDialog> createState() => _NewProcedureDialogState();
}

class _NewProcedureDialogState extends State<NewProcedureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  String _selectedConfig = 'D';
  late TextEditingController _codeCtrl;

  static const _configs = [
    'D',
    'J',
    'A',
    'G',
    'S',
    'C',
    'F',
    'T',
    'V',
    'O',
    'I',
  ];

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(
      text:
          'BEGIN\n  DECLARE\n    W_STAT VARCHAR2(5) := \'0\';\n  BEGIN\n    -- Tu código aquí\n    NULL;\n  EXCEPTION\n    WHEN OTHERS THEN\n      :P_ERROR := \'NOMBRE_PROC EN \' || W_STAT || \' ** \' || SQLERRM;\n  END;\nEND;',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cdUsuario = procedimientosProvider.cdUsuario;
      if (cdUsuario.isNotEmpty) _usuarioCtrl.text = cdUsuario;
    });
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _usuarioCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onConfigChanged(String newConfig) {
    setState(() {
      _selectedConfig = newConfig;
    });
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = procedimientosProvider;
    final ok = await provider.crear(
      cdProcedimiento: _codigoCtrl.text.trim().toUpperCase(),
      deTexto: _codeCtrl.text,
      inConfiguracion: _selectedConfig,
      cdUsuario: _usuarioCtrl.text.trim(),
    );

    if (ok && mounted) {
      provider.setCdUsuario(_usuarioCtrl.text.trim());
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 900,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            _buildDialogHeader(),
            Expanded(child: _buildBody()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Text(
            'Nuevo Procedimiento Dinámico',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              size: 18,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(child: _buildCodigoField()),
                const SizedBox(width: 12),
                _buildConfigDropdown(),
                const SizedBox(width: 12),
                Expanded(child: _buildUsuarioField()),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 13, fontFamily: 'Consolas'),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodigoField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _codigoCtrl,
      style: TextStyle(
        color: colorScheme.onSurface,
        fontFamily: 'Consolas',
        fontSize: 13,
      ),
      decoration: _inputDecoration('Código del procedimiento *', Icons.code),
      textCapitalization: TextCapitalization.characters,
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Requerido';
        if (v.trim().length > 30) return 'Máximo 30 caracteres';
        return null;
      },
    );
  }

  Widget _buildUsuarioField() {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: _usuarioCtrl,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
      decoration: _inputDecoration('Usuario *', Icons.person_outline),
      textCapitalization: TextCapitalization.characters,
      validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
    );
  }

  Widget _buildConfigDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    final configs = procedimientosProvider.configuraciones;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedConfig,
          isDense: true,
          dropdownColor: colorScheme.surface,
          icon: Icon(
            Icons.arrow_drop_down,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
            size: 18,
          ),
          items: configs.isEmpty
              // Fallback a lista estática si no cargaron aún
              ? _configs
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: ConfigBadge(config: c, small: false),
                      ),
                    )
                    .toList()
              : configs
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.cdModulo,
                        child: Row(
                          children: [
                            ConfigBadge(config: c.cdModulo, small: true),
                            const SizedBox(width: 8),
                            Text(
                              c.deArgumento,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          onChanged: (v) => v != null ? _onConfigChanged(v) : null,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: colorScheme.onSurface.withValues(alpha: 0.5),
        fontSize: 12,
      ),
      prefixIcon: Icon(
        icon,
        size: 16,
        color: colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      filled: true,
      fillColor: colorScheme.onSurface.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Observer(
      builder: (context) {
        final provider = procedimientosProvider;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (provider.error != null)
                Expanded(
                  child: Text(
                    provider.error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: provider.cargando ? null : _crear,
                icon: provider.cargando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add, size: 16),
                label: const Text('Crear Procedimiento'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
