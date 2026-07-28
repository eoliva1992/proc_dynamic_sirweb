import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/procedimientos_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/ambiente_selector.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/procedure_list.dart';
import '../widgets/code_editor_panel.dart';
import '../widgets/new_procedure_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    // Cargar configuraciones en background al iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcedimientosProvider>().cargarConfiguraciones();
    });
  }

  Future<void> _showNewProcedureDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewProcedureDialog(),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<ProcedimientosProvider>().mensaje ?? 'Creado correctamente',
          ),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showUsuarioDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.read<ProcedimientosProvider>();
    final ctrl = TextEditingController(text: provider.cdUsuario);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'usuario',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Cabecera con gradiente ──────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0078D4), Color(0xFF005A9E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Identificación',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ingresá tu código de usuario',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Cuerpo ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: TextStyle(
                        color: isDark ? const Color(0xFFD4D4D4) : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Ej: EOLIVA',
                        hintStyle: TextStyle(
                          color: isDark ? const Color(0xFF555555) : Colors.black38,
                          fontWeight: FontWeight.normal,
                          letterSpacing: 0,
                        ),
                        prefixIcon: Icon(
                          Icons.badge_outlined,
                          size: 18,
                          color: isDark ? const Color(0xFF0078D4) : const Color(0xFF0078D4),
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFF5F7FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF3A3A3A)
                                : const Color(0xFFDDE2EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF0078D4),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onSubmitted: (v) {
                        provider.setCdUsuario(v.trim());
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ),

                  // ── Acciones ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF3A3A3A)
                                      : Colors.grey.shade300,
                                ),
                              ),
                            ),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF808080)
                                    : Colors.black45,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              provider.setCdUsuario(ctrl.text.trim());
                              Navigator.of(ctx).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0078D4),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_rounded, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Guardar',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProcedimientosProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: _buildAppBar(context, provider),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: provider.modo == ViewMode.busqueda
                ? const Column(
                    key: ValueKey('busqueda'),
                    children: [
                      SearchBarWidget(),
                      Expanded(child: ProcedureList()),
                    ],
                  )
                : _buildEditorView(provider),
          ),
        );
      },
    );
  }

  AppBar _buildAppBar(BuildContext context, ProcedimientosProvider provider) {
    return AppBar(
      titleSpacing: 16,
      title: const Text(
        'Procedimientos Dinámicos',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      actions: [
        AmbienteSelector(
          value: provider.ambiente,
          onChanged: provider.setAmbiente,
        ),
        const SizedBox(width: 12),
        _UsuarioButton(
          cdUsuario: provider.cdUsuario,
          onTap: () => _showUsuarioDialog(context),
        ),
        const SizedBox(width: 8),
        // Botón toggle de tema
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) => Tooltip(
            message: themeProvider.isDark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
            child: IconButton(
              onPressed: themeProvider.toggle,
              icon: Icon(
                themeProvider.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Nuevo procedimiento',
          child: IconButton(
            onPressed: () => _showNewProcedureDialog(context),
            icon: const Icon(Icons.add_circle_outline),
            color: const Color(0xFF0078D4),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEditorView(ProcedimientosProvider provider) {
    final proc = provider.procedimientoActual;
    if (proc == null) return const SizedBox.shrink(key: ValueKey('empty'));
    return CodeEditorPanel(
      key: ValueKey(proc.cdProcedimiento),
      procedimiento: proc,
    );
  }
}

class _UsuarioButton extends StatelessWidget {
  final String cdUsuario;
  final VoidCallback onTap;

  const _UsuarioButton({required this.cdUsuario, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Text(
              cdUsuario.isEmpty ? 'Usuario' : cdUsuario,
              style: TextStyle(
                color: cdUsuario.isEmpty ? Colors.white38 : Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 12, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}


