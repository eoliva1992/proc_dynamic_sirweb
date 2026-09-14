part of 'code_editor_panel.dart';

// ── Panel de chat con GitHub Copilot ──────────────────────────────────────────

/// Panel lateral acoplado que conversa con Copilot a través de la CLI oficial.
///
/// Replica el modelo de interacción de Copilot Chat en VS Code:
/// conversaciones persistentes con contexto de servidor (`--resume`),
/// respuesta en streaming token a token, markdown renderizado, comandos
/// `/slash` con navegación por teclado y acciones sobre los bloques de código.
class _AiChatDockedPanel extends StatefulWidget {
  final String procedimiento;
  final String ambiente;

  /// Devuelve la selección de Monaco con su rango, o `null` si no hay.
  final Future<EditorSelection?> Function() getSelection;

  /// Texto completo del documento activo.
  final String Function() getFullText;

  /// Resumen de los errores actuales (sintaxis + compilación), si los hay.
  final String Function() getErrors;

  /// Inserta código en el editor en la posición del cursor.
  final Future<void> Function(String code) onInsertCode;

  /// Aplica las ediciones ancladas que propuso Copilot.
  final Future<bool> Function(List<EditBlock> bloques) onApplyEdits;

  /// Aplica código **sobre el documento abierto**: reemplaza la selección o,
  /// si no hay, el documento entero. Devuelve `true` si se aplicó.
  ///
  /// Con `confirmar: false` no pregunta: es el camino de la aplicación
  /// automática, donde la red de seguridad es Ctrl+Z, no un diálogo.
  final Future<bool> Function(String code, {bool confirmar}) onApplyCode;

  final VoidCallback onClose;

  const _AiChatDockedPanel({
    required this.procedimiento,
    required this.ambiente,
    required this.getSelection,
    required this.getFullText,
    required this.getErrors,
    required this.onInsertCode,
    required this.onApplyCode,
    required this.onApplyEdits,
    required this.onClose,
  });

  @override
  State<_AiChatDockedPanel> createState() => _AiChatDockedPanelState();
}

class _AiChatDockedPanelState extends State<_AiChatDockedPanel> {
  final _service = CopilotCliService.instance;
  final _store = ChatStore.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  /// Conversaciones guardadas, la activa la primera vez que se abre el panel.
  List<ChatConversation> _conversations = [];
  ChatConversation _current = ChatConversation.nueva();

  CopilotAuthStatus _auth = const CopilotAuthStatus(CopilotAuthState.unknown);
  CopilotSessionEvidence _evidence = const CopilotSessionEvidence();
  StreamSubscription<CopilotEvent>? _sub;
  bool _sending = false;
  bool _verifying = false;
  bool _showHistory = false;

  /// Fase de arranque de la CLI mientras aún no llega texto del modelo.
  String? _startupStatus;

  /// Incluir el resumen de errores de sintaxis y compilación.
  ///
  /// Se separa del código porque no siempre interesa: preguntar «qué hace
  /// esto» con 40 errores de compilación colgando desvía la respuesta.
  bool _includeErrors = true;

  /// Modelo seleccionado (`auto` = lo elige Copilot), como en VS Code.
  String _model = 'auto';

  /// Modelos que admite la CLI instalada, leídos de `copilot help config`.
  List<String> _models = CopilotCliService.fallbackModels;
  bool _loadingModels = false;

  /// Modo de trabajo: Agente, Plan o Pregunta (como el selector de VS Code).
  CopilotChatMode _mode = CopilotChatMode.ask;

  /// Ajustes finos del modelo.
  CopilotEffort _effort = CopilotEffort.auto;
  CopilotContextTier _contextTier = CopilotContextTier.standard;

  /// Comando `/…` que se está escribiendo; alimenta el popup de sugerencias.
  String? _slashQuery;

  /// Elemento resaltado del popup, para navegar con ↑/↓ como en VS Code.
  int _slashIndex = 0;

  /// Historial de preguntas enviadas, recorrible con ↑ en la caja vacía.
  final List<String> _sentHistory = [];
  int _historyCursor = -1;

  /// Ancho del panel; se puede arrastrar el borde izquierdo y se recuerda.
  double _panelWidth = 400;
  static const double _kMinWidth = 320;
  static const double _kMaxWidth = 760;

  /// `true` mientras la vista está pegada al final de la conversación.
  ///
  /// El auto-scroll solo se aplica en ese caso: si el usuario ha subido a
  /// releer algo, el streaming no debe arrastrarle de vuelta al final.
  bool _stickToBottom = true;

  /// Filtro de la lista de conversaciones guardadas.
  final _historySearch = TextEditingController();
  String _historyQuery = '';

  /// Mensaje bajo el puntero: sus acciones solo aparecen al pasar por encima.
  ChatMessage? _hovered;

  /// `true` cuando el compositor tiene texto: gobierna el botón de envío.
  bool _hasText = false;

  /// Consejo sobre los `/comandos` en la cabecera de la caja de entrada.
  bool _showTip = false;

  /// Paso del plan que se está abordando, base 0.
  ///
  /// Vive en el panel y no en el mensaje porque es estado de navegación: el
  /// plan en sí es inmutable una vez que Copilot lo redactó.
  int _planStep = 0;

  /// La lista de pasos está desplegada bajo la barra del plan.
  bool _planExpanded = false;

  /// El usuario ocultó las acciones del plan para seguir conversando.
  bool _planDismissed = false;

  /// Selección viva del editor, para el chip `PROCEDIMIENTO:112-140`.
  EditorSelection? _seleccion;

  /// Errores que aparecieron **después** de aplicar el último cambio.
  ///
  /// Solo los nuevos: los que ya estaban antes no los causó Copilot y
  /// señalarlos aquí sería ruido.
  String? _erroresIntroducidos;

  /// Ya se pidió al modelo que reformulara la respuesta como edición.
  ///
  /// Evita el bucle: si el turno correctivo tampoco trae una edición
  /// aplicable, se para y decide el usuario.
  bool _reintentoFormato = false;

  /// Escribir en el documento en cuanto la respuesta esté lista.
  ///
  /// Por defecto sí: el sentido de este panel es editar la regla, no dictar
  /// código para que el usuario lo copie. La seguridad no viene de preguntar
  /// sino de que el cambio sea deshacible con Ctrl+Z y quede resaltado.
  bool _autoApply = true;

  /// Último plan redactado por Copilot, si la conversación acaba en uno.
  ///
  /// Se recalcula en cada build a partir del último mensaje en modo Plan; no
  /// se cachea porque el contenido cambia mientras llega el streaming.
  ChatPlan get _plan {
    final m = _planMessage;
    return m == null ? const ChatPlan([]) : parsePlan(m.content);
  }

  /// Mensaje que contiene el plan vigente, o `null` si el último turno no fue
  /// un plan terminado.
  ChatMessage? get _planMessage {
    if (_messages.isEmpty) return null;
    final last = _messages.last;
    if (last.isUser || last.isStreaming || last.isError) return null;
    return last.mode == CopilotChatMode.plan.id ? last : null;
  }

  static const _kModelPref = 'copilot_chat_model';
  static const _kIncludeErrorsPref = 'copilot_chat_include_errors';
  static const _kAutoApplyPref = 'copilot_chat_auto_apply';
  static const _kModePref = 'copilot_chat_mode';
  static const _kEffortPref = 'copilot_chat_effort';
  static const _kContextTierPref = 'copilot_chat_context_tier';
  static const _kWidthPref = 'copilot_chat_panel_width';
  static const _kTipSeenPref = 'copilot_chat_tip_seen';

  List<ChatMessage> get _messages => _current.messages;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    // El borde de la caja de entrada se resalta al enfocar, como en VS Code.
    _inputFocus.addListener(_onFocusChanged);
    _scroll.addListener(_onScroll);
    _historySearch.addListener(
      () => _safeSetState(() => _historyQuery = _historySearch.text.trim()),
    );
    unawaited(_loadPrefs());
    unawaited(_refreshAuth());
  }

  /// Recalcula si la vista sigue pegada al final (margen de 40 px).
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final stick = pos.pixels >= pos.maxScrollExtent - 40;
    if (stick != _stickToBottom) _safeSetState(() => _stickToBottom = stick);
  }

  void _onFocusChanged() {
    _safeSetState(() {});
    // Al volver al chat desde el editor, lo primero que se mira es el chip:
    // conviene que ya diga qué líneas viajan.
    if (_inputFocus.hasFocus) unawaited(_refrescarSeleccion());
  }

  /// `setState` a prueba de rebuilds ajenos.
  ///
  /// Los listeners de `FocusNode`/`TextEditingController` y los callbacks del
  /// stream pueden dispararse **mientras Flutter está construyendo otro
  /// widget** (por ejemplo, al cambiar de ambiente: la reacción de MobX
  /// reconstruye el `Observer` que envuelve al editor y, de paso, mueve el
  /// foco). Llamar a `setState` en ese instante marca el elemento como sucio
  /// fuera del build scope activo y Flutter aborta con
  /// *«Tried to build dirty widget in the wrong build scope»*.
  /// Aquí se detecta esa fase y se aplaza el cambio al siguiente frame.
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final building =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (building) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _inputFocus.removeListener(_onFocusChanged);
    _scroll.removeListener(_onScroll);
    unawaited(_sub?.cancel());
    unawaited(_service.cancel());
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    _historySearch.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await _store.load();
    if (!mounted) return;
    _safeSetState(() {
      _model = prefs.getString(_kModelPref) ?? 'auto';
      _includeErrors = prefs.getBool(_kIncludeErrorsPref) ?? true;
      _autoApply = prefs.getBool(_kAutoApplyPref) ?? true;
      _mode = CopilotChatModeX.fromId(prefs.getString(_kModePref));
      _effort = CopilotEffortX.fromId(prefs.getString(_kEffortPref));
      _contextTier = CopilotContextTierX.fromId(
        prefs.getString(_kContextTierPref),
      );
      _panelWidth = (prefs.getDouble(_kWidthPref) ?? 400).clamp(
        _kMinWidth,
        _kMaxWidth,
      );
      _showTip = !(prefs.getBool(_kTipSeenPref) ?? false);
      _conversations = saved;
      // Se retoma la última conversación, como hace VS Code al reabrir.
      if (saved.isNotEmpty) _current = saved.first;
    });
    unawaited(_loadModels());
  }

  /// Pregunta a la CLI qué modelos admite la cuenta.
  ///
  /// La lista depende de la versión instalada y de la organización, así que no
  /// se codifica en la app: se lee de `copilot help config`, que es la misma
  /// fuente que usa el comando `/model` de la CLI.
  Future<void> _loadModels({bool force = false}) async {
    if (_loadingModels) return;
    _safeSetState(() => _loadingModels = true);
    final models = await _service.listModels(force: force);
    if (!mounted) return;
    _safeSetState(() {
      _models = models;
      _loadingModels = false;
      // Un modelo guardado que ya no exista se degrada a `auto` para evitar el
      // error «Model … is not available» en el primer envío.
      if (_model != 'auto' && !models.contains(_model)) _model = 'auto';
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModelPref, _model);
    await prefs.setBool(_kIncludeErrorsPref, _includeErrors);
    await prefs.setBool(_kAutoApplyPref, _autoApply);
    await prefs.setString(_kModePref, _mode.id);
    await prefs.setString(_kEffortPref, _effort.id);
    await prefs.setString(_kContextTierPref, _contextTier.id);
    await prefs.setDouble(_kWidthPref, _panelWidth);
  }

  Future<void> _persistConversations() async {
    _current.updatedAt = DateTime.now();
    _current.autoTitle();
    if (!_conversations.contains(_current) && _current.messages.isNotEmpty) {
      _conversations.insert(0, _current);
    }
    await _store.save(_conversations);
  }

  /// Detecta si se está escribiendo un slash command al principio del texto.
  void _onInputChanged() {
    final text = _input.text;
    final match = RegExp(r'^\s*/(\w*)$').firstMatch(text);
    final query = match?.group(1);
    final hasText = text.trim().isNotEmpty;
    if (query != _slashQuery || hasText != _hasText) {
      _safeSetState(() {
        if (query != _slashQuery) _slashIndex = 0;
        _slashQuery = query;
        _hasText = hasText;
      });
    }
  }

  Future<void> _refreshAuth({bool force = false}) async {
    final status = await _service.checkAuth(force: force);
    final evidence = await _service.collectEvidence();
    if (!mounted) return;
    _safeSetState(() {
      _auth = status;
      _evidence = evidence;
    });
  }

  /// Verificación real contra la CLI: es la única forma fiable de saber si la
  /// sesión sigue siendo válida, así que se hace solo bajo petición explícita.
  Future<void> _verifySession() async {
    if (_verifying) return;
    _safeSetState(() => _verifying = true);
    final status = await _service.verifySession();
    final evidence = await _service.collectEvidence();
    if (!mounted) return;
    _safeSetState(() {
      _auth = status;
      _evidence = evidence;
      _verifying = false;
    });
    if (status.isReady) {
      AppToast.success('Sesión de Copilot verificada');
    } else {
      AppToast.warning(status.detail ?? 'La sesión no es válida');
    }
  }

  /// Texto legible para la última verificación correcta.
  String _lastVerifiedLabel() {
    final at = _evidence.lastVerifiedOk;
    if (at == null) return 'sin verificar';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'verificada hace instantes';
    if (d.inMinutes < 60) return 'verificada hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'verificada hace ${d.inHours} h';
    return 'verificada hace ${d.inDays} d';
  }

  /// Baja al final de la conversación.
  ///
  /// Durante el streaming se llama en cada fragmento, así que solo actúa si el
  /// usuario no se ha desplazado hacia arriba: interrumpir su lectura para
  /// arrastrarle al final es de los defectos más molestos de un chat.
  void _scrollToEnd({bool force = false}) {
    if (!force && !_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (force) {
        unawaited(
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
        _safeSetState(() => _stickToBottom = true);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  // ── Envío ──────────────────────────────────────────────────────────────────

  Future<void> _send({String? overrideText, bool esReintento = false}) async {
    final raw = (overrideText ?? _input.text).trim();
    if (raw.isEmpty || _sending) return;

    if (!_auth.isReady) {
      await _refreshAuth(force: true);
      if (!mounted || !_auth.isReady) return;
    }

    // Slash command: la plantilla se antepone y el resto es la pregunta.
    final parsed = parseSlashCommand(raw);
    final command = parsed.command;
    final question = command == null
        ? raw
        : '${command.template}\n\n${parsed.rest}'.trim();

    // La CLI mantiene el hilo por sesión, así que a partir del segundo turno
    // solo viaja la pregunta: ni preámbulo ni historial.
    final conv = _current;
    final resume = conv.sessionStarted;
    conv.sessionId ??= _newSessionUuid();

    // El documento abierto viaja SIEMPRE. Sin él, Copilot responde sobre PL/SQL
    // genérico en vez de sobre la regla que se está editando, que es justo lo
    // que hace útil este panel; por eso no hay interruptor para quitarlo.
    // Si hay selección se manda solo ella: es más preciso y gasta menos
    // presupuesto de línea de comandos.
    final seleccion = await widget.getSelection();
    final String code = seleccion?.text ?? widget.getFullText();

    final errores = _includeErrors ? widget.getErrors() : '';

    // Sello del contexto realmente adjuntado, para que al releer el hilo se
    // sepa con qué información respondió Copilot.
    final adjuntos = <String>[
      _etiquetaDocumento(seleccion),
      if (errores.trim().isNotEmpty) 'errores',
      widget.ambiente,
    ];

    final answer = ChatMessage.assistant('', isStreaming: true, mode: _mode.id);
    final pregunta = ChatMessage.user(raw, contextLabel: adjuntos.join(' · '));

    if (overrideText == null) _input.clear();
    // Se reanuda tras un `await` al webview: la fase del scheduler es
    // impredecible, así que también aquí se difiere si hace falta.
    _safeSetState(() {
      _sending = true;
      _reintentoFormato = esReintento;
      _slashQuery = null;
      // Un turno nuevo invalida el plan anterior: si la respuesta vuelve a
      // ser un plan, la barra reaparece sola.
      _planDismissed = false;
      _startupStatus = 'Iniciando Copilot';
      _sentHistory.add(raw);
      _historyCursor = -1;
      _messages
        ..add(pregunta)
        ..add(answer);
    });
    _scrollToEnd(force: true);

    final prompt = _service.buildPrompt(
      question: question,
      code: code,
      // Van en todos los turnos: son dos líneas y mantienen al modelo
      // anclado a la regla concreta que se está editando.
      procedimiento: widget.procedimiento,
      ambiente: widget.ambiente,
      errores: errores,
      isFollowUp: resume,
      mode: _mode,
    );

    _sub = _service
        .askEvents(
          prompt,
          model: _model,
          sessionId: conv.sessionId,
          resume: resume,
          mode: _mode,
          effort: _effort,
          contextTier: _contextTier,
        )
        .listen(
          (event) => _onEvent(event, answer, conv),
          onError: (Object e) {
            // Si `_stop()` ya cerró el turno, lo que llega después es solo el
            // proceso muriendo: cancelar no debe pintar un error.
            if (!mounted || !_sending) return;
            _safeSetState(() {
              _messages.remove(answer);
              _messages.add(
                ChatMessage.error(
                  e is CopilotCliException ? e.message : e.toString(),
                ),
              );
              _sending = false;
              _startupStatus = null;
            });
            _scrollToEnd();
            unawaited(_persistConversations());
            // El servicio puede haber marcado la sesión como caducada a
            // partir del error real: se relee para mostrar la pantalla de
            // acceso.
            unawaited(_refreshAuth());
          },
          onDone: () {
            if (!mounted || !_sending) return;
            _safeSetState(() {
              answer.isStreaming = false;
              if (answer.content.trim().isEmpty) {
                _messages.remove(answer);
                _messages.add(
                  ChatMessage.error('Copilot no devolvió respuesta.'),
                );
              }
              _sending = false;
              _startupStatus = null;
            });
            _scrollToEnd();
            unawaited(_persistConversations());
            _inputFocus.requestFocus();
            // El turno acabó: si la respuesta trae el código final, va al
            // documento sin esperar a que nadie pulse nada.
            unawaited(_autoAplicar(answer));
          },
          cancelOnError: true,
        );
  }

  /// Traduce los eventos JSONL de la CLI a cambios de estado de la UI.
  void _onEvent(CopilotEvent event, ChatMessage answer, ChatConversation conv) {
    if (!mounted) return;
    switch (event.kind) {
      case CopilotEventKind.startup:
        _safeSetState(() {
          _startupStatus = event.detail ?? _startupStatus;
          if (event.model != null) answer.model = event.model;
        });

      case CopilotEventKind.turnStart:
        _safeSetState(() {
          _startupStatus = 'Generando respuesta';
          if (event.model != null) answer.model = event.model;
        });

      case CopilotEventKind.delta:
        _safeSetState(() {
          _startupStatus = null;
          answer.appendChunk(event.text ?? '');
        });
        _scrollToEnd();

      case CopilotEventKind.message:
        // El evento final trae el contenido completo: sustituye a los deltas
        // para evitar cualquier desajuste por fragmentos perdidos.
        final full = event.text;
        if (full != null && full.trim().isNotEmpty) {
          _safeSetState(() {
            answer.content = full;
            answer.model = event.model ?? answer.model;
          });
        }

      case CopilotEventKind.toolStart:
        _safeSetState(() {
          answer.toolCalls.add(ChatToolCall(event.toolName ?? 'herramienta'));
          _startupStatus = 'Usando ${event.toolName ?? "una herramienta"}';
        });

      case CopilotEventKind.toolEnd:
        _safeSetState(() {
          for (final t in answer.toolCalls) {
            if (t.name == event.toolName) t.finished = true;
          }
          _startupStatus = null;
        });

      case CopilotEventKind.result:
        // A partir de aquí la sesión existe en el almacén de la CLI y se
        // puede continuar con `--resume`.
        _safeSetState(() {
          conv.sessionId = event.sessionId ?? conv.sessionId;
          conv.sessionStarted = true;
          answer.premiumRequests = event.premiumRequests;
          answer.apiDurationMs = event.apiDurationMs;
        });

      case CopilotEventKind.unknown:
        break;
    }
  }

  /// UUID v4 para identificar la sesión de la CLI.
  String _newSessionUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int from, int to) => b
        .sublist(from, to)
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-'
        '${hex(10, 16)}';
  }

  /// Detiene la respuesta en curso.
  ///
  /// El orden importa y es contraintuitivo. `askEvents` es un generador
  /// `async*` que pasa la vida parado en `await for` esperando líneas de
  /// stdout; cancelar su suscripción **no devuelve el control hasta que el
  /// generador llega a un `yield`**, cosa que no ocurrirá mientras el modelo
  /// piense en silencio. Esperar ese `cancel()` antes de matar el proceso
  /// dejaba el botón colgado para siempre: por eso primero se refresca la UI,
  /// después se mata el proceso —que es lo que desatasca el `await for`— y la
  /// cancelación de la suscripción se lanza sin esperarla.
  Future<void> _stop() async {
    if (!_sending && _sub == null) return;

    _safeSetState(() {
      for (final m in _messages) {
        if (m.isStreaming && m.content.trim().isEmpty) {
          m.content = '_Cancelado._';
        }
        m.isStreaming = false;
      }
      _sending = false;
      _startupStatus = null;
    });

    final sub = _sub;
    _sub = null;
    await _service.cancel();
    unawaited(sub?.cancel());

    unawaited(_persistConversations());
    _inputFocus.requestFocus();
  }

  /// Nueva conversación: sesión limpia, como el botón «+» de VS Code.
  void _newChat() {
    unawaited(_stop());
    _safeSetState(() {
      if (_current.messages.isNotEmpty && !_conversations.contains(_current)) {
        _conversations.insert(0, _current);
      }
      _current = ChatConversation.nueva();
      _showHistory = false;
    });
    unawaited(_store.save(_conversations));
    _inputFocus.requestFocus();
  }

  void _openConversation(ChatConversation conv) {
    unawaited(_stop());
    _safeSetState(() {
      _current = conv;
      _showHistory = false;
    });
    _scrollToEnd(force: true);
  }

  Future<void> _deleteConversation(ChatConversation conv) async {
    _safeSetState(() {
      _conversations.remove(conv);
      if (_current == conv) _current = ChatConversation.nueva();
    });
    await _store.save(_conversations);
  }

  /// Reintenta la última pregunta descartando la respuesta anterior.
  void _retryLast() {
    final lastUser = _messages.lastWhere(
      (m) => m.isUser,
      orElse: () => ChatMessage.user(''),
    );
    if (lastUser.content.isEmpty) return;
    _safeSetState(() {
      // Se eliminan las respuestas posteriores a la última pregunta.
      final index = _messages.lastIndexOf(lastUser);
      _messages.removeRange(index, _messages.length);
    });
    unawaited(_send(overrideText: lastUser.content));
  }

  /// Recorre las preguntas anteriores con ↑/↓ cuando la caja está vacía o se
  /// está navegando el historial, igual que una terminal.
  void _recallHistory(int direction) {
    if (_sentHistory.isEmpty) return;
    if (_historyCursor == -1 && _input.text.trim().isNotEmpty) return;
    final next = _historyCursor == -1
        ? _sentHistory.length - 1
        : (_historyCursor + direction).clamp(0, _sentHistory.length - 1);
    _safeSetState(() {
      _historyCursor = next;
      _input.text = _sentHistory[next];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    });
  }

  // ── Construcción ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        _buildResizeHandle(cs),
        // Atajos del panel completo: funcionan tenga el foco la caja de
        // texto o cualquier otro control interno.
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
              if (_messages.isNotEmpty) _newChat();
            },
            const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
                _safeSetState(() => _showHistory = !_showHistory),
          },
          child: Container(
            width: _panelWidth,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1F1F) : cs.surfaceContainerLow,
            ),
            child: Column(
              children: [
                _buildHeader(cs, isDark),
                if (_showHistory)
                  Expanded(child: _buildHistoryList(cs, isDark))
                // Sin sesión no se muestra el chat: el panel entero se
                // reemplaza por la pantalla de acceso, así no se puede
                // escribir una pregunta que de todos modos fallaría.
                else if (_auth.state == CopilotAuthState.unknown)
                  const Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      ),
                    ),
                  )
                else if (!_auth.isReady)
                  Expanded(child: _buildAuthGate(cs, isDark))
                else ...[
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _messages.isEmpty
                              ? _buildEmptyState(cs)
                              : ListView.builder(
                                  controller: _scroll,
                                  // Sin padding lateral: cada mensaje ocupa
                                  // el ancho completo y trae su separador.
                                  padding: const EdgeInsets.only(bottom: 8),
                                  itemCount: _messages.length,
                                  itemBuilder: (_, i) =>
                                      _buildMessage(_messages[i], cs, isDark),
                                ),
                        ),
                        // Volver al final solo aparece si hace falta, como en
                        // los clientes de chat modernos.
                        if (!_stickToBottom && _messages.isNotEmpty)
                          Positioned(
                            right: 12,
                            bottom: 10,
                            child: _ScrollToEndBtn(
                              pending: _sending,
                              onTap: () => _scrollToEnd(force: true),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildComposer(cs, isDark),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Borde arrastrable para ajustar el ancho del panel.
  ///
  /// 400 px se quedan cortos para leer un bloque de PL/SQL sin scroll
  /// horizontal; el ancho elegido se recuerda entre sesiones.
  Widget _buildResizeHandle(ColorScheme cs) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _safeSetState(() {
          _panelWidth = (_panelWidth - d.delta.dx).clamp(
            _kMinWidth,
            _kMaxWidth,
          );
        }),
        onHorizontalDragEnd: (_) => unawaited(_savePrefs()),
        onDoubleTap: () {
          _safeSetState(() => _panelWidth = 400);
          unawaited(_savePrefs());
        },
        child: Tooltip(
          message: 'Arrastra para redimensionar · doble clic para restablecer',
          waitDuration: const Duration(milliseconds: 700),
          child: SizedBox(
            width: 5,
            height: double.infinity,
            child: Center(child: Container(width: 1, color: cs.outlineVariant)),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Container(
      height: 32,
      color: isDark ? const Color(0xFF181818) : cs.surfaceContainerHighest,
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 12, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _showHistory
                  ? 'HISTORIAL'
                  : (_messages.isEmpty ? 'CHAT' : _current.title.toUpperCase()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          _ChatIconBtn(
            icon: Icons.history,
            tooltip: 'Conversaciones anteriores',
            size: 14,
            active: _showHistory,
            onTap: () => _safeSetState(() => _showHistory = !_showHistory),
          ),
          _ChatIconBtn(
            icon: Icons.add,
            tooltip: 'Nueva conversación (Ctrl+L)',
            size: 14,
            onTap: _messages.isEmpty ? null : _newChat,
          ),
          _buildAccountMenu(cs),
          _buildOverflowMenu(cs),
          _ChatIconBtn(
            icon: Icons.close,
            tooltip: 'Cerrar panel',
            size: 13,
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  /// Menú «…» de la cabecera, como el del panel de chat de VS Code.
  Widget _buildOverflowMenu(ColorScheme cs) {
    final vacio = _messages.isEmpty;
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      icon: Icon(Icons.more_horiz, size: 14, color: cs.onSurfaceVariant),
      iconSize: 14,
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (value) async {
        switch (value) {
          case 'export':
            await Clipboard.setData(ClipboardData(text: _exportMarkdown()));
            if (mounted) AppToast.info('Conversación copiada en markdown');
          case 'clear':
            _clearConversation();
          case 'width':
            _safeSetState(() => _panelWidth = 400);
            await _savePrefs();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'export',
          height: 34,
          enabled: !vacio,
          child: const Row(
            children: [
              Icon(Icons.ios_share, size: 14),
              SizedBox(width: 8),
              Text(
                'Copiar conversación (markdown)',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          height: 34,
          enabled: !vacio,
          child: const Row(
            children: [
              Icon(Icons.cleaning_services_outlined, size: 14),
              SizedBox(width: 8),
              Text('Vaciar esta conversación', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem(
          value: 'width',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.settings_ethernet, size: 14),
              SizedBox(width: 8),
              Text('Restablecer el ancho', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  /// Vuelca el hilo a markdown, para pegarlo en una incidencia o en un PR.
  String _exportMarkdown() {
    final b = StringBuffer('# ${_current.title}\n\n');
    for (final m in _messages) {
      b
        ..writeln(m.isUser ? '## Pregunta' : '## Copilot')
        ..writeln()
        ..writeln(m.content.trim())
        ..writeln();
    }
    return b.toString();
  }

  /// Borra los mensajes conservando la conversación: la sesión de la CLI ya
  /// no vale, así que se abre una nueva.
  void _clearConversation() {
    unawaited(_stop());
    _safeSetState(() {
      _conversations.remove(_current);
      _current = ChatConversation.nueva();
    });
    unawaited(_store.save(_conversations));
    _inputFocus.requestFocus();
  }

  /// Lista de conversaciones guardadas, como el desplegable «Show Chats» de
  /// VS Code, con filtro por título y contenido.
  Widget _buildHistoryList(ColorScheme cs, bool isDark) {
    final query = _historyQuery.toLowerCase();
    final items = query.isEmpty
        ? _conversations
        : _conversations
              .where(
                (c) =>
                    c.title.toLowerCase().contains(query) ||
                    c.messages.any(
                      (m) => m.content.toLowerCase().contains(query),
                    ),
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            controller: _historySearch,
            style: const TextStyle(fontSize: 11),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar en las conversaciones',
              hintStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              prefixIcon: Icon(
                Icons.search,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              suffixIcon: _historyQuery.isEmpty
                  ? null
                  : _ChatIconBtn(
                      icon: Icons.close,
                      tooltip: 'Limpiar',
                      size: 12,
                      onTap: _historySearch.clear,
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 26,
                minHeight: 26,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant, width: 0.6),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant, width: 0.6),
              ),
            ),
          ),
        ),
        if (items.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _conversations.isEmpty
                    ? 'Todavía no hay conversaciones guardadas'
                    : 'Ninguna conversación coincide',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final c = items[i];
                final active = c == _current;
                return _HoverHighlight(
                  builder: (hovered) => InkWell(
                    onTap: () => _openConversation(c),
                    child: Container(
                      color: active
                          ? cs.primaryContainer.withValues(alpha: 0.2)
                          : hovered
                          ? cs.onSurface.withValues(alpha: 0.05)
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 12,
                            color: active ? cs.primary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Text(
                                  '${c.messages.length} mensajes · '
                                  '${_relativeDate(c.updatedAt)}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Eliminar solo al pasar por encima: evita borrados
                          // accidentales al recorrer la lista.
                          Opacity(
                            opacity: hovered ? 1 : 0,
                            child: _ChatIconBtn(
                              icon: Icons.delete_outline,
                              tooltip: 'Eliminar',
                              size: 12,
                              onTap: hovered
                                  ? () => unawaited(_confirmDelete(c))
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Borrar una conversación es irreversible: se confirma antes.
  Future<void> _confirmDelete(ChatConversation conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Eliminar conversación',
          style: TextStyle(fontSize: 14),
        ),
        content: Text(
          '«${conv.title}» se borrará definitivamente.',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok ?? false) await _deleteConversation(conv);
  }

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  /// Menú de cuenta: permite (re)autenticarse en cualquier momento, no solo
  /// cuando la app detecta que falta sesión.
  Widget _buildAccountMenu(ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta de GitHub',
      padding: EdgeInsets.zero,
      splashRadius: 14,
      position: PopupMenuPosition.under,
      icon: Icon(
        _auth.isReady
            ? Icons.account_circle_outlined
            : Icons.no_accounts_outlined,
        size: 14,
        color: _auth.isReady ? cs.onSurfaceVariant : cs.error,
      ),
      iconSize: 14,
      constraints: const BoxConstraints(minWidth: 230),
      onSelected: (value) async {
        switch (value) {
          case 'web':
            await _service.openLoginTerminal();
            if (mounted) {
              AppToast.info('Autoriza la sesión en el navegador y vuelve aquí');
            }
          case 'device':
            await _service.openLoginTerminal(deviceCode: true);
            if (mounted) {
              AppToast.info('Introduce el código que muestra la consola');
            }
          case 'verify':
            await _verifySession();
          case 'check':
            await _refreshAuth(force: true);
            if (mounted) {
              AppToast.info(
                _auth.isReady
                    ? 'Copilot listo (${_auth.executablePath ?? "CLI"})'
                    : _auth.detail ?? 'Sin sesión',
              );
            }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          height: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _evidence.account != null
                    ? 'Cuenta: ${_evidence.account}'
                    : 'Cuenta no detectada',
                style: const TextStyle(fontSize: 10.5),
              ),
              Text(
                'Sesión ${_lastVerifiedLabel()}',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem(
          value: 'verify',
          height: 34,
          child: Row(
            children: [
              Icon(
                _verifying ? Icons.hourglass_top : Icons.verified_outlined,
                size: 14,
              ),
              const SizedBox(width: 8),
              const Text(
                'Verificar sesión (consulta real)',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'web',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.open_in_browser, size: 14),
              SizedBox(width: 8),
              Text(
                'Iniciar sesión (navegador)',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'device',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.password_outlined, size: 14),
              SizedBox(width: 8),
              Text('Iniciar sesión (código)', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'check',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.refresh, size: 14),
              SizedBox(width: 8),
              Text('Releer estado local', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  /// Pantalla de acceso que sustituye al chat mientras no haya sesión válida.
  Widget _buildAuthGate(ColorScheme cs, bool isDark) {
    final state = _auth.state;
    final needsInstall = state == CopilotAuthState.notInstalled;
    final canLogin = state == CopilotAuthState.notLoggedIn;
    final blocked = state == CopilotAuthState.forbidden;

    final (icon, title) = switch (state) {
      CopilotAuthState.notInstalled => (
        Icons.download_for_offline_outlined,
        'Copilot CLI no instalada',
      ),
      CopilotAuthState.forbidden => (
        Icons.gpp_maybe_outlined,
        'Acceso bloqueado por la organización',
      ),
      _ => (Icons.lock_outline, 'Inicia sesión en GitHub'),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: blocked || needsInstall
                  ? cs.errorContainer.withValues(alpha: 0.35)
                  : cs.primaryContainer.withValues(alpha: 0.35),
            ),
            child: Icon(
              icon,
              size: 22,
              color: blocked || needsInstall ? cs.error : cs.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _auth.detail ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (canLogin) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await _service.openLoginTerminal();
                  if (mounted) {
                    AppToast.info(
                      'Autoriza la sesión en el navegador y vuelve aquí',
                    );
                  }
                },
                icon: const Icon(Icons.open_in_browser, size: 15),
                label: const Text(
                  'Iniciar sesión con GitHub',
                  style: TextStyle(fontSize: 11.5),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  await _service.openLoginTerminal(deviceCode: true);
                  if (mounted) {
                    AppToast.info('Introduce el código que muestra la consola');
                  }
                },
                icon: const Icon(Icons.password_outlined, size: 14),
                label: const Text(
                  'Usar código de dispositivo',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
          if (needsInstall)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: 'npm install -g @github/copilot'),
                  );
                  AppToast.info('Comando copiado al portapapeles');
                },
                icon: const Icon(Icons.copy_all_outlined, size: 15),
                label: const Text(
                  'Copiar comando de instalación',
                  style: TextStyle(fontSize: 11.5),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          const SizedBox(height: 14),
          _buildEvidenceBox(cs, isDark),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _verifying ? null : _verifySession,
            icon: _verifying
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : const Icon(Icons.verified_outlined, size: 14),
            label: Text(
              _verifying ? 'Verificando…' : 'Ya inicié sesión — verificar',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Muestra en qué se basa la app para decidir el estado de la sesión.
  /// Sin esto, un "sin sesión" resulta opaco y no hay forma de diagnosticarlo.
  Widget _buildEvidenceBox(ColorScheme cs, bool isDark) {
    final items = <(bool, String)>[
      (
        _auth.executablePath != null,
        _auth.executablePath != null ? 'CLI detectada' : 'CLI no encontrada',
      ),
      (
        _evidence.hasCliConfig,
        _evidence.hasCliConfig
            ? 'Configuración local presente'
            : 'Sin configuración local (~/.copilot)',
      ),
      (
        _evidence.credentialEntries > 0,
        _evidence.credentialEntries > 0
            ? '${_evidence.credentialEntries} credenciales en el almacén'
            : 'Sin credenciales en el almacén',
      ),
      if (_evidence.account != null) (true, 'Cuenta: ${_evidence.account}'),
      if (_evidence.hasEnvToken) (true, 'Token en variables de entorno'),
      (_evidence.lastVerifiedOk != null, 'Sesión ${_lastVerifiedLabel()}'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DIAGNÓSTICO',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 5),
          for (final (ok, label) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                    size: 11,
                    color: ok ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 9.5, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Pantalla inicial: bienvenida + sugerencias + comandos, como el
  /// *welcome view* de Copilot Chat.
  Widget _buildEmptyState(ColorScheme cs) {
    // Preguntas de arranque: bajan la barrera de entrada mucho más que una
    // caja vacía, y están redactadas para el dominio de reglas PL/SQL.
    final sugerencias = <(IconData, String)>[
      (Icons.help_outline, '¿Qué hace esta regla, paso a paso?'),
      (Icons.bug_report_outlined, 'Revisa los errores de compilación actuales'),
      (Icons.speed_outlined, '¿Cómo puedo optimizar este bloque?'),
      (Icons.rule_folder_outlined, 'Explica las tablas y datos que consulta'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      children: [
        Icon(
          Icons.auto_awesome,
          size: 28,
          color: cs.primary.withValues(alpha: 0.75),
        ),
        const SizedBox(height: 12),
        Text(
          'Pregunta a Copilot',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Copilot conoce el procedimiento abierto, el ambiente y los errores '
          'de compilación actuales.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.45,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _buildSectionLabel('SUGERENCIAS', cs),
        const SizedBox(height: 6),
        for (final (icon, texto) in sugerencias)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _HoverHighlight(
              builder: (hovered) => InkWell(
                onTap: () => unawaited(_send(overrideText: texto)),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: hovered
                        ? cs.primaryContainer.withValues(alpha: 0.22)
                        : null,
                    border: Border.all(
                      color: hovered
                          ? cs.primary.withValues(alpha: 0.45)
                          : cs.outlineVariant,
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 13, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          texto,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.3,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_outward,
                        size: 11,
                        color: hovered
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        _buildSectionLabel('COMANDOS', cs),
        const SizedBox(height: 6),
        for (final c in kChatSlashCommands)
          _HoverHighlight(
            builder: (hovered) => InkWell(
              onTap: () => _applySlashCommand(c),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: hovered ? cs.onSurface.withValues(alpha: 0.055) : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '/${c.name}',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.description,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionLabel(String text, ColorScheme cs) => Text(
    text,
    style: TextStyle(
      fontSize: 8.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
    ),
  );

  void _applySlashCommand(ChatSlashCommand c) {
    _input.text = '/${c.name} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _safeSetState(() => _slashQuery = null);
    _inputFocus.requestFocus();
  }

  /// Mensaje al estilo VS Code: sin burbujas, con avatar + nombre y la
  /// respuesta a ancho completo. Las acciones aparecen al pasar el puntero
  /// para que la conversación se lea sin ruido.
  Widget _buildMessage(ChatMessage m, ColorScheme cs, bool isDark) {
    final isLast = _messages.isNotEmpty && _messages.last == m;
    final hovered = identical(_hovered, m);

    return MouseRegion(
      onEnter: (_) => _safeSetState(() => _hovered = m),
      onExit: (_) {
        if (identical(_hovered, m)) _safeSetState(() => _hovered = null);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: m.isUser
              ? (isDark ? const Color(0xFF252526) : cs.surfaceContainerLowest)
              : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.45),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: m.isError
                        ? cs.errorContainer
                        : m.isUser
                        ? cs.secondaryContainer
                        : cs.primaryContainer,
                  ),
                  child: Icon(
                    m.isUser
                        ? Icons.person
                        : m.isError
                        ? Icons.priority_high
                        : Icons.auto_awesome,
                    size: 10,
                    color: m.isError
                        ? cs.error
                        : m.isUser
                        ? cs.onSecondaryContainer
                        : cs.primary,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  m.isUser ? 'Tú' : 'GitHub Copilot',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                // La barra de acciones ocupa sitio siempre (opacidad 0) para
                // que el texto no se mueva al entrar el puntero.
                AnimatedOpacity(
                  opacity: hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (m.content.trim().isNotEmpty && !m.isStreaming)
                        _ChatIconBtn(
                          icon: Icons.content_copy_outlined,
                          tooltip: m.isUser
                              ? 'Copiar pregunta'
                              : 'Copiar respuesta',
                          size: 11,
                          onTap: hovered
                              ? () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: m.content),
                                  );
                                  AppToast.info('Copiado al portapapeles');
                                }
                              : null,
                        ),
                      if (m.isUser && !_sending)
                        _ChatIconBtn(
                          icon: Icons.edit_outlined,
                          tooltip: 'Editar y reenviar',
                          size: 11,
                          onTap: hovered ? () => _editMessage(m) : null,
                        ),
                      if (!m.isUser && !m.isStreaming && isLast && !_sending)
                        _ChatIconBtn(
                          icon: Icons.refresh,
                          tooltip: 'Reintentar',
                          size: 11,
                          onTap: hovered ? _retryLast : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (m.isUser && m.contextLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 3),
                child: Row(
                  children: [
                    Icon(
                      Icons.attachment,
                      size: 9,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        m.contextLabel!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in m.toolCalls) _buildToolChip(t, cs),
                  if (m.isPending)
                    _buildThinking(cs)
                  else
                    _MarkdownView(
                      content: m.content,
                      isError: m.isError,
                      isStreaming: m.isStreaming,
                      onCopy: (code) async {
                        await Clipboard.setData(ClipboardData(text: code));
                        AppToast.info('Copiado al portapapeles');
                      },
                      onInsert: (code) => unawaited(widget.onInsertCode(code)),
                    ),
                  if (m.applied) _buildAppliedBanner(cs),
                  if (!m.isUser && !m.isStreaming) _buildMessageFooter(m, cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Devuelve una pregunta al compositor para retocarla y volver a enviarla.
  void _editMessage(ChatMessage m) {
    _input.text = m.content;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _inputFocus.requestFocus();
  }

  /// Indicador de trabajo con la fase real informada por la CLI.
  Widget _buildThinking(ColorScheme cs) {
    return Row(
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.4, color: cs.primary),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            '${_startupStatus ?? "Pensando"}…',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Contador en vivo: una espera con cifra se tolera mucho mejor que
        // una espera muda, y delata al modelo que se ha quedado colgado.
        _ElapsedLabel(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        _ChatIconBtn(
          icon: Icons.stop_circle_outlined,
          tooltip: 'Detener (Esc)',
          size: 12,
          onTap: () => unawaited(_stop()),
        ),
      ],
    );
  }

  /// Fila de herramienta invocada, como el bloque «Ran …» de VS Code.
  Widget _buildToolChip(ChatToolCall t, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          border: Border.all(color: cs.outlineVariant, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.finished)
              Icon(Icons.check, size: 10, color: cs.primary)
            else
              SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.3,
                  color: cs.primary,
                ),
              ),
            const SizedBox(width: 6),
            Text(
              t.finished ? 'Ejecutó' : 'Ejecutando',
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                t.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aviso de que el código ya está en el documento.
  ///
  /// Escribir sin preguntar solo es aceptable si queda claro que ocurrió y
  /// cómo revertirlo; de ahí el recordatorio de Ctrl+Z.
  Widget _buildAppliedBanner(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.35),
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 12, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Aplicado al documento',
                style: TextStyle(fontSize: 10, color: cs.onSurface),
              ),
            ),
            Text(
              'Ctrl+Z para deshacer',
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pie con el modelo y el consumo real del turno, como el detalle de VS Code.
  Widget _buildMessageFooter(ChatMessage m, ColorScheme cs) {
    final parts = <String>[
      if (m.model != null) m.model!,
      if (m.apiDurationMs != null)
        '${(m.apiDurationMs! / 1000).toStringAsFixed(1)} s',
      if (m.premiumRequests != null && m.premiumRequests! > 0)
        '${m.premiumRequests} petición premium',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        parts.join(' · '),
        style: TextStyle(
          fontSize: 8.5,
          color: cs.onSurfaceVariant.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  /// `true` si el editor tiene errores que adjuntar ahora mismo.
  bool get _hayErrores => widget.getErrors().trim().isNotEmpty;

  /// Etiqueta del chip del documento: `DR_REGLA` o `DR_REGLA:112-140`.
  String _etiquetaDocumento(EditorSelection? sel) {
    final base = widget.procedimiento.isEmpty ? 'Editor' : widget.procedimiento;
    return sel == null ? base : sel.label(base);
  }

  /// Relee la selección del editor para mantener el chip al día.
  ///
  /// Monaco no notifica los cambios de selección a Dart, así que se consulta
  /// en los momentos en que el usuario mira el chip: al entrar el puntero en
  /// el compositor y al enfocar la caja de texto. Sondear con un temporizador
  /// costaría un salto al webview varias veces por segundo para nada.
  Future<void> _refrescarSeleccion() async {
    final sel = await widget.getSelection();
    if (!mounted) return;
    final cambio =
        sel?.startLine != _seleccion?.startLine ||
        sel?.endLine != _seleccion?.endLine;
    if (cambio) _safeSetState(() => _seleccion = sel);
  }

  /// Contexto que se puede volver a adjuntar desde «Añadir contexto».
  ///
  /// El documento abierto no aparece nunca aquí: va siempre adjunto y no se
  /// puede retirar.
  List<(String, IconData, String)> _contextoDisponible() => [
    if (!_includeErrors && _hayErrores)
      ('errors', Icons.error_outline, 'Errores actuales'),
  ];

  /// Caja de entrada unificada al estilo VS Code: chips de contexto arriba,
  /// texto en el centro y barra inferior con modelo y botón de envío.
  Widget _buildComposer(ColorScheme cs, bool isDark) {
    final boxColor = isDark
        ? const Color(0xFF1B1B1B)
        : cs.surfaceContainerLowest;
    final adjuntos = _chipsAdjuntos(cs);
    // La barra sale en cuanto un turno en modo Plan termina, tenga o no pasos
    // reconocibles: exigir que el parser acertara con el formato dejaba al
    // usuario sin botón justo cuando más lo necesita.
    final hayPlan = _planMessage != null && !_planDismissed;
    // La franja de progreso sí depende de haber podido leer los pasos.
    final pasos = _plan;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: MouseRegion(
        onEnter: (_) => unawaited(_refrescarSeleccion()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_slashQuery != null) _buildSlashPopup(cs, isDark),
            if (_erroresIntroducidos != null) _buildErroresBanner(cs),
            if (hayPlan) _buildPlanActions(cs),
            Container(
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _inputFocus.hasFocus
                      ? cs.primary.withValues(alpha: 0.8)
                      : cs.outlineVariant,
                  width: _inputFocus.hasFocus ? 1 : 0.6,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Franja de consejo, como el «Tip:» que VS Code muestra sobre
                  // la caja. Se descarta para siempre en cuanto estorba.
                  if (hayPlan && pasos.isNotEmpty)
                    _buildPlanStrip(cs)
                  else if (_showTip && !hayPlan)
                    _buildTipStrip(cs),
                  // Fila de adjuntos: solo lo que realmente viaja en el prompt.
                  if (adjuntos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: adjuntos,
                      ),
                    ),
                  // Entrada de texto con navegación de teclado al estilo VS Code.
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (_slashQuery != null) {
                          _acceptSlashHighlighted();
                        } else {
                          unawaited(_send());
                        }
                      },
                      const SingleActivator(LogicalKeyboardKey.tab): () {
                        if (_slashQuery != null) _acceptSlashHighlighted();
                      },
                      const SingleActivator(LogicalKeyboardKey.escape): () {
                        if (_slashQuery != null) {
                          _safeSetState(() => _slashQuery = null);
                        } else if (_sending) {
                          unawaited(_stop());
                        }
                      },
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                        if (_slashQuery != null) {
                          _moveSlashHighlight(1);
                        } else {
                          _recallHistory(1);
                        }
                      },
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                        if (_slashQuery != null) {
                          _moveSlashHighlight(-1);
                        } else {
                          _recallHistory(-1);
                        }
                      },
                    },
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 3,
                      maxLines: 8,
                      enabled: !_sending,
                      style: const TextStyle(fontSize: 11.5, height: 1.35),
                      decoration: InputDecoration(
                        hintText: 'Describe qué necesitas',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(9, 9, 9, 4),
                      ),
                    ),
                  ),
                  // Barra de herramientas: contexto, comandos, modo, modelo,
                  // ajuste fino y envío. Todos los controles son planos, sin
                  // relleno, como en la caja de VS Code.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Row(
                      children: [
                        _buildAddContextBtn(cs),
                        _ChatIconBtn(
                          icon: Icons.bolt_outlined,
                          tooltip: 'Comandos sobre el procedimiento (/)',
                          size: 14,
                          active: _slashQuery != null,
                          onTap: _openSlashMenu,
                        ),
                        const SizedBox(width: 2),
                        _buildModePicker(cs),
                        Flexible(child: _buildModelPicker(cs)),
                        _buildTuningPicker(cs),
                        _buildSettingsButton(cs),
                        const Spacer(),
                        if (_sending)
                          _RoundActionBtn(
                            icon: Icons.stop_rounded,
                            tooltip: 'Detener (Esc)',
                            background: cs.error,
                            foreground: cs.onError,
                            onTap: _stop,
                          )
                        // Sin texto el botón no se rellena: queda como una
                        // flecha apagada, igual que en VS Code, porque enviar
                        // en vacío no hace nada.
                        else if (!_hasText)
                          _ChatIconBtn(
                            icon: Icons.arrow_upward_rounded,
                            tooltip: 'Escribe una pregunta para enviar',
                            size: 15,
                            onTap: null,
                          )
                        else
                          _RoundActionBtn(
                            icon: Icons.arrow_upward_rounded,
                            tooltip: 'Enviar · Enter',
                            background: cs.primary,
                            foreground: cs.onPrimary,
                            onTap: () => unawaited(_send()),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Pie de estado fuera de la caja, como el «Local · Default
            // permissions» de VS Code: dice dónde se ejecuta y con qué permisos.
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
              child: Row(
                children: [
                  _StatusPill(
                    icon: Icons.dns_outlined,
                    label: widget.ambiente,
                    tooltip: 'Ambiente Oracle sobre el que se responde',
                  ),
                  const SizedBox(width: 10),
                  _StatusPill(
                    icon: Icons.gpp_maybe_outlined,
                    label: _mode == CopilotChatMode.agent
                        ? 'Solo consulta'
                        : 'Solo lectura',
                    // Coloreado y pulsable, como el «Allow all» de VS Code:
                    // el alcance de los permisos es justo lo que hay que poder
                    // consultar de un vistazo.
                    accent: true,
                    onTap: _mostrarPermisos,
                  ),
                  const Spacer(),
                  if (_sending)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.3,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    )
                  else
                    Text(
                      'Enter envía',
                      style: TextStyle(
                        fontSize: 8.5,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
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

  /// Aviso de que el cambio aplicado rompió algo, con la corrección a un clic.
  Widget _buildErroresBanner(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: cs.error.withValues(alpha: 0.4),
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 13, color: cs.error),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'El cambio dejó errores en el editor',
                style: TextStyle(fontSize: 10, color: cs.onSurface),
              ),
            ),
            _PlanActionBtn(
              label: 'Corregir',
              onTap: _sending ? null : _corregirErroresIntroducidos,
            ),
            const SizedBox(width: 4),
            _ChatIconBtn(
              icon: Icons.close,
              tooltip: 'Ignorar',
              size: 12,
              onTap: () => _safeSetState(() => _erroresIntroducidos = null),
            ),
          ],
        ),
      ),
    );
  }

  /// Chips del contexto que se adjunta realmente al prompt.
  List<Widget> _chipsAdjuntos(ColorScheme cs) => [
    // El documento abierto es contexto fijo: sin × y siempre presente.
    _ContextChip(
      icon: Icons.description_outlined,
      label: _etiquetaDocumento(_seleccion),
      active: true,
      pinned: true,
      tooltip: _seleccion == null
          ? 'Siempre adjunto: se envía el documento completo. Selecciona '
                'líneas en el editor para acotar el envío.'
          : 'Se enviarán solo las ${_seleccion!.lineCount} líneas '
                'seleccionadas',
    ),
    if (_includeErrors && _hayErrores)
      _ContextChip(
        icon: Icons.error_outline,
        label: 'errores',
        active: true,
        warn: true,
        tooltip: 'Se envía el resumen de errores actuales',
        onRemove: () {
          setState(() => _includeErrors = false);
          unawaited(_savePrefs());
        },
      ),
    if (_current.sessionStarted)
      _ContextChip(
        icon: Icons.link,
        label: 'hilo activo',
        active: true,
        tooltip:
            'Copilot recuerda el contexto de esta conversación '
            '(sesión reanudada)',
      ),
  ];

  /// Franja de consejo sobre los comandos, al estilo del «Tip:» de VS Code.
  Widget _buildTipStrip(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.35,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                ),
                children: [
                  const TextSpan(text: 'Consejo: escribe '),
                  TextSpan(
                    text: '/',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const TextSpan(
                    text: ' para lanzar un comando sobre el procedimiento.',
                  ),
                ],
              ),
            ),
          ),
          _ChatIconBtn(
            icon: Icons.close,
            tooltip: 'No volver a mostrar',
            size: 11,
            onTap: _dismissTip,
          ),
        ],
      ),
    );
  }

  /// Explica con qué permisos corre el agente.
  ///
  /// El pie dice «Solo lectura», pero eso no basta: hay que poder ver la
  /// lista exacta de lo que está denegado sin salir del panel.
  void _mostrarPermisos() {
    final agente = _mode == CopilotChatMode.agent;
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Permisos del agente',
          style: TextStyle(fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'En todos los modos están denegados:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final t in const [
              'shell — no ejecuta comandos del sistema',
              'write — no escribe archivos en disco',
              'url — no sale a internet',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $t', style: const TextStyle(fontSize: 11.5)),
              ),
            const SizedBox(height: 8),
            Text(
              agente
                  ? 'En modo Agente puede consultar únicamente estos '
                        'servidores MCP, y solo para leer:'
                  : 'En este modo los servidores MCP están apagados: la '
                        'respuesta sale solo del contexto que se envía.',
              style: const TextStyle(fontSize: 11.5, height: 1.35),
            ),
            if (agente) ...[
              const SizedBox(height: 6),
              for (final s in const [
                'sqlcl — esquema y datos de Oracle',
                'mcp-sirweb — procedimientos, eventos y tablas',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('• $s', style: const TextStyle(fontSize: 11.5)),
                ),
              const SizedBox(height: 4),
              Text(
                'Cualquier otro servidor de tu configuración queda apagado.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.storage_outlined, size: 14, color: cs.error),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Nunca escribe en la base de datos. No crea ni actualiza '
                      'procedimientos, no compila objetos y no ejecuta DML ni '
                      'DDL. Los cambios se aplican en el editor y los guardas '
                      'tú.',
                      style: TextStyle(fontSize: 11.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Abre el listado de comandos sin obligar a teclear la barra.
  void _openSlashMenu() {
    _inputFocus.requestFocus();
    if (_input.text.trim().isEmpty) {
      _input.text = '/';
      _input.selection = TextSelection.collapsed(offset: 1);
    }
  }

  // ── Continuar desde el plan ───────────────────────────────────────────────

  /// Pide a Copilot que ejecute el plan y devuelva el código final.
  ///
  /// La instrucción es deliberadamente estricta —un único bloque, sin
  /// explicaciones— porque la respuesta se va a aplicar sobre el documento:
  /// si el modelo intercala prosa entre fragmentos, no hay forma de saber
  /// cuál es el procedimiento resultante.
  void _startImplementation({bool onlyCurrentStep = false}) {
    final plan = _plan;
    final paso = plan.isEmpty ? 0 : _planStep.clamp(0, plan.length - 1);
    final alcance = (onlyCurrentStep && plan.isNotEmpty)
        ? 'Implementa ÚNICAMENTE el paso ${paso + 1} del plan '
              '(«${plan.steps[paso].title}»). Deja el resto igual.'
        : 'Implementa el plan que acabas de describir, completo y en orden.';

    // Se cambia a modo Agente: escribir el código ya no es planificar, y en
    // Plan la CLI vuelve a redactar pasos en vez de producir el resultado.
    _safeSetState(() => _mode = CopilotChatMode.agent);
    unawaited(_savePrefs());

    unawaited(
      _send(
        overrideText:
            '$alcance\n\n'
            'Devuelve el procedimiento resultante COMPLETO en un único bloque '
            '```sql, listo para reemplazar el documento. No añadas '
            'explicaciones fuera del bloque.',
      ),
    );
  }

  /// Aplica al documento el último bloque de código de la conversación.
  Future<void> _openInEditor() async {
    final ultima = _messages.lastWhere(
      (m) => !m.isUser && !m.isError,
      orElse: () => ChatMessage.assistant(''),
    );
    final bloques = parseEditBlocks(ultima.content);
    if (bloques.isNotEmpty) {
      final ok = await widget.onApplyEdits(bloques);
      if (ok && mounted) _safeSetState(() => ultima.applied = true);
      return;
    }

    final code = _ultimoBloqueDeCodigo();
    if (code == null) {
      AppToast.warning('Todavía no hay código que aplicar');
      return;
    }
    final aplicado = await widget.onApplyCode(code);
    if (aplicado && mounted) {
      _safeSetState(() {
        if (_planStep < _plan.length - 1) _planStep++;
      });
    }
  }

  /// Escribe en el documento el código de [respuesta], si procede.
  ///
  /// No se aplica todo a ciegas: [decideAutoApply] descarta los bloques que
  /// vienen recortados (`-- ...`) o que son un fragmento suelto cuando no hay
  /// selección, porque reemplazar la regla entera con ellos perdería código.
  /// En esos casos queda el botón manual.
  Future<void> _autoAplicar(ChatMessage respuesta) async {
    if (!_autoApply || respuesta.isError) return;

    // Camino preferente: ediciones ancladas. Son deterministas y no dependen
    // de que el modelo reproduzca el procedimiento entero sin recortarlo.
    final erroresPrevios = widget.getErrors();

    final bloques = parseEditBlocks(respuesta.content);
    if (bloques.isNotEmpty) {
      final ok = await widget.onApplyEdits(bloques);
      if (ok && mounted) {
        _safeSetState(() {
          respuesta.applied = true;
          if (_planStep < _plan.length - 1) _planStep++;
        });
        unawaited(_verificarCambio(erroresPrevios));
      }
      return;
    }

    final code = ultimoBloqueDeCodigo(respuesta.content);
    if (code == null) {
      _pedirFormatoDeEdicion();
      return;
    }

    final seleccion = await widget.getSelection();
    if (!mounted) return;

    final decision = decideAutoApply(code, haySeleccion: seleccion != null);
    if (decision == AutoApplyDecision.ask) {
      // El bloque no era aplicable (venia recortado o era un fragmento):
      // se pide la edición anclada, que no tiene ese problema.
      _pedirFormatoDeEdicion();
      return;
    }

    final aplicado = await widget.onApplyCode(code, confirmar: false);
    if (!aplicado || !mounted) return;

    _safeSetState(() {
      respuesta.applied = true;
      if (_planStep < _plan.length - 1) _planStep++;
    });
    unawaited(_verificarCambio(erroresPrevios));
  }

  /// Comprueba si el cambio recin aplicado introdujo errores.
  ///
  /// El chequeo de PL/SQL del editor corre con retardo tras cada edición, así
  /// que se espera a que termine antes de leer el resultado.
  Future<void> _verificarCambio(String erroresPrevios) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final ahora = widget.getErrors().trim();
    // Solo interesa lo que NO estaba antes: los errores preexistentes no los
    // causó este cambio.
    if (ahora.isEmpty || ahora == erroresPrevios.trim()) {
      _safeSetState(() => _erroresIntroducidos = null);
      return;
    }
    _safeSetState(() => _erroresIntroducidos = ahora);
  }

  /// Manda a Copilot los errores que él mismo introdujo.
  void _corregirErroresIntroducidos() {
    final errores = _erroresIntroducidos;
    if (errores == null) return;
    _safeSetState(() => _erroresIntroducidos = null);
    unawaited(
      _send(
        overrideText:
            'El cambio que acabas de aplicar dejó estos errores. '
            'Corrígelos con ediciones ancladas:\n$errores',
      ),
    );
  }

  /// Pide al modelo que devuelva la edición en el formato anclado.
  ///
  /// Es el sustituto del *function calling* que sí tienen los agentes de
  /// IDE: si la respuesta no se puede aplicar, se reclama la forma correcta
  /// una única vez.
  void _pedirFormatoDeEdicion() {
    if (_reintentoFormato || _sending) return;
    unawaited(
      _send(
        esReintento: true,
        overrideText:
            'Esa respuesta no se puede aplicar al documento. Repite el '
            'cambio usando SOLO ediciones ancladas, sin explicaciones:\n'
            '$kBuscarMarker\n(líneas exactas actuales)\n$kSepararMarker\n'
            '(líneas nuevas)\n$kReemplazarMarker',
      ),
    );
  }

  /// Último bloque ```` ``` ```` de la última respuesta del asistente.
  ///
  /// Se coge el último y no el primero porque, cuando el modelo enseña el
  /// «antes» y el «después», el resultado final va siempre al cierre.
  String? _ultimoBloqueDeCodigo() {
    for (final m in _messages.reversed) {
      if (m.isUser || m.isError) continue;
      final bloques = parseMarkdownBlocks(
        m.content,
      ).where((b) => b.isCode && b.text.trim().isNotEmpty).toList();
      if (bloques.isNotEmpty) return bloques.last.text;
    }
    return null;
  }

  /// Barra «Continuar desde el plan», sobre la caja de entrada.
  ///
  /// Aparece solo cuando el último turno fue un plan terminado: es el momento
  /// exacto en que el usuario decide si ejecutarlo, y tenerla siempre visible
  /// la convertiría en ruido.
  Widget _buildPlanActions(ColorScheme cs) {
    final plan = _plan;
    final hayCodigo = _ultimoBloqueDeCodigo() != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Continuar desde el plan',
            style: TextStyle(
              fontSize: 9.5,
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PlanActionBtn(
                label: 'Implementar',
                onTap: _sending ? null : () => _startImplementation(),
                // El desplegable evita multiplicar botones para variantes que
                // se usan de vez en cuando.
                menu: [
                  ('Implementar el plan completo', _startImplementation),
                  if (plan.length > 1)
                    (
                      'Implementar solo el paso ${_planStep + 1}',
                      () => _startImplementation(onlyCurrentStep: true),
                    ),
                ],
              ),
              _PlanActionBtn(
                label: 'Aplicar al documento',
                enabled: hayCodigo && !_sending,
                tooltip: hayCodigo
                    ? 'Reemplaza la selección o el documento abierto'
                    : 'Aún no hay ningún bloque de código en la respuesta',
                onTap: () => unawaited(_openInEditor()),
              ),
              _PlanActionBtn(
                label: 'Descartar',
                tooltip: 'Oculta estas acciones y sigue conversando',
                onTap: () => _safeSetState(() => _planDismissed = true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Fila del paso actual dentro de la caja, como la de VS Code.
  Widget _buildPlanStrip(ColorScheme cs) {
    final plan = _plan;
    final paso = _planStep.clamp(0, plan.length - 1);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _safeSetState(() => _planExpanded = !_planExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Row(
                children: [
                  Icon(
                    _planExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.radio_button_unchecked,
                    size: 10,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      plan.steps[paso].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: cs.onSurface),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${paso + 1}/${plan.length})',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 2),
                  _ChatIconBtn(
                    icon: _planExpanded
                        ? Icons.unfold_less
                        : Icons.format_list_numbered,
                    tooltip: _planExpanded
                        ? 'Plegar los pasos'
                        : 'Ver todos los pasos',
                    size: 12,
                    onTap: () =>
                        _safeSetState(() => _planExpanded = !_planExpanded),
                  ),
                ],
              ),
            ),
          ),
          if (_planExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 6, 6),
              child: Column(
                children: [
                  for (var i = 0; i < plan.length; i++)
                    InkWell(
                      onTap: () => _safeSetState(() => _planStep = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              i < paso
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 10,
                              color: i < paso
                                  ? cs.primary
                                  : i == paso
                                  ? cs.primary
                                  : cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '${i + 1}. ${plan.steps[i].title}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.3,
                                  fontWeight: i == paso
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i == paso
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                ),
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
    );
  }

  Future<void> _dismissTip() async {
    _safeSetState(() => _showTip = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTipSeenPref, true);
  }

  /// Botón `+` de la barra: adjunta el contexto que se haya retirado.
  Widget _buildAddContextBtn(ColorScheme cs) {
    final disponibles = _contextoDisponible();
    if (disponibles.isEmpty) {
      return _ChatIconBtn(
        icon: Icons.add,
        tooltip: 'Todo el contexto disponible ya está adjunto',
        size: 14,
        onTap: null,
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Añadir contexto',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      onSelected: (id) {
        if (id == 'errors') {
          setState(() => _includeErrors = true);
          unawaited(_savePrefs());
        }
      },
      itemBuilder: (_) => [
        for (final (id, icon, label) in disponibles)
          PopupMenuItem(
            value: id,
            height: 32,
            child: Row(
              children: [
                Icon(icon, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.add, size: 14, color: cs.onSurfaceVariant),
      ),
    );
  }

  /// Ajuste fino en una etiqueta compacta («Medium 1M» en VS Code).
  Widget _buildTuningPicker(ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: 'Razonamiento y ventana de contexto',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      onSelected: (value) {
        final parts = value.split(':');
        setState(() {
          if (parts.first == 'effort') {
            _effort = CopilotEffortX.fromId(parts[1]);
          } else {
            _contextTier = CopilotContextTierX.fromId(parts[1]);
          }
        });
        unawaited(_savePrefs());
      },
      itemBuilder: (_) => [
        _menuLabel('RAZONAMIENTO', cs),
        for (final e in CopilotEffort.values)
          PopupMenuItem(
            value: 'effort:${e.id}',
            height: 30,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 12,
                  color: _effort == e ? cs.primary : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(e.label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        const PopupMenuDivider(height: 6),
        _menuLabel('VENTANA DE CONTEXTO', cs),
        for (final t in CopilotContextTier.values)
          PopupMenuItem(
            value: 'context:${t.id}',
            height: 30,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 12,
                  color: _contextTier == t ? cs.primary : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(t.label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          '${_effort.label} · ${_tierCorto()}',
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  String _tierCorto() =>
      _contextTier == CopilotContextTier.long ? 'largo' : 'estándar';

  PopupMenuItem<String> _menuLabel(String text, ColorScheme cs) =>
      PopupMenuItem(
        enabled: false,
        height: 26,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
      );

  List<ChatSlashCommand> get _slashMatches {
    final query = (_slashQuery ?? '').toLowerCase();
    return kChatSlashCommands.where((c) => c.name.startsWith(query)).toList();
  }

  void _moveSlashHighlight(int delta) {
    final matches = _slashMatches;
    if (matches.isEmpty) return;
    _safeSetState(() {
      _slashIndex = (_slashIndex + delta) % matches.length;
      if (_slashIndex < 0) _slashIndex += matches.length;
    });
  }

  void _acceptSlashHighlighted() {
    final matches = _slashMatches;
    if (matches.isEmpty) return;
    _applySlashCommand(matches[_slashIndex.clamp(0, matches.length - 1)]);
  }

  /// Popup de autocompletado de `/comandos`, encima de la caja de entrada.
  ///
  /// Imita el *suggest widget* del editor de VS Code: icono de símbolo, el
  /// prefijo ya escrito resaltado, la descripción atenuada a la derecha y una
  /// única fila seleccionada con borde.
  Widget _buildSlashPopup(ColorScheme cs, bool isDark) {
    final matches = _slashMatches;
    if (matches.isEmpty) return const SizedBox.shrink();
    final typed = (_slashQuery ?? '').length;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252526) : cs.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: matches.length,
        itemBuilder: (_, i) {
          final c = matches[i];
          final selected = i == _slashIndex.clamp(0, matches.length - 1);
          final nombre = '/${c.name}';
          // El tramo ya tecleado va en color y en negrita, igual que la
          // coincidencia del autocompletado del editor.
          final prefijo = nombre.substring(
            0,
            (typed + 1).clamp(0, nombre.length),
          );
          final resto = nombre.substring(prefijo.length);

          return _HoverHighlight(
            builder: (hovered) => InkWell(
              onTap: () => _applySlashCommand(c),
              child: Container(
                color: selected
                    ? cs.primary.withValues(alpha: 0.22)
                    : hovered
                    ? cs.onSurface.withValues(alpha: 0.06)
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt_outlined,
                      size: 12,
                      color: cs.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10.5,
                        ),
                        children: [
                          TextSpan(
                            text: prefijo,
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: resto,
                            style: TextStyle(color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.description,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Tab',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Selector de modelo, equivalente al de la esquina inferior de VS Code.
  Widget _buildModelPicker(ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: 'Modelo',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      onSelected: (value) async {
        if (value == '__refresh__') {
          await _loadModels(force: true);
          return;
        }
        if (value == '__custom__') {
          final custom = await _askCustomModel();
          if (custom == null) return;
          setState(() => _model = custom);
        } else {
          setState(() => _model = value);
        }
        unawaited(_savePrefs());
      },
      itemBuilder: (_) => [
        for (final m in _models)
          PopupMenuItem(
            value: m,
            height: 32,
            child: Row(
              children: [
                Icon(
                  _model == m ? Icons.check : Icons.circle_outlined,
                  size: 12,
                  color: _model == m ? cs.primary : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(m, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem(
          value: '__refresh__',
          height: 32,
          child: Row(
            children: [
              Icon(
                _loadingModels ? Icons.hourglass_top : Icons.refresh,
                size: 12,
              ),
              const SizedBox(width: 8),
              const Text('Actualizar lista', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: '__custom__',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 12),
              SizedBox(width: 8),
              Text('Otro modelo…', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 11, color: cs.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Selector de modo (Agente / Plan / Pregunta), como el de VS Code.
  ///
  /// El modo cambia los permisos con los que se lanza la CLI y la instrucción
  /// que encabeza el prompt (ver [CopilotChatMode]).
  Widget _buildModePicker(ColorScheme cs) {
    const icons = {
      CopilotChatMode.agent: Icons.smart_toy_outlined,
      CopilotChatMode.plan: Icons.checklist_rtl,
      CopilotChatMode.ask: Icons.chat_bubble_outline,
    };

    return PopupMenuButton<CopilotChatMode>(
      tooltip: 'Modo: ${_mode.label}',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      onSelected: (value) {
        setState(() => _mode = value);
        unawaited(_savePrefs());
      },
      itemBuilder: (_) => [
        for (final m in CopilotChatMode.values)
          PopupMenuItem(
            value: m,
            height: 44,
            child: Row(
              children: [
                Icon(
                  icons[m],
                  size: 13,
                  color: _mode == m ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _mode == m
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      Text(
                        m.description,
                        style: TextStyle(
                          fontSize: 9,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_mode == m) Icon(Icons.check, size: 12, color: cs.primary),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icons[_mode], size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              _mode.label,
              style: TextStyle(fontSize: 10, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  /// Interruptores del contexto que se adjunta. El razonamiento y la ventana
  /// viven en su propio control, como en la barra de VS Code.
  Widget _buildSettingsButton(ColorScheme cs) {
    return PopupMenuButton<String>(
      tooltip: 'Qué se envía con la pregunta',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      onSelected: (value) {
        setState(() {
          if (value == 'auto') {
            _autoApply = !_autoApply;
          } else {
            _includeErrors = !_includeErrors;
          }
        });
        unawaited(_savePrefs());
      },
      itemBuilder: (_) => [
        _menuLabel('CAMBIOS', cs),
        PopupMenuItem(
          value: 'auto',
          height: 30,
          child: Row(
            children: [
              Icon(
                _autoApply ? Icons.check_box : Icons.check_box_outline_blank,
                size: 13,
                color: _autoApply ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              const Text(
                'Escribir en el documento al terminar',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        _menuLabel('CONTEXTO', cs),
        // El documento abierto no es opcional: se informa, no se ofrece.
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 12, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'El documento abierto va siempre',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'errors',
          height: 30,
          child: Row(
            children: [
              Icon(
                _includeErrors
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 13,
                color: _includeErrors ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              const Text(
                'Enviar los errores actuales',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.tune,
          size: 13,
          color: cs.onSurfaceVariant.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// Pide un identificador de modelo libre: la CLI acepta cualquiera que la
  /// cuenta tenga habilitado, y la lista cambia con el tiempo.
  Future<String?> _askCustomModel() async {
    final ctrl = TextEditingController(text: _model);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modelo de Copilot', style: TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'p. ej. auto, gpt-5, claude-sonnet-4.5',
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Usar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }
}

// ── Renderizado de markdown ───────────────────────────────────────────────────

/// Renderiza la respuesta de Copilot con formato: encabezados, listas, citas,
/// énfasis en línea y bloques de código con acciones.
///
/// Se implementa a mano en vez de añadir una dependencia porque el subconjunto
/// necesario es pequeño y así se controla el estilo compacto del panel.
class _MarkdownView extends StatelessWidget {
  final String content;
  final bool isError;

  /// Mientras llega texto se pinta un cursor, para que se note que la
  /// respuesta sigue creciendo y no está congelada.
  final bool isStreaming;
  final Future<void> Function(String code) onCopy;
  final void Function(String code) onInsert;

  const _MarkdownView({
    required this.content,
    required this.isError,
    required this.onCopy,
    required this.onInsert,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blocks = parseMarkdownBlocks(content);
    final baseColor = isError ? cs.error : cs.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks) _buildBlock(context, b, cs, isDark, baseColor),
        if (isStreaming) _StreamingCaret(color: cs.primary),
      ],
    );
  }

  Widget _buildBlock(
    BuildContext context,
    MdBlock b,
    ColorScheme cs,
    bool isDark,
    Color baseColor,
  ) {
    switch (b.kind) {
      case MdBlockKind.code:
        return _CodeBlock(
          code: b.text,
          language: b.language,
          onCopy: onCopy,
          onInsert: onInsert,
        );

      case MdBlockKind.heading:
        return Padding(
          padding: EdgeInsets.only(top: b.level <= 2 ? 10 : 7, bottom: 3),
          child: _inline(
            b.text,
            cs,
            TextStyle(
              fontSize: switch (b.level) {
                1 => 13.5,
                2 => 12.5,
                _ => 11.8,
              },
              fontWeight: FontWeight.w700,
              color: baseColor,
              height: 1.3,
            ),
          ),
        );

      case MdBlockKind.bullet:
        return Padding(
          padding: EdgeInsets.fromLTRB(4.0 + b.level * 12, 2, 0, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4.5, right: 7),
                child: Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: _inline(b.text, cs, _body(baseColor))),
            ],
          ),
        );

      case MdBlockKind.numbered:
        return Padding(
          padding: EdgeInsets.fromLTRB(4.0 + b.level * 12, 2, 0, 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  b.marker ?? '•',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: _inline(b.text, cs, _body(baseColor))),
            ],
          ),
        );

      case MdBlockKind.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 9),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cs.outlineVariant, width: 2.5),
            ),
          ),
          child: _inline(
            b.text,
            cs,
            _body(cs.onSurfaceVariant).copyWith(fontStyle: FontStyle.italic),
          ),
        );

      case MdBlockKind.rule:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 0.5, color: cs.outlineVariant),
        );

      case MdBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _inline(b.text, cs, _body(baseColor)),
        );
    }
  }

  TextStyle _body(Color color) =>
      TextStyle(fontSize: 11.5, height: 1.5, color: color);

  /// Convierte los `MdSpan` en un `SelectableText.rich`, para que el usuario
  /// pueda copiar cualquier fragmento igual que en VS Code.
  Widget _inline(String text, ColorScheme cs, TextStyle base) {
    final spans = parseInlineSpans(text);
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final s in spans)
            TextSpan(
              text: s.text,
              style: switch (s.style) {
                MdSpanStyle.bold => base.copyWith(fontWeight: FontWeight.w700),
                MdSpanStyle.italic => base.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                MdSpanStyle.code => base.copyWith(
                  fontFamily: 'Consolas',
                  fontSize: base.fontSize! - 0.5,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: cs.primary,
                ),
                MdSpanStyle.link => base.copyWith(
                  color: cs.primary,
                  decoration: TextDecoration.underline,
                ),
                MdSpanStyle.normal => base,
              },
            ),
        ],
      ),
    );
  }
}

/// Bloque de código con barra de acciones, como en Copilot Chat.
class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final Future<void> Function(String code) onCopy;
  final void Function(String code) onInsert;

  const _CodeBlock({
    required this.code,
    required this.language,
    required this.onCopy,
    required this.onInsert,
  });

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _hovered = false;

  /// El código no se envuelve por defecto —romper la indentación del PL/SQL
  /// lo hace ilegible—, pero se puede activar como en VS Code.
  bool _wrap = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spans = highlightCode(widget.code, widget.language, isDark: isDark);
    final baseStyle = const TextStyle(
      fontFamily: 'Consolas',
      fontSize: 10.5,
      height: 1.45,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161616) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _hovered
                ? cs.primary.withValues(alpha: 0.45)
                : cs.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 25,
              padding: const EdgeInsets.only(left: 9, right: 2),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    widget.language ?? 'plsql',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                  const Spacer(),
                  // Las acciones aparecen al pasar el puntero, como la barra
                  // de un bloque de código en VS Code.
                  AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ChatIconBtn(
                          icon: Icons.wrap_text,
                          tooltip: _wrap
                              ? 'No ajustar líneas'
                              : 'Ajustar líneas',
                          size: 11,
                          active: _wrap,
                          onTap: _hovered
                              ? () => setState(() => _wrap = !_wrap)
                              : null,
                        ),
                        _ChatIconBtn(
                          icon: Icons.content_copy_outlined,
                          tooltip: 'Copiar',
                          size: 11,
                          onTap: _hovered
                              ? () => unawaited(widget.onCopy(widget.code))
                              : null,
                        ),
                        _ChatIconBtn(
                          icon: Icons.keyboard_tab_rounded,
                          tooltip: 'Insertar en el cursor',
                          size: 11,
                          onTap: _hovered
                              ? () => widget.onInsert(widget.code)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_wrap)
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: SelectableText.rich(
                  TextSpan(style: baseStyle, children: spans),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: SelectableText.rich(
                  TextSpan(style: baseStyle, children: spans),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Piezas reutilizables ─────────────────────────────────────────────────────

/// Envuelve un hijo y le informa de si el puntero está encima.
///
/// Evita convertir en `StatefulWidget` cada fila que necesita destacar al
/// pasar por encima.
class _HoverHighlight extends StatefulWidget {
  final Widget Function(bool hovered) builder;

  const _HoverHighlight({required this.builder});

  @override
  State<_HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<_HoverHighlight> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}

/// Contador de segundos transcurridos, que se refresca solo.
///
/// Se aísla en su propio widget para que el tic no reconstruya el panel
/// entero mientras llega la respuesta.
class _ElapsedLabel extends StatefulWidget {
  final Color color;

  const _ElapsedLabel({required this.color});

  @override
  State<_ElapsedLabel> createState() => _ElapsedLabelState();
}

class _ElapsedLabelState extends State<_ElapsedLabel> {
  final _watch = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _watch.elapsedMilliseconds / 1000;
    return Text(
      '${s.toStringAsFixed(1)} s',
      style: TextStyle(
        fontSize: 9,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: widget.color,
      ),
    );
  }
}

/// Cursor parpadeante al final de una respuesta en streaming.
class _StreamingCaret extends StatefulWidget {
  final Color color;

  const _StreamingCaret({required this.color});

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: FadeTransition(
        opacity: _ctrl.drive(Tween(begin: 0.15, end: 1)),
        child: Container(width: 6, height: 11, color: widget.color),
      ),
    );
  }
}

/// Botón flotante para volver al final de la conversación.
class _ScrollToEndBtn extends StatelessWidget {
  /// Si hay respuesta en curso se avisa de que se está perdiendo contenido.
  final bool pending;
  final VoidCallback onTap;

  const _ScrollToEndBtn({required this.pending, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant, width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward_rounded, size: 12, color: cs.primary),
              const SizedBox(width: 5),
              Text(
                pending ? 'Respondiendo…' : 'Ir al final',
                style: TextStyle(fontSize: 9.5, color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de la barra «Continuar desde el plan».
///
/// Reproduce el botón partido de VS Code: la acción principal a la izquierda
/// y, si hay variantes, una flecha que abre el menú. Así las opciones poco
/// frecuentes no multiplican los botones visibles.
class _PlanActionBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onTap;
  final List<(String, VoidCallback)> menu;

  const _PlanActionBtn({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.tooltip,
    this.menu = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activo = enabled && onTap != null;
    final borde = cs.outlineVariant.withValues(alpha: activo ? 1 : 0.4);
    final texto = activo
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.45);
    final conMenu = menu.length > 1 && activo;

    final Widget cuerpo = _HoverHighlight(
      builder: (hovered) => Container(
        decoration: BoxDecoration(
          color: hovered && activo
              ? cs.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: borde, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: activo ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10.5, color: texto),
                ),
              ),
            ),
            if (conMenu) ...[
              // Divisoria del botón partido, como en VS Code.
              Container(width: 0.8, height: 21, color: borde),
              PopupMenuButton<int>(
                tooltip: 'Más opciones',
                position: PopupMenuPosition.under,
                padding: EdgeInsets.zero,
                onSelected: (i) => menu[i].$2(),
                itemBuilder: (_) => [
                  for (var i = 0; i < menu.length; i++)
                    PopupMenuItem(
                      value: i,
                      height: 32,
                      child: Text(
                        menu[i].$1,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 5,
                  ),
                  child: Icon(Icons.expand_more, size: 14, color: texto),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return tooltip == null ? cuerpo : Tooltip(message: tooltip!, child: cuerpo);
  }
}

/// Chip de contexto adjunto de la caja de entrada.
class _ContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final String tooltip;

  /// Pinta el icono en color de aviso, como la señal de VS Code cuando el
  /// adjunto arrastra problemas.
  final bool warn;

  /// Contexto fijo: no se puede retirar, y se marca con una chincheta para
  /// que se entienda que la ausencia de × es deliberada y no un olvido.
  final bool pinned;

  /// Si se indica, el chip muestra una × para desadjuntar el contexto.
  final VoidCallback? onRemove;

  const _ContextChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.tooltip,
    this.warn = false,
    this.pinned = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = warn
        ? cs.error
        : active
        ? cs.primary
        : cs.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: _HoverHighlight(
        builder: (hovered) => Container(
          padding: EdgeInsets.fromLTRB(5, 2, onRemove == null ? 5 : 2, 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: cs.outlineVariant, width: 0.6),
            color: cs.onSurface.withValues(alpha: hovered ? 0.06 : 0.03),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // La chincheta precede al icono del documento, igual que en la
              // caja de VS Code.
              if (pinned) ...[
                Icon(
                  Icons.push_pin,
                  size: 9,
                  color: cs.primary.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 3),
              ],
              Icon(icon, size: 10, color: iconColor),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: cs.onSurface),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 2),
                // La × solo se enciende al pasar por encima: el chip se lee
                // como una etiqueta hasta que se quiere retirar.
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(
                    Icons.close,
                    size: 10,
                    color: hovered
                        ? cs.onSurface
                        : cs.onSurfaceVariant.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador del pie del compositor («Local · Default permissions»).
///
/// No es decorativo: dice dónde se responde y con qué permisos corre el
/// agente, que es justo lo que no se puede deducir mirando la caja.
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;

  /// Se pinta en color de acento, para lo que el usuario debe poder localizar
  /// de un vistazo (los permisos del agente).
  final bool accent;
  final VoidCallback? onTap;

  const _StatusPill({
    required this.icon,
    required this.label,
    this.tooltip,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accent
        ? cs.primary
        : cs.onSurfaceVariant.withValues(alpha: 0.8);

    Widget fila = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 9, color: color)),
      ],
    );

    if (onTap != null) {
      fila = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: fila,
        ),
      );
    }

    return tooltip == null
        ? fila
        : Tooltip(
            message: tooltip!,
            waitDuration: const Duration(milliseconds: 400),
            child: fila,
          );
  }
}

/// Botón circular de enviar/detener, como el de Copilot Chat.
class _RoundActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  const _RoundActionBtn({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, size: 13, color: foreground),
        ),
      ),
    );
  }
}

class _ChatIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final bool active;

  const _ChatIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 12,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: _HoverHighlight(
        builder: (hovered) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              // Realimentación al pasar por encima: sin ella los iconos de
              // 11 px no parecen pulsables.
              color: hovered && onTap != null
                  ? cs.onSurface.withValues(alpha: 0.09)
                  : null,
            ),
            child: Icon(
              icon,
              size: size,
              color: onTap == null
                  ? cs.onSurfaceVariant.withValues(alpha: 0.3)
                  : active
                  ? cs.primary
                  : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
