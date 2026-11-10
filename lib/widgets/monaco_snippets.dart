import 'dart:convert' show jsonEncode;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' as fm;

import '../models/plantilla.dart';
import '../services/snippet_service.dart';
import 'plsql_symbols.dart';
import 'snippets/snippets_browser_dialog.dart' show showSnippetsBrowser;

export 'snippets/snippets_browser_dialog.dart'
    show showSnippetsBrowser, SnippetsBrowserDialog;

// ── Snippets de usuario en editores Monaco ───────────────────────────────────
//
// Extrae la implementación de snippets del editor de procedimientos dinámicos
// (`code_editor_panel.dart`) para poder reutilizarla tal cual en cualquier otro
// editor Monaco de la app (p. ej. el editor de fuentes de objetos de esquema).

/// Se incrementa cada vez que el usuario modifica sus snippets.
///
/// Los editores abiertos escuchan este notificador para volver a registrar sus
/// completions sin tener que conocerse entre sí.
final ValueNotifier<int> snippetsRevision = ValueNotifier<int>(0);

/// Abre el visor/estación de snippets y notifica a los editores abiertos al cerrarlo.
Future<void> openSnippetsManager(BuildContext context) async {
  await showSnippetsBrowser(context);
  snippetsRevision.value++;
}

/// Registra los snippets del usuario como *completions* de Monaco.
///
/// Devuelve la registración para poder liberarla (`dispose`) o reemplazarla
/// luego de editar los snippets. Retorna `null` si no hay snippets.
///
/// Si [isLocalDocumentEditor] es `true`, se incluyen los snippets específicos de
/// YAML y texto plano (`yaml`, `any`).
/// Si es `false` (editores Oracle / SQL / PL-SQL), los snippets marcados con
/// lenguaje `yaml` se excluyen para que solo aparezcan en el editor de documentos locales.
Future<fm.MonacoCompletionRegistration?> registerUserSnippetCompletions(
  fm.MonacoController ctrl, {
  String id = 'user-snippets',
  bool isLocalDocumentEditor = false,
}) async {
  try {
    final allSnippets = await SnippetService.instance.loadAll();
    if (allSnippets.isEmpty) return null;

    final snippets = allSnippets.where((s) {
      final lang = s.language.toLowerCase().trim();
      if (isLocalDocumentEditor) {
        // En editor local: snippets de yaml o genéricos (any).
        // También admitimos otros si estuvieran disponibles en texto plano.
        return lang == 'yaml' || lang == 'any';
      }
      // En editores de procedimientos Oracle / SQL: no mostrar snippets yaml.
      return lang != 'yaml';
    }).toList();

    if (snippets.isEmpty) return null;

    final languages = isLocalDocumentEditor
        ? [fm.MonacoLanguage.yaml, fm.MonacoLanguage.plaintext]
        : [
            fm.MonacoLanguage.sql,
            fm.MonacoLanguage('plsql'),
            fm.MonacoLanguage.javascript,
          ];

    return await ctrl.registerStaticCompletions(
      id: id,
      languages: languages,
      triggerCharacters: const [' '],
      items: [
        for (final s in snippets)
          fm.CompletionItem(
            label: s.prefix,
            kind: fm.CompletionItemKind.snippet,
            detail: s.name,
            documentation: s.description.isNotEmpty ? s.description : null,
            insertText: s.body,
            insertTextRules: {fm.InsertTextRule.insertAsSnippet},
            // Por encima de las palabras clave del lenguaje.
            sortText: '0${s.prefix}',
          ),
      ],
    );
  } catch (_) {
    // Sin snippets disponibles (offline, error de red…): el editor sigue
    // funcionando normalmente.
    return null;
  }
}

/// Código JavaScript para instalar el navegador resiliente de snippets en Monaco.
/// Mantiene decoraciones rastreadas de los placeholders, intercepta Tab/Shift+Tab
/// mientras la navegación esté activa y expone `jump(direction)` para Ctrl+J / Ctrl+Shift+J.
const String _kSnippetNavigatorJs = r'''
(function() {
  try {
    var ed = window.editor;
    if (!ed) return;

    if (!window.__snippetNavigator) {
      window.__snippetNavigator = {
        active: false,
        currentIndex: -1,
        placeholders: [],     // Array de { id, index, text, range, defaultVal }
        decorationIds: [],    // IDs de deltaDecorations en Monaco
        lastSnippetRaw: '',   // Copia cruda del último snippet para re-escaneo resiliente

        // Inyecta estilos CSS para destacar visualmente el placeholder activo si aún no existen
        ensureStyles: function() {
          if (document.getElementById('__snippetNavigatorStyles')) return;
          var style = document.createElement('style');
          style.id = '__snippetNavigatorStyles';
          style.innerHTML =
            '.snippet-placeholder-active { background-color: rgba(56, 139, 253, 0.28) !important; border-bottom: 2px solid #58a6ff !important; border-radius: 2px; }' +
            '.snippet-placeholder-item { border-bottom: 1px dashed rgba(88, 166, 255, 0.45); }';
          document.head.appendChild(style);
        },

        // Registra placeholders y crea decoraciones rastreadas que se ajustan automáticamente
        registerPlaceholders: function(phs, rawSnippet) {
          this.ensureStyles();
          if (rawSnippet) {
            this.lastSnippetRaw = rawSnippet;
          }
          if (!phs || phs.length === 0) {
            this.clear();
            return;
          }

          var model = ed.getModel();
          if (!model) return;

          // Limpiar decoraciones previas si existían
          this.clear(false);

          this.placeholders = phs;
          this.currentIndex = -1;
          this.active = true;

          var newDecos = phs.map(function(p, i) {
            return {
              range: p.range,
              options: {
                description: 'snippet-placeholder-' + (p.index != null ? p.index : i),
                className: 'snippet-placeholder-item',
                stickiness: 1 // TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges
              }
            };
          });

          try {
            this.decorationIds = ed.deltaDecorations([], newDecos);
          } catch (_) {}
        },

        // Intenta re-escanear los placeholders en el documento actual si se perdieron las decoraciones
        rebuildPlaceholders: function() {
          var model = ed.getModel();
          if (!model) return false;

          // Si tenemos placeholders con defaultVal o lastSnippetRaw, reconstruir rangos
          var list = [];
          if (this.placeholders && this.placeholders.length > 0) {
            for (var i = 0; i < this.placeholders.length; i++) {
              var p = this.placeholders[i];
              var targetText = p.defaultVal || p.text;
              if (targetText && targetText.length > 0) {
                var matches = model.findMatches(targetText, false, false, true, null, true);
                if (matches && matches.length > 0) {
                  var mRange = matches[0].range;
                  list.push({
                    id: p.id || ('ph_reb_' + i),
                    index: p.index != null ? p.index : i,
                    defaultVal: targetText,
                    range: {
                      startLineNumber: mRange.startLineNumber,
                      startColumn: mRange.startColumn,
                      endLineNumber: mRange.endLineNumber,
                      endColumn: mRange.endColumn
                    }
                  });
                }
              }
            }
          }

          if (list.length === 0 && this.lastSnippetRaw) {
            var phRegex = /\$\{(\d+):([^}]*)\}|\$(\d+)/g;
            var match;
            var seenIndices = {};
            while ((match = phRegex.exec(this.lastSnippetRaw)) !== null) {
              var idx = match[1] ? parseInt(match[1], 10) : parseInt(match[3], 10);
              var defaultVal = match[2] || '';
              if (idx > 0 && !seenIndices[idx] && defaultVal.length > 0) {
                seenIndices[idx] = true;
                var matches2 = model.findMatches(defaultVal, false, false, true, null, true);
                if (matches2 && matches2.length > 0) {
                  var mRange2 = matches2[0].range;
                  list.push({
                    id: 'ph_reb_' + idx,
                    index: idx,
                    defaultVal: defaultVal,
                    range: {
                      startLineNumber: mRange2.startLineNumber,
                      startColumn: mRange2.startColumn,
                      endLineNumber: mRange2.endLineNumber,
                      endColumn: mRange2.endColumn
                    }
                  });
                }
              }
            }
            list.sort(function(a, b) { return a.index - b.index; });
          }

          if (list.length > 0) {
            this.registerPlaceholders(list);
            return true;
          }
          return false;
        },

        clear: function(deep) {
          if (this.decorationIds && this.decorationIds.length > 0) {
            try {
              ed.deltaDecorations(this.decorationIds, []);
            } catch (_) {}
          }
          this.decorationIds = [];
          if (deep !== false) {
            this.placeholders = [];
            this.currentIndex = -1;
            this.active = false;
          }
        },

        // Salta en la dirección especificada (1: siguiente, -1: anterior, 0: actual/primero)
        jump: function(direction) {
          var sc = ed.getContribution('snippetController2');

          // Si la sesión nativa de Monaco sigue viva, delegar directamente
          if (sc && sc.isInSnippet && sc.isInSnippet()) {
            if (direction > 0) {
              sc.next();
            } else if (direction < 0) {
              sc.prev();
            }
            this.active = true;
            this.forceEditorFocus();
            return true;
          }

          // Si no hay placeholders o se perdieron las decoraciones, intentar reconstruir
          if (!this.placeholders || this.placeholders.length === 0 || !this.decorationIds || this.decorationIds.length === 0) {
            var rebuilt = this.rebuildPlaceholders();
            if (!rebuilt) {
              this.active = false;
              return false;
            }
          }

          var model = ed.getModel();
          if (!model) {
            this.active = false;
            return false;
          }

          // Calcular nuevo índice (o el primero si currentIndex no es válido)
          var total = this.placeholders.length;
          if (total === 0) return false;

          var targetIndex = this.currentIndex;
          if (direction === 0) {
            targetIndex = (targetIndex >= 0 && targetIndex < total) ? targetIndex : 0;
          } else if (targetIndex < 0 || targetIndex >= total) {
            targetIndex = direction > 0 ? 0 : total - 1;
          } else {
            targetIndex = targetIndex + direction;
          }

          if (targetIndex < 0) {
            targetIndex = total - 1; // Wraparound circular
          } else if (targetIndex >= total) {
            // Si llegó al final con Tab normal, terminar navegación; con F8 / llamada directa hacer wraparound
            if (direction > 0 && !this._manualJump) {
              this.clear(true);
              return false;
            }
            targetIndex = 0;
          }

          // Obtener rango actualizado en tiempo real según las decoraciones rastreadas
          var decId = this.decorationIds[targetIndex];
          var currentRange = decId ? model.getDecorationRange(decId) : null;

          // Si se perdió el rango específico, intentar con el range guardado o re-buscar por defaultVal
          if (!currentRange && this.placeholders[targetIndex]) {
            var ph = this.placeholders[targetIndex];
            if (ph.defaultVal) {
              var m = model.findMatches(ph.defaultVal, false, false, true, null, true);
              if (m && m.length > 0) {
                currentRange = m[0].range;
              }
            }
            if (!currentRange && ph.range) {
              currentRange = ph.range;
            }
          }

          if (!currentRange) {
            this.currentIndex = targetIndex;
            return false;
          }

          this.currentIndex = targetIndex;
          this.active = true;

          try {
            var sel = {
              selectionStartLineNumber: currentRange.startLineNumber,
              selectionStartColumn: currentRange.startColumn,
              positionLineNumber: currentRange.endLineNumber,
              positionColumn: currentRange.endColumn
            };
            if (window.monaco && window.monaco.Selection) {
              sel = new window.monaco.Selection(
                currentRange.startLineNumber,
                currentRange.startColumn,
                currentRange.endLineNumber,
                currentRange.endColumn
              );
            }
            ed.setSelection(sel);
            ed.revealRangeInCenterIfOutsideViewport(currentRange);
          } catch (_) {}

          this.forceEditorFocus();

          return true;
        },

        forceEditorFocus: function() {
          try {
            window.focus();
            if (window.flutterMonaco && window.flutterMonaco.forceFocus) {
              try { window.flutterMonaco.forceFocus(); } catch(_) {}
            }
            if (ed) ed.focus();
            var ta = document.querySelector('textarea.inputarea, .monaco-editor textarea, [contenteditable=true]');
            if (ta) ta.focus();
          } catch (_) {}
        },

        // Inserta un snippet interactivo y activa el seguimiento de placeholders
        insertSnippet: function(snippetRaw) {
          try {
            if (!ed) return false;
            ed.focus();
            var pos = ed.getPosition();
            if (!pos) {
              ed.setPosition({ lineNumber: 1, column: 1 });
            }
            var sc = ed.getContribution('snippetController2');
            if (!sc) {
              var plain = snippetRaw.replace(/\$\{(\d+):?([^}]*)\}|\$(\d+)/g, function(_, m1, m2, m3) {
                return m2 || '';
              });
              ed.trigger('keyboard', 'type', { text: plain });
              return true;
            }
            sc.insert(snippetRaw, {
              undoStopBefore: true,
              undoStopAfter: true,
              adjustWhitespace: true
            });
            ed.focus();

            try {
              var session = sc._currentSession || (sc.getSession ? sc.getSession() : null) || sc._session || null;
              var list = [];
              var model = ed.getModel();

              if (session && session._placeholders && session._placeholders.length > 0) {
                var rawPhs = session._placeholders;
                for (var i = 0; i < rawPhs.length; i++) {
                  var p = rawPhs[i];
                  var r = p.range || (p.ranges && p.ranges.length > 0 ? p.ranges[0] : null);
                  if (r) {
                    var defVal = p.value || (model ? model.getValueInRange(r) : '') || '';
                    list.push({
                      id: p.id || ('ph_' + i),
                      index: p.index != null ? p.index : i,
                      defaultVal: defVal,
                      range: {
                        startLineNumber: r.startLineNumber,
                        startColumn: r.startColumn,
                        endLineNumber: r.endLineNumber,
                        endColumn: r.endColumn
                      }
                    });
                  }
                }
              }

              if (list.length === 0 && model) {
                var phRegex = /\$\{(\d+):([^}]*)\}|\$(\d+)/g;
                var match;
                var seenIndices = {};
                while ((match = phRegex.exec(snippetRaw)) !== null) {
                  var idx = match[1] ? parseInt(match[1], 10) : parseInt(match[3], 10);
                  var defaultVal = match[2] || '';
                  if (idx > 0 && !seenIndices[idx] && defaultVal.length > 0) {
                    seenIndices[idx] = true;
                    var matches = model.findMatches(defaultVal, false, false, true, null, true);
                    if (matches && matches.length > 0) {
                      var mRange = matches[0].range;
                      list.push({
                        id: 'ph_fallback_' + idx,
                        index: idx,
                        defaultVal: defaultVal,
                        range: {
                          startLineNumber: mRange.startLineNumber,
                          startColumn: mRange.startColumn,
                          endLineNumber: mRange.endLineNumber,
                          endColumn: mRange.endColumn
                        }
                      });
                    }
                  }
                }
                list.sort(function(a, b) { return a.index - b.index; });
              }

              if (list.length > 0) {
                this.registerPlaceholders(list, snippetRaw);
                this.jump(0);
              }
            } catch (_) {}

            return true;
          } catch(e) {
            return false;
          }
        }
      };
    }

    if (!window.__snippetNavigatorListenersInstalled) {
      // Registrar comando de Ctrl+J y Ctrl+Shift+J directamente en Monaco
      try {
        if (window.monaco && window.monaco.KeyCode && window.monaco.KeyMod) {
          // KeyCode.KeyJ = 40 (o usar KeyCode.KEY_J según versión)
          var keyJ = window.monaco.KeyCode.KeyJ || window.monaco.KeyCode.KEY_J || 40;
          ed.addCommand(window.monaco.KeyMod.CtrlCmd | keyJ, function() {
            var nav = window.__snippetNavigator;
            if (!nav) return;
            nav.active = true;
            nav._manualJump = true;
            nav.jump(1);
            nav._manualJump = false;
            nav.forceEditorFocus();
          });
          ed.addCommand(window.monaco.KeyMod.CtrlCmd | window.monaco.KeyMod.Shift | keyJ, function() {
            var nav = window.__snippetNavigator;
            if (!nav) return;
            nav.active = true;
            nav._manualJump = true;
            nav.jump(-1);
            nav._manualJump = false;
            nav.forceEditorFocus();
          });
        }
      } catch(_) {}

      // Helper para chequear si el widget de autocompletado (suggest widget) está visible
      function isSuggestWidgetVisible() {
        try {
          var sw = document.querySelector('.suggest-widget');
          if (!sw) return false;
          if (sw.classList && sw.classList.contains('visible')) return true;
          var style = window.getComputedStyle(sw);
          return style.display !== 'none' && style.visibility !== 'hidden' && (sw.offsetHeight > 0 || sw.offsetWidth > 0);
        } catch (_) {
          return false;
        }
      }

      // Cancela explícitamente cualquier sesión y memoria de autocompletado
      function cancelSuggestWidget() {
        try {
          var sugg = ed.getContribution('editor.contrib.suggestController');
          if (sugg && sugg.cancelSuggestWidget) {
            sugg.cancelSuggestWidget();
          }
        } catch (_) {}
      }

      // Interceptor de teclado en Monaco: captura Tab / Shift+Tab, Ctrl+J / Ctrl+Shift+J y Escape
      ed.onKeyDown(function(e) {
        var nav = window.__snippetNavigator;

        var isTab = (e.keyCode === 2) || (e.browserEvent && (e.browserEvent.key === 'Tab' || e.browserEvent.keyCode === 9));
        var hasCtrl = e.ctrlKey || e.metaKey || (e.browserEvent && (e.browserEvent.ctrlKey || e.browserEvent.metaKey));
        var isKeyJ = (e.keyCode === 40) ||
                     (e.browserEvent && (e.browserEvent.key === 'j' || e.browserEvent.key === 'J' || e.browserEvent.keyCode === 74));
        var isCtrlJ = hasCtrl && isKeyJ;
        var isEsc = (e.keyCode === 9) || (e.browserEvent && (e.browserEvent.key === 'Escape' || e.browserEvent.keyCode === 27));

        // Escape: Si el menú de autocompletado está activo, Escape sólo cierra el autocompletado
        // y conserva intacta la navegación del snippet interactivo.
        // Si el menú NO está activo, Escape sí cancela la navegación manual del snippet.
        if (isEsc) {
          var suggestVisible = isSuggestWidgetVisible();
          if (suggestVisible) {
            cancelSuggestWidget();
            e.preventDefault();
            e.stopPropagation();
            return;
          }

          cancelSuggestWidget();
          if (nav && nav.active) {
            nav.clear(true);
          }
          return;
        }

        // Ctrl+J / Ctrl+Shift+J: Activar / Reanudar o navegar placeholders
        if (isCtrlJ) {
          if (!nav) return;
          e.preventDefault();
          e.stopPropagation();
          nav.active = true;
          nav._manualJump = true;
          var dir = (e.shiftKey || (e.browserEvent && e.browserEvent.shiftKey)) ? -1 : 1;
          nav.jump(dir);
          nav._manualJump = false;
          nav.forceEditorFocus();
          return;
        }

        // Tab / Shift+Tab
        if (isTab) {
          var suggestVisible = isSuggestWidgetVisible();

          // Si el menú de sugerencias NO está visible, nos aseguramos de que no autocomplete
          // por memoria residual de Monaco
          if (!suggestVisible) {
            cancelSuggestWidget();

            var sc = ed.getContribution('snippetController2');
            if (sc && sc.isInSnippet && sc.isInSnippet()) {
              // Dejar que Monaco maneje la navegación del snippet nativo
              return;
            }

            // Si tenemos placeholders en el navegador resiliente
            if (nav && nav.placeholders && nav.placeholders.length > 0) {
              e.preventDefault();
              e.stopPropagation();
              var direction = (e.shiftKey || (e.browserEvent && e.browserEvent.shiftKey)) ? -1 : 1;
              nav.jump(direction);
              return;
            }

            // Si no hay snippet ni sugerencias visibles, Tab solo debe insertar sangría / tabulación normal
            // Si Monaco estuviera intentando aceptar una sugerencia invisible por tabCompletion,
            // prevenimos y disparamos la acción de tabulación del editor.
            e.preventDefault();
            e.stopPropagation();
            try {
              ed.trigger('keyboard', 'tab', null);
            } catch (_) {}
            return;
          }

          // Si el suggest widget SÍ está visible, dejar que Monaco procese la aceptación o navegación
          return;
        }
      });

      // Captura global en document/window dentro del WebView para Ctrl+J / Ctrl+Shift+J
      window.addEventListener('keydown', function(evt) {
        var isCtrl = evt.ctrlKey || evt.metaKey;
        var isJ = evt.key === 'j' || evt.key === 'J' || evt.keyCode === 74;
        if (isCtrl && isJ) {
          var nav = window.__snippetNavigator;
          if (nav) {
            evt.preventDefault();
            evt.stopPropagation();
            nav.active = true;
            nav._manualJump = true;
            nav.jump(evt.shiftKey ? -1 : 1);
            nav._manualJump = false;
            nav.forceEditorFocus();
          }
        }
      }, true);

      window.__snippetNavigatorListenersInstalled = true;
    }

    window.__snippetNavigatorInstalled = true;
  } catch (_) {}
})();
''';

/// Instala el navegador de snippets en la instancia de Monaco Editor.
Future<void> installMonacoSnippetNavigator(fm.MonacoController ctrl) async {
  try {
    await ctrl.runJavaScript(_kSnippetNavigatorJs);
  } catch (_) {}
}

/// Salta al siguiente o anterior placeholder de snippet en Monaco.
/// Reanuda la navegación desde donde quedó o avanza en secuencia.
Future<bool> jumpSnippetPlaceholder(
  fm.MonacoController ctrl, {
  required bool forward,
}) async {
  try {
    await ctrl.requestFocus(intent: fm.MonacoFocusIntent.user);
  } catch (_) {}
  final dir = forward ? 1 : -1;
  final jsCode =
      '''
    (function() {
      try {
        var ed = window.editor;
        if (!ed) return false;
        var nav = window.__snippetNavigator;
        if (!nav) return false;
        nav.active = true;
        nav._manualJump = true;
        var res = nav.jump($dir);
        nav._manualJump = false;
        nav.forceEditorFocus();
        return res;
      } catch(_) {
        return false;
      }
    })()
  ''';
  try {
    final result = await ctrl.evaluateJavaScript<bool>(jsCode);
    return result ?? false;
  } catch (_) {
    return false;
  }
}

/// Inserta un texto con sintaxis de snippet (ej. `${1:placeholder}`, `${0:usuario}`)
/// en el cursor o selección actual del editor Monaco utilizando la contribución nativa
/// `snippetController2`. Esto activa el modo de edición interactivo y la navegación con Tab.
Future<bool> insertMonacoSnippet(
  fm.MonacoController ctrl,
  String snippetText,
) async {
  // Asegurar que el navegador esté instalado antes de insertar
  await installMonacoSnippetNavigator(ctrl);

  final snippetTextJson = jsonEncode(snippetText);
  final jsCode =
      r'''
    (function() {
      try {
        var nav = window.__snippetNavigator;
        if (nav && nav.insertSnippet) {
          return nav.insertSnippet(''' +
      snippetTextJson +
      r''');
        }
        var ed = window.editor;
        if (!ed) return false;
        ed.focus();
        var sc = ed.getContribution('snippetController2');
        if (sc) {
          sc.insert(''' +
      snippetTextJson +
      r''', { undoStopBefore: true, undoStopAfter: true, adjustWhitespace: true });
          return true;
        }
        return false;
      } catch (e) {
        return false;
      }
    })()
  ''';

  try {
    final result = await ctrl.evaluateJavaScript<bool>(jsCode);
    return result ?? false;
  } catch (_) {
    return false;
  }
}

/// Genera el script de JavaScript para pegar texto en el editor Monaco,
/// detectando automáticamente si el texto pegado contiene sintaxis de snippet interactivo
/// (`${1:nombre}`, `$0`, etc.). Si es así, lo inserta a través de `snippetController2`
/// y registra sus placeholders en el navegador interactivo para habilitar la navegación con Tab.
String buildMonacoPasteJs(String text) {
  final literal = jsonEncode(text);
  final isSnippetLiteral = Plantilla.contieneSintaxisSnippet(text) ? 'true' : 'false';

  return '(()=>{'
      '  try {'
      '    const t = $literal;'
      '    const isSnippet = $isSnippetLiteral;'
      '    var aux = window.__fmAuxInput ? window.__fmAuxInput() : null;'
      '    if (aux) {'
      '      var start = aux.selectionStart != null ? aux.selectionStart : aux.value.length;'
      '      var end = aux.selectionEnd != null ? aux.selectionEnd : aux.value.length;'
      '      var val = aux.value || "";'
      '      aux.value = val.substring(0, start) + t + val.substring(end);'
      '      aux.selectionStart = aux.selectionEnd = start + t.length;'
      '      aux.focus();'
      '      aux.dispatchEvent(new Event("input", { bubbles: true }));'
      '      return "ok";'
      '    }'
      '    const ed = window.editor;'
      '    if (!ed) return "err";'
      '    ed.focus();'
      '    if (isSnippet) {'
      '      var nav = window.__snippetNavigator;'
      '      if (nav && nav.insertSnippet) {'
      '        var ok = nav.insertSnippet(t);'
      '        if (ok) return "ok";'
      '      }'
      '      var sc = ed.getContribution("snippetController2");'
      '      if (sc) {'
      '        sc.insert(t, { undoStopBefore: true, undoStopAfter: true, adjustWhitespace: true });'
      '        return "ok";'
      '      }'
      '    }'
      '    let sels = ed.getSelections();'
      '    if (!sels || sels.length === 0) {'
      '      const s = ed.getSelection();'
      '      sels = s ? [s] : [];'
      '    }'
      '    if (sels.length === 0) return "err";'
      '    const lines = t.split(/\\r?\\n/);'
      '    const matchLines = sels.length > 1 && lines.length === sels.length;'
      '    ed.pushUndoStop();'
      '    ed.executeEdits("flutter-paste", sels.map(function(s, idx){'
      '      return { range: s, text: matchLines ? lines[idx] : t, forceMoveMarkers: true };'
      '    }));'
      '    ed.pushUndoStop();'
      '    return "ok";'
      '  } catch(e) { return "err"; }'
      '})()';
}

// ── Símbolos declarados en el fuente ─────────────────────────────────────────

/// Icono de autocompletado según el tipo de símbolo.
fm.CompletionItemKind _kindOf(PlSqlSymbolKind k) => switch (k) {
  PlSqlSymbolKind.parameter => fm.CompletionItemKind.variable,
  PlSqlSymbolKind.variable => fm.CompletionItemKind.variable,
  PlSqlSymbolKind.constant => fm.CompletionItemKind.constant,
  PlSqlSymbolKind.cursor => fm.CompletionItemKind.reference,
  PlSqlSymbolKind.exception => fm.CompletionItemKind.event,
  PlSqlSymbolKind.type => fm.CompletionItemKind.typeParameter,
  PlSqlSymbolKind.subprogram => fm.CompletionItemKind.functionType,
};

/// Convierte el fuente PL/SQL en items de autocompletado con los parámetros y
/// variables declaradas.
///
/// El parseo corre en un isolate (`compute`) para no bloquear la UI en fuentes
/// grandes (packages de miles de líneas).
Future<List<fm.CompletionItem>> plsqlSymbolCompletions(String code) async {
  if (code.trim().isEmpty) return const [];
  final List<PlSqlSymbol> symbols;
  try {
    symbols = await compute(parsePlSqlSymbols, code);
  } catch (_) {
    return const [];
  }
  return [
    for (final s in symbols)
      fm.CompletionItem(
        label: s.name,
        kind: _kindOf(s.kind),
        detail: s.detail,
        insertText: s.name,
        // Por encima de las palabras clave del lenguaje, igual que en el
        // editor de procedimientos dinámicos.
        sortText: '0${s.name}',
      ),
  ];
}
