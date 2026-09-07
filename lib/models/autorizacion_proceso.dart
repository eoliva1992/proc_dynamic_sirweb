/// Modelo de una autorización de proceso (tabla AUTORIZACIONPROCESO).
///
/// El servicio devuelve las columnas en snake_case tal como vienen de Oracle
/// (`cd_autorizacion_proceso`, `de_autorizacion`, …). El parseo acepta también
/// camelCase por si el backend cambia la convención.
class AutorizacionProceso {
  // ── Identificación ─────────────────────────────────────────────────────
  final String? version;
  final String? cdAutorizacionProceso;
  final String? deAutorizacion;
  final String? cdAutorizacionProcesoBase;
  final String? deAutorizacionBase;

  // ── Alcance ────────────────────────────────────────────────────────────
  final String? cdSubproceso;
  final String? deSubproceso;
  final String? cdOperacion;
  final String? deOperacion;
  final String? cdSubOperacion;
  final String? cdProducto;
  final String? deProducto;
  final String? cdMoneda;
  final String? deMoneda;
  final String? nuBienAsegurado;

  // ── Validación ─────────────────────────────────────────────────────────
  final String? tpParametroValidar;
  final String? deParametroValidar;
  final String? cdDato;
  final String? deDato;
  final String? vaMaximoAutorizar;
  final String? cdParametro;
  final String? cdProcedimiento;
  final String? tpAutorizacionEspecial;
  final String? deAutorizacionEspecial;

  // ── Indicadores ────────────────────────────────────────────────────────
  final bool? inUsoDato;
  final bool? inASolicitudUsuario;
  final bool? inAutorizacionUnica;
  final bool? inNoRechazarCotizacion;
  final bool? inMostrarEnError;

  // ── Correo: solicitud ──────────────────────────────────────────────────
  final bool? inEnvioEmail;
  final String? diRemitente;
  final String? diDestinatario;
  final String? txAsunto;
  final String? txMensaje;

  // ── Correo: aprobada ───────────────────────────────────────────────────
  final bool? inEnvioEmailAprobada;
  final String? diRemitenteAprobada;
  final String? txAsuntoAprobada;
  final String? txMensajeAprobada;

  // ── Correo: rechazada ──────────────────────────────────────────────────
  final bool? inEnvioEmailRechazada;
  final String? diRemitenteRechazada;
  final String? txAsuntoRechazada;
  final String? txMensajeRechazada;

  /// JSON original, para exportar / copiar sin perder columnas nuevas.
  final Map<String, dynamic> raw;

  const AutorizacionProceso({
    this.version,
    this.cdAutorizacionProceso,
    this.deAutorizacion,
    this.cdAutorizacionProcesoBase,
    this.deAutorizacionBase,
    this.cdSubproceso,
    this.deSubproceso,
    this.cdOperacion,
    this.deOperacion,
    this.cdSubOperacion,
    this.cdProducto,
    this.deProducto,
    this.cdMoneda,
    this.deMoneda,
    this.nuBienAsegurado,
    this.tpParametroValidar,
    this.deParametroValidar,
    this.cdDato,
    this.deDato,
    this.vaMaximoAutorizar,
    this.cdParametro,
    this.cdProcedimiento,
    this.tpAutorizacionEspecial,
    this.deAutorizacionEspecial,
    this.inUsoDato,
    this.inASolicitudUsuario,
    this.inAutorizacionUnica,
    this.inNoRechazarCotizacion,
    this.inMostrarEnError,
    this.inEnvioEmail,
    this.diRemitente,
    this.diDestinatario,
    this.txAsunto,
    this.txMensaje,
    this.inEnvioEmailAprobada,
    this.diRemitenteAprobada,
    this.txAsuntoAprobada,
    this.txMensajeAprobada,
    this.inEnvioEmailRechazada,
    this.diRemitenteRechazada,
    this.txAsuntoRechazada,
    this.txMensajeRechazada,
    this.raw = const {},
  });

  /// Lee una clave aceptando snake_case o camelCase.
  static String? _s(Map<String, dynamic> j, String snake, String camel) {
    final v = j[snake] ?? j[camel];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool? _b(Map<String, dynamic> j, String snake, String camel) {
    final v = j[snake] ?? j[camel];
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toUpperCase();
    if (s.isEmpty) return null;
    return s == '1' || s == 'S' || s == 'SI' || s == 'Y' || s == 'TRUE';
  }

  factory AutorizacionProceso.fromJson(Map<String, dynamic> j) {
    return AutorizacionProceso(
      version: _s(j, 'version', 'version'),
      cdAutorizacionProceso: _s(
        j,
        'cd_autorizacion_proceso',
        'cdAutorizacionProceso',
      ),
      deAutorizacion: _s(j, 'de_autorizacion', 'deAutorizacion'),
      cdAutorizacionProcesoBase: _s(
        j,
        'cd_autorizacion_proceso_base',
        'cdAutorizacionProcesoBase',
      ),
      deAutorizacionBase: _s(j, 'de_autorizacion_base', 'deAutorizacionBase'),
      cdSubproceso: _s(j, 'cd_subproceso', 'cdSubproceso'),
      deSubproceso: _s(j, 'de_subproceso', 'deSubproceso'),
      cdOperacion: _s(j, 'cd_operacion', 'cdOperacion'),
      deOperacion: _s(j, 'de_operacion', 'deOperacion'),
      cdSubOperacion: _s(j, 'cd_sub_operacion', 'cdSubOperacion'),
      cdProducto: _s(j, 'cd_producto', 'cdProducto'),
      deProducto: _s(j, 'de_producto', 'deProducto'),
      cdMoneda: _s(j, 'cd_moneda', 'cdMoneda'),
      deMoneda: _s(j, 'de_moneda', 'deMoneda'),
      nuBienAsegurado: _s(j, 'nu_bien_asegurado', 'nuBienAsegurado'),
      tpParametroValidar: _s(j, 'tp_parametro_validar', 'tpParametroValidar'),
      deParametroValidar: _s(j, 'de_parametro_validar', 'deParametroValidar'),
      cdDato: _s(j, 'cd_dato', 'cdDato'),
      deDato: _s(j, 'de_dato', 'deDato'),
      vaMaximoAutorizar: _s(j, 'va_maximo_autorizar', 'vaMaximoAutorizar'),
      cdParametro: _s(j, 'cd_parametro', 'cdParametro'),
      cdProcedimiento: _s(j, 'cd_procedimiento', 'cdProcedimiento'),
      tpAutorizacionEspecial: _s(
        j,
        'tp_autorizacion_especial',
        'tpAutorizacionEspecial',
      ),
      deAutorizacionEspecial: _s(
        j,
        'de_autorizacion_especial',
        'deAutorizacionEspecial',
      ),
      inUsoDato: _b(j, 'in_uso_dato', 'inUsoDato'),
      inASolicitudUsuario: _b(
        j,
        'in_a_solicitud_usuario',
        'inASolicitudUsuario',
      ),
      inAutorizacionUnica: _b(
        j,
        'in_autorizacion_unica',
        'inAutorizacionUnica',
      ),
      inNoRechazarCotizacion: _b(
        j,
        'in_no_rechazar_cotizacion',
        'inNoRechazarCotizacion',
      ),
      inMostrarEnError: _b(j, 'in_mostrar_en_error', 'inMostrarEnError'),
      inEnvioEmail: _b(j, 'in_envio_email', 'inEnvioEmail'),
      diRemitente: _s(j, 'di_remitente', 'diRemitente'),
      diDestinatario: _s(j, 'di_destinatario', 'diDestinatario'),
      txAsunto: _s(j, 'tx_asunto', 'txAsunto'),
      txMensaje: _s(j, 'tx_mensaje', 'txMensaje'),
      inEnvioEmailAprobada: _b(
        j,
        'in_envio_email_aprobada',
        'inEnvioEmailAprobada',
      ),
      diRemitenteAprobada: _s(
        j,
        'di_remitente_aprobada',
        'diRemitenteAprobada',
      ),
      txAsuntoAprobada: _s(j, 'tx_asunto_aprobada', 'txAsuntoAprobada'),
      txMensajeAprobada: _s(j, 'tx_mensaje_aprobada', 'txMensajeAprobada'),
      inEnvioEmailRechazada: _b(
        j,
        'in_envio_email_rechazada',
        'inEnvioEmailRechazada',
      ),
      diRemitenteRechazada: _s(
        j,
        'di_remitente_rechazada',
        'diRemitenteRechazada',
      ),
      txAsuntoRechazada: _s(j, 'tx_asunto_rechazada', 'txAsuntoRechazada'),
      txMensajeRechazada: _s(j, 'tx_mensaje_rechazada', 'txMensajeRechazada'),
      raw: j,
    );
  }

  /// Título corto para la lista maestra.
  String get titulo =>
      deAutorizacion ?? cdAutorizacionProceso ?? '(sin descripción)';

  /// Subtítulo para la lista maestra.
  String get subtitulo {
    final partes = <String>[
      ?cdAutorizacionProceso,
      ?(deSubproceso ?? cdSubproceso),
    ];
    return partes.join(' · ');
  }

  /// Texto plano usado por el filtro local del modal.
  String get searchText => [
    cdAutorizacionProceso,
    deAutorizacion,
    cdSubproceso,
    deSubproceso,
    deOperacion,
    deProducto,
    deDato,
    cdProcedimiento,
    cdParametro,
  ].whereType<String>().join(' ').toUpperCase();

  // ── Agrupaciones para el detalle del modal ─────────────────────────────

  List<(String, String)> get identificacion => _pairs([
    ('Código', cdAutorizacionProceso),
    ('Descripción', deAutorizacion),
    ('Versión', version),
    ('Autorización base', cdAutorizacionProcesoBase),
    ('Desc. base', deAutorizacionBase),
  ]);

  List<(String, String)> get alcance => _pairs([
    ('Subproceso', _codeAndDesc(cdSubproceso, deSubproceso)),
    ('Operación', _codeAndDesc(cdOperacion, deOperacion)),
    ('Sub-operación', cdSubOperacion),
    ('Producto', _codeAndDesc(cdProducto, deProducto)),
    ('Moneda', _codeAndDesc(cdMoneda, deMoneda)),
    ('Bien asegurado', nuBienAsegurado),
  ]);

  List<(String, String)> get validacion => _pairs([
    ('Parámetro validar', _codeAndDesc(tpParametroValidar, deParametroValidar)),
    ('Dato', _codeAndDesc(cdDato, deDato)),
    ('Máximo a autorizar', vaMaximoAutorizar),
    ('Parámetro', cdParametro),
    ('Procedimiento', cdProcedimiento),
    (
      'Autorización especial',
      _codeAndDesc(tpAutorizacionEspecial, deAutorizacionEspecial),
    ),
  ]);

  List<(String, bool)> get indicadores => _flags([
    ('Usa dato', inUsoDato),
    ('A solicitud del usuario', inASolicitudUsuario),
    ('Autorización única', inAutorizacionUnica),
    ('No rechaza cotización', inNoRechazarCotizacion),
    ('Mostrar en error', inMostrarEnError),
  ]);

  /// Bloques de correo: (título, activo, campos).
  List<(String, bool?, List<(String, String)>)> get correos => [
    (
      'Solicitud',
      inEnvioEmail,
      _pairs([
        ('Remitente', diRemitente),
        ('Destinatario', diDestinatario),
        ('Asunto', txAsunto),
        ('Mensaje', txMensaje),
      ]),
    ),
    (
      'Aprobada',
      inEnvioEmailAprobada,
      _pairs([
        ('Remitente', diRemitenteAprobada),
        ('Asunto', txAsuntoAprobada),
        ('Mensaje', txMensajeAprobada),
      ]),
    ),
    (
      'Rechazada',
      inEnvioEmailRechazada,
      _pairs([
        ('Remitente', diRemitenteRechazada),
        ('Asunto', txAsuntoRechazada),
        ('Mensaje', txMensajeRechazada),
      ]),
    ),
  ];

  static String? _codeAndDesc(String? cd, String? de) {
    if (cd == null && de == null) return null;
    if (cd == null) return de;
    if (de == null) return cd;
    return '$cd — $de';
  }

  static List<(String, String)> _pairs(List<(String, String?)> src) => [
    for (final (label, value) in src)
      if (value != null) (label, value),
  ];

  static List<(String, bool)> _flags(List<(String, bool?)> src) => [
    for (final (label, value) in src)
      if (value != null) (label, value),
  ];
}

/// Página de resultados devuelta por el servicio de autorizaciones.
class AutorizacionPage {
  final List<AutorizacionProceso> items;
  final int pagina;
  final int top;
  final bool tieneSiguiente;
  final bool tienePrevio;

  const AutorizacionPage({
    required this.items,
    required this.pagina,
    required this.top,
    required this.tieneSiguiente,
    required this.tienePrevio,
  });

  factory AutorizacionPage.fromData(
    dynamic data, {
    required int paginaSolicitada,
    required int topSolicitado,
  }) {
    if (data is List) {
      return AutorizacionPage(
        items: data
            .whereType<Map<String, dynamic>>()
            .map(AutorizacionProceso.fromJson)
            .toList(),
        pagina: paginaSolicitada,
        top: topSolicitado,
        tieneSiguiente: false,
        tienePrevio: paginaSolicitada > 1,
      );
    }
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final rawItems =
        map['items'] as List<dynamic>? ??
        map['autorizaciones'] as List<dynamic>? ??
        const <dynamic>[];
    return AutorizacionPage(
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(AutorizacionProceso.fromJson)
          .toList(),
      pagina: (map['pagina'] as num?)?.toInt() ?? paginaSolicitada,
      top: (map['top'] as num?)?.toInt() ?? topSolicitado,
      tieneSiguiente: map['tieneSiguiente'] as bool? ?? false,
      tienePrevio: map['tienePrevio'] as bool? ?? paginaSolicitada > 1,
    );
  }

  static const empty = AutorizacionPage(
    items: [],
    pagina: 1,
    top: 50,
    tieneSiguiente: false,
    tienePrevio: false,
  );
}
