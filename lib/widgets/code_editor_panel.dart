import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import 'config_badge.dart';
import '_editor_js_engine.dart';
import 'monaco_editor_widget.dart';

part '_editor_config_widgets.dart';
part '_editor_plsql_checker.dart';

// ── Widget público ─────────────────────────────────────────────────────────────
class CodeEditorPanel extends StatefulWidget {
  final Procedimiento procedimiento;

  const CodeEditorPanel({super.key, required this.procedimiento});

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

// ── Estado ─────────────────────────────────────────────────────────────────────
class _CodeEditorPanelState extends State<CodeEditorPanel> {
  late String _selectedConfig;
  String _currentCode = '';

  final MonacoController _monaco = MonacoController();

  // Errores de sintaxis (checker Dart → squiggles en Monaco + panel inferior)
  final _errors = ValueNotifier<List<_SyntaxError>>([]);
  List<_SyntaxError> get _syntaxErrors => _errors.value;

  Timer? _debounce;

  // ── Ciclo de vida ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.procedimiento.inConfiguracion;
    _currentCode = widget.procedimiento.deTexto;
    // Carga el bundle ANTLR4; cuando termine vuelve a correr el check.
    initPlSqlEngine().then((_) {
      if (mounted) _runCheck();
    });
    _runCheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _errors.dispose();
    _monaco.dispose();
    super.dispose();
  }

  // ── Checker ──────────────────────────────────────────────────────────────────

  void _onCodeChanged(String code) {
    _currentCode = code;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _runCheck);
  }

  void _runCheck() {
    if (!mounted) return;
    final errs = _SyntaxChecker.check(
      _currentCode,
      isJs: _selectedConfig == 'J',
    );
    _errors.value = errs;
    _monaco.setErrors(
      errs
          .map((e) => MonacoError(line: e.line, col: e.col, message: e.message))
          .toList(),
    );
    setState(() {});
  }

  void _onConfigChanged(String cfg) {
    setState(() => _selectedConfig = cfg);
    _monaco.setLanguage(cfg == 'J' ? 'javascript' : 'plsql');
    _runCheck();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<ProcedimientosProvider>(
      builder: (context, provider, _) {
        if (provider.cargandoEditor) {
          return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        return Column(
          children: [
            _buildHeader(context, provider),
            Expanded(
              child: MonacoEditorWidget(
                controller: _monaco,
                initialCode: _currentCode,
                language: _selectedConfig == 'J' ? 'javascript' : 'plsql',
                darkTheme: Theme.of(context).brightness == Brightness.dark,
                onChanged: _onCodeChanged,
              ),
            ),
            if (_syntaxErrors.isNotEmpty) _buildErrorPanel(context),
          ],
        );
      },
    );
  }

  // ── Header (título + config + guardar + variables) ────────────────────────────

  Widget _buildHeader(BuildContext context, ProcedimientosProvider provider) {
    final proc = widget.procedimiento;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);

    return Container(
      height: 40,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Nombre del procedimiento
          Expanded(
            child: Text(
              proc.cdProcedimiento,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Selector de configuración (PL/SQL / JS / etc.)
          _ConfigSelector(
            value: _selectedConfig,
            onChanged: _onConfigChanged,
            isNuevo: proc.version == 0,
          ),
          const SizedBox(width: 8),

          // Variables dinámicas
          IconButton(
            icon: const Icon(Icons.data_object, size: 18),
            tooltip: 'Variables dinámicas',
            onPressed: _showVariablesModal,
          ),

          // Guardar
          if (provider.cargando)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined, size: 18),
              tooltip: 'Guardar (Ctrl+S)',
              onPressed: () => provider.guardar(
                deTexto: _currentCode,
                inConfiguracion: _selectedConfig,
              ),
            ),

          // Indicador de errores
          if (_syntaxErrors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: '${_syntaxErrors.length} error(es) de sintaxis',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFFF6B6B),
                      size: 16,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${_syntaxErrors.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF6B6B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Variables dinámicas ──────────────────────────────────────────────────────

  void _showVariablesModal() {
    final provider = context.read<ProcedimientosProvider>();
    final vars = provider.variablesDinamicas
        .where((v) => v.inConfiguracion == _selectedConfig)
        .toList();
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Variables dinámicas',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                if (vars.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No hay variables para esta configuración.'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: vars.length,
                      itemBuilder: (_, i) {
                        final v = vars[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            ':${v.cdVariable}',
                            style: const TextStyle(fontFamily: 'Consolas'),
                          ),
                          subtitle: Text(v.deVariable ?? ''),
                          onTap: () {
                            Navigator.pop(ctx);
                            _monaco.insertTextAtCursor(':${v.cdVariable}');
                          },
                        );
                      },
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Panel inferior de errores ────────────────────────────────────────────────

  Widget _buildErrorPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);

    return Container(
      constraints: const BoxConstraints(maxHeight: 130),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFF6B6B),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_syntaxErrors.length} error${_syntaxErrors.length == 1 ? '' : 'es'} de sintaxis',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFF6B6B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              itemCount: _syntaxErrors.length,
              itemBuilder: (ctx, i) {
                final e = _syntaxErrors[i];
                return InkWell(
                  onTap: () => _monaco.revealLine(e.line),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Línea ${e.line}:${e.col}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'Consolas',
                            color: Color(0xFFFF6B6B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.message,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
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

// ── Modelo de error de sintaxis ────────────────────────────────────────────────

class _SyntaxError {
  final int line;
  final int col;
  final String message;
  const _SyntaxError({
    required this.line,
    required this.col,
    required this.message,
  });
}

// ── Checker de sintaxis ────────────────────────────────────────────────────────

class _SyntaxChecker {
  static List<_SyntaxError> check(String code, {required bool isJs}) =>
      isJs ? _checkJs(code) : _checkSql(code);

  // ── PL/SQL ──────────────────────────────────────────────────────────────────
  // Usa el bundle ANTLR4 si está disponible; fallback al parser Dart.

  static List<_SyntaxError> _checkSql(String code) {
    final engineResult = evalPlSqlSyntax(code);
    if (engineResult == null) return _checkSqlManual(code);
    if (engineResult == '[]' || engineResult.isEmpty) return [];
    try {
      final list = jsonDecode(engineResult) as List<dynamic>;
      if (list.isEmpty) return [];
      final lineCount = code.split('\n').length;
      return list.map((e) {
        final map = e as Map<String, dynamic>;
        final line = (map['line'] as num?)?.toInt() ?? 1;
        final col = (map['col'] as num?)?.toInt() ?? 1;
        final msg = map['msg'] as String? ?? 'Error PL/SQL';
        return _SyntaxError(
          line: line.clamp(1, lineCount),
          col: col.clamp(1, 10000),
          message: msg,
        );
      }).toList();
    } catch (_) {
      return _checkSqlManual(code);
    }
  }

  static List<_SyntaxError> _checkSqlManual(String code) {
    final lex = _PlSqlLexer(code);
    final (:tokens, :errors) = lex.tokenize();
    return _PlSqlParser(tokens, errors).validate();
  }

  // ── JavaScript ──────────────────────────────────────────────────────────────
  // Usa el motor QuickJS embebido si está disponible; fallback manual.

  static List<_SyntaxError> _checkJs(String code) {
    final engineResult = evalJsSyntax(code);
    if (engineResult == null) return _checkJsManual(code);
    if (engineResult.isEmpty) return [];
    try {
      final map = jsonDecode(engineResult) as Map<String, dynamic>;
      final lineCount = code.split('\n').length;
      final line = (map['line'] as num?)?.toInt() ?? 1;
      final col = (map['col'] as num?)?.toInt() ?? 1;
      final msg = map['msg'] as String? ?? 'Error de sintaxis JS';
      return [
        _SyntaxError(
          line: line.clamp(1, lineCount),
          col: col.clamp(1, 10000),
          message: msg,
        ),
      ];
    } catch (_) {
      return _checkJsManual(code);
    }
  }

  static List<_SyntaxError> _checkJsManual(String code) {
    final errors = <_SyntaxError>[];
    final lines = code.split('\n');
    final braceStack = <(int, int)>[];
    final parenStack = <(int, int)>[];
    final bracketStack = <(int, int)>[];
    String? stringChar;
    bool inBlockComment = false;
    bool inRegex = false;
    bool inRegexClass = false;
    bool lastWasValue = false;

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];
      int ci = 0;
      while (ci < line.length) {
        if (inBlockComment) {
          if (ci + 1 < line.length && line[ci] == '*' && line[ci + 1] == '/') {
            inBlockComment = false;
            ci += 2;
          } else {
            ci++;
          }
          continue;
        }
        if (inRegex) {
          if (line[ci] == '\\') {
            ci += 2;
            continue;
          }
          if (!inRegexClass && line[ci] == '[') {
            inRegexClass = true;
            ci++;
            continue;
          }
          if (inRegexClass && line[ci] == ']') {
            inRegexClass = false;
            ci++;
            continue;
          }
          if (!inRegexClass && line[ci] == '/') {
            inRegex = false;
            inRegexClass = false;
            lastWasValue = true;
            ci++;
            continue;
          }
          ci++;
          continue;
        }
        if (stringChar != null) {
          if (line[ci] == '\\') {
            ci += 2;
            continue;
          }
          if (line[ci] == stringChar) {
            stringChar = null;
            lastWasValue = true;
          }
          ci++;
          continue;
        }
        if (ci + 1 < line.length && line[ci] == '/' && line[ci + 1] == '/')
          break;
        if (ci + 1 < line.length && line[ci] == '/' && line[ci + 1] == '*') {
          inBlockComment = true;
          ci += 2;
          continue;
        }
        if (line[ci] == '/' && !lastWasValue) {
          inRegex = true;
          inRegexClass = false;
          lastWasValue = false;
          ci++;
          continue;
        }
        final ch = line[ci];
        switch (ch) {
          case '\'':
          case '"':
          case '`':
            stringChar = ch;
            lastWasValue = false;
          case '{':
            braceStack.add((li + 1, ci + 1));
            lastWasValue = false;
          case '}':
            if (braceStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: '} sin { correspondiente',
                ),
              );
            } else {
              braceStack.removeLast();
            }
            lastWasValue = true;
          case '(':
            parenStack.add((li + 1, ci + 1));
            lastWasValue = false;
          case ')':
            if (parenStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: ') sin ( correspondiente',
                ),
              );
            } else {
              parenStack.removeLast();
            }
            lastWasValue = true;
          case '[':
            bracketStack.add((li + 1, ci + 1));
            lastWasValue = false;
          case ']':
            if (bracketStack.isEmpty) {
              errors.add(
                _SyntaxError(
                  line: li + 1,
                  col: ci + 1,
                  message: '] sin [ correspondiente',
                ),
              );
            } else {
              bracketStack.removeLast();
            }
            lastWasValue = true;
          default:
            final c = ch.codeUnitAt(0);
            if ((c >= 65 && c <= 90) ||
                (c >= 97 && c <= 122) ||
                (c >= 48 && c <= 57) ||
                c == 95) {
              lastWasValue = true;
            } else if (ch != ' ' && ch != '\t') {
              lastWasValue = false;
            }
        }
        ci++;
      }
      if (stringChar != null && stringChar != '`') {
        errors.add(
          _SyntaxError(
            line: li + 1,
            col: line.length,
            message: "Cadena sin cerrar — falta $stringChar",
          ),
        );
        stringChar = null;
      }
      if (inRegex) {
        errors.add(
          _SyntaxError(
            line: li + 1,
            col: line.length,
            message: 'Expresión regular sin cerrar',
          ),
        );
        inRegex = false;
        inRegexClass = false;
      }
      lastWasValue = false;
    }
    for (final b in braceStack)
      errors.add(
        _SyntaxError(line: b.$1, col: b.$2, message: '{ sin } correspondiente'),
      );
    for (final p in parenStack)
      errors.add(
        _SyntaxError(line: p.$1, col: p.$2, message: '( sin ) correspondiente'),
      );
    for (final b in bracketStack)
      errors.add(
        _SyntaxError(line: b.$1, col: b.$2, message: '[ sin ] correspondiente'),
      );
    if (inBlockComment)
      errors.add(
        _SyntaxError(
          line: lines.length,
          col: 1,
          message: 'Comentario /* sin cerrar',
        ),
      );
    if (stringChar != null)
      errors.add(
        _SyntaxError(line: lines.length, col: 1, message: 'Cadena sin cerrar'),
      );
    errors.sort((a, b) => a.line.compareTo(b.line));
    return errors;
  }
}
