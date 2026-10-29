import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/git_service.dart';
import '../app_toast.dart';

/// Mini-terminal embebida para visualizar comandos Git enviados, estados y respuestas.
class GitTerminalConsole extends StatefulWidget {
  final List<GitCommandLog> logs;
  final VoidCallback? onClear;
  final bool initialExpanded;
  final String title;

  const GitTerminalConsole({
    super.key,
    required this.logs,
    this.onClear,
    this.initialExpanded = true,
    this.title = 'Terminal Git — Registro de comandos',
  });

  @override
  State<GitTerminalConsole> createState() => _GitTerminalConsoleState();
}

class _GitTerminalConsoleState extends State<GitTerminalConsole> {
  late bool _expanded;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  void didUpdateWidget(covariant GitTerminalConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _copyAllLogs() {
    if (widget.logs.isEmpty) {
      AppToast.info('No hay registros en la terminal para copiar');
      return;
    }
    final buffer = StringBuffer();
    for (final log in widget.logs) {
      final time =
          '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
      if (log.description != null && log.description!.isNotEmpty) {
        buffer.writeln('[$time] # ${log.description}');
      }
      buffer.writeln('[$time] \$ ${log.command} (exitCode: ${log.exitCode})');
      if (log.stdout.isNotEmpty) {
        buffer.writeln(log.stdout);
      }
      if (log.stderr.isNotEmpty) {
        buffer.writeln(log.stderr);
      }
      buffer.writeln('--------------------------------------------------');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    AppToast.success('Historial de terminal copiado al portapapeles');
  }

  @override
  Widget build(BuildContext context) {
    const termBg = Color(0xFF0D1117);
    const headerBg = Color(0xFF161B22);
    const termBorder = Color(0xFF30363D);

    return Container(
      decoration: BoxDecoration(
        color: termBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: termBorder, width: 0.9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera de la terminal
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: headerBg,
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 15,
                  color: Color(0xFF58A6FF),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC9D1D9),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.logs.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B949E),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  tooltip: 'Copiar log de comandos',
                  color: const Color(0xFF8B949E),
                  hoverColor: Colors.white10,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: _copyAllLogs,
                ),
                if (widget.onClear != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    tooltip: 'Limpiar consola',
                    color: const Color(0xFF8B949E),
                    hoverColor: Colors.white10,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: widget.onClear,
                  ),
                IconButton(
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                  ),
                  tooltip: _expanded
                      ? 'Colapsar terminal'
                      : 'Expandir terminal',
                  color: const Color(0xFF8B949E),
                  hoverColor: Colors.white10,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),

          // Cuerpo de la terminal con scroll
          if (_expanded)
            Container(
              height: 140,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: termBg,
              child: widget.logs.isEmpty
                  ? const Center(
                      child: Text(
                        'En espera de comandos Git...',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas, monospace',
                          color: Color(0xFF8B949E),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: widget.logs.length,
                      itemBuilder: (context, index) {
                        final log = widget.logs[index];
                        final timeStr =
                            '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Descripción amigable del comando (si existe)
                              if (log.description != null &&
                                  log.description!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: SelectableText.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '[$timeStr] ',
                                          style: const TextStyle(
                                            color: Color(0xFF6E7681),
                                            fontSize: 10.5,
                                            fontFamily: 'Consolas, monospace',
                                          ),
                                        ),
                                        const TextSpan(
                                          text: '# ',
                                          style: TextStyle(
                                            color: Color(0xFFE3B341),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            fontFamily: 'Consolas, monospace',
                                          ),
                                        ),
                                        TextSpan(
                                          text: log.description!.trim(),
                                          style: const TextStyle(
                                            color: Color(0xFFE3B341),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                            fontFamily: 'Consolas, monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // Línea de comando
                              SelectableText.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '[$timeStr] ',
                                      style: const TextStyle(
                                        color: Color(0xFF6E7681),
                                        fontSize: 11,
                                        fontFamily: 'Consolas, monospace',
                                      ),
                                    ),
                                    const TextSpan(
                                      text: '\$ ',
                                      style: TextStyle(
                                        color: Color(0xFF58A6FF),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'Consolas, monospace',
                                      ),
                                    ),
                                    TextSpan(
                                      text: log.command,
                                      style: const TextStyle(
                                        color: Color(0xFFF0F6FC),
                                        fontSize: 11,
                                        fontFamily: 'Consolas, monospace',
                                      ),
                                    ),
                                    TextSpan(
                                      text: log.isSuccess ? ' ✓' : ' ✗',
                                      style: TextStyle(
                                        color: log.isSuccess
                                            ? const Color(0xFF3FB950)
                                            : const Color(0xFFF85149),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'Consolas, monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Salida Stdout
                              if (log.stdout.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    top: 2,
                                  ),
                                  child: SelectableText(
                                    log.stdout,
                                    style: const TextStyle(
                                      color: Color(0xFFC9D1D9),
                                      fontSize: 10.5,
                                      fontFamily: 'Consolas, monospace',
                                    ),
                                  ),
                                ),
                              // Salida Stderr
                              if (log.stderr.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    top: 2,
                                  ),
                                  child: SelectableText(
                                    log.stderr,
                                    style: TextStyle(
                                      color: log.isSuccess
                                          ? const Color(0xFFD29922)
                                          : const Color(0xFFF85149),
                                      fontSize: 10.5,
                                      fontFamily: 'Consolas, monospace',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
