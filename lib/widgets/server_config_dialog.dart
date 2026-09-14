import 'package:flutter/material.dart';
import '../services/server_config_service.dart';

/// Widget dialogo para cambiar la dirección base del servidor
class ServerConfigDialog extends StatefulWidget {
  final VoidCallback? onServerConfigChanged;

  const ServerConfigDialog({
    Key? key,
    this.onServerConfigChanged,
  }) : super(key: key);

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late TextEditingController _urlController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _loadCurrentUrl();
  }

  Future<void> _loadCurrentUrl() async {
    final currentUrl = await ServerConfigService().getBaseUrl();
    if (mounted) {
      _urlController.text = currentUrl;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final newUrl = _urlController.text.trim();
      await ServerConfigService().setBaseUrl(newUrl);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _successMessage = 'Servidor guardado correctamente';
        });

        // Notificar al callback si existe
        widget.onServerConfigChanged?.call();

        // Cerrar después de 1.5 segundos
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar configuración'),
        content: Text(
          '¿Deseas reiniciar la dirección del servidor a su valor por defecto?\n\n'
          'Valor por defecto: ${ServerConfigService.getDefault()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _successMessage = null;
      });

      try {
        await ServerConfigService().resetToDefault();
        if (mounted) {
          _urlController.text = ServerConfigService.getDefault();
          setState(() {
            _isLoading = false;
            _successMessage = 'Configuración reiniciada al valor por defecto';
          });

          widget.onServerConfigChanged?.call();

          // Cerrar después de 1.5 segundos
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configurar Servidor'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dirección base del servidor:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  hintText: 'ej: http://localhost:5179',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  prefixIcon: const Icon(Icons.language),
                  errorText: _errorMessage,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'La URL no puede estar vacía';
                  }
                  if (!value.startsWith('http://') && !value.startsWith('https://')) {
                    return 'La URL debe comenzar con http:// o https://';
                  }
                  try {
                    Uri.parse(value);
                  } catch (_) {
                    return 'URL inválida';
                  }
                  return null;
                },
                onFieldSubmitted: _isLoading ? null : (_) => _saveUrl(),
              ),
              if (_successMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Esto cambiará la dirección donde la aplicación busca el servidor.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Text(
                'Valor por defecto: ${ServerConfigService.getDefault()}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_isLoading || _successMessage != null)
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        TextButton(
          onPressed: (_isLoading || _successMessage != null) ? null : _resetToDefault,
          child: const Text('Por defecto'),
        ),
        ElevatedButton(
          onPressed: (_isLoading || _successMessage != null) ? null : _saveUrl,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}


