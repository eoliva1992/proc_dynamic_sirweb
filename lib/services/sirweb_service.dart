import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/autorizacion_proceso.dart';
import '../models/configuracion_tipo.dart';
import '../models/dato_info.dart';
import '../models/ejecucion_procedimiento.dart';
import '../models/evento_info.dart';
import '../models/llamada_plsql.dart';
import '../models/procedimiento.dart';
import '../models/uso_procedimiento.dart';
import '../models/variable_dinamica.dart';
import 'app_log.dart';
import 'connection_status_service.dart';
import 'mcp_sse.dart';

class SirwebService {
  static final SirwebService _instance = SirwebService._();
  factory SirwebService() => _instance;
  SirwebService._();

  static const String _host = 'http://localhost:5179';
  static const String _baseUrl = '$_host/mcp';

  /// Nombre de la tool MCP que resuelve las autorizaciones de proceso.
  /// Centralizado acÃ¡ para poder ajustarlo si el servidor lo renombra.
  static const String _toolAutorizaciones = 'consultar_autorizaciones';

  // Shared across all instances for TCP keep-alive / connection reuse
  static final http.Client _client = http.Client();
  int _nextId = 1;

  /// Tiempo mÃ¡ximo que se espera una respuesta del servidor MCP.
  /// Sin esto, una caÃ­da del servidor deja el `await` colgado para siempre
  /// y la UI queda con el spinner activo sin poder recuperarse.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Envuelve una operaciÃ³n de red aplicando timeout y traduciendo las
  /// excepciones de bajo nivel a mensajes legibles para el usuario.
  /// [cancelado] permite distinguir un corte provocado por el usuario (cerrar
  /// el `http.Client` desde la UI) de una caída real del backend: si devuelve
  /// `true`, el fallo no se reporta al indicador de conexión —de lo contrario
  /// cancelar una ejecución dejaría la app marcada como "Sin conexión".
  static Future<T> guardRequest<T>(
    Future<T> Function() action, {
    Duration? timeout,
    String contexto = 'el servidor',
    bool Function()? cancelado,
  }) async {
    try {
      final result = await action().timeout(timeout ?? defaultTimeout);
      // El servidor respondio: alimentar el indicador de conexion.
      ConnectionStatusService.instance.reportSuccess();
      return result;
    } on TimeoutException {
      if (cancelado?.call() ?? false) throw const SirwebCancelledException();
      ConnectionStatusService.instance.reportFailure();
      throw _conexion(
        contexto,
        'Tiempo de espera agotado al comunicarse con $contexto. '
            'Verifica que el servicio este en ejecucion.',
        'TimeoutException (${(timeout ?? defaultTimeout).inSeconds}s)',
      );
    } on SocketException catch (e) {
      if (cancelado?.call() ?? false) throw const SirwebCancelledException();
      ConnectionStatusService.instance.reportFailure();
      throw _conexion(
        contexto,
        'No se pudo conectar con $contexto (${e.osError?.message ?? e.message}).',
        'SocketException: ${e.osError ?? e.message}',
      );
    } on HandshakeException catch (e) {
      if (cancelado?.call() ?? false) throw const SirwebCancelledException();
      ConnectionStatusService.instance.reportFailure();
      throw _conexion(
        contexto,
        'Error de conexion segura con $contexto.',
        'HandshakeException: ${e.message}',
      );
    } on http.ClientException catch (e) {
      if (cancelado?.call() ?? false) throw const SirwebCancelledException();
      ConnectionStatusService.instance.reportFailure();
      throw _conexion(
        contexto,
        'Se perdio la conexion con $contexto (${e.message}).',
        'ClientException: ${e.message} (${e.uri})',
      );
    }
  }

  /// Arma la excepcion de conexion dejando constancia en el log de la app.
  static SirwebConnectionException _conexion(
    String contexto,
    String mensaje,
    String tecnico,
  ) {
    AppLog.instance.server(
      contexto,
      message: mensaje,
      respuesta: tecnico,
      source: 'Conexion',
    );
    return SirwebConnectionException(mensaje);
  }

  Future<Map<String, dynamic>> _call(
    String toolName,
    Map<String, dynamic> arguments, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? defaultTimeout;
    final reloj = Stopwatch()..start();

    // Se usa `send` (y no `post`) porque el servidor responde vía SSE y deja el
    // stream abierto: `post` esperaría el EOF del cuerpo y el Future quedaría
    // colgado aunque el resultado ya haya llegado.
    final request = http.Request('POST', Uri.parse(_baseUrl))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      })
      ..body = jsonEncode({
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': {'name': toolName, 'arguments': arguments},
      });

    final dataStr = await guardRequest(
      () async {
        final streamed = await _client.send(request);
        return readFirstSseData(
          streamed,
          toolName: toolName,
          timeout: effectiveTimeout,
        );
      },
      timeout: effectiveTimeout,
      contexto: 'el servidor SirWeb',
    );

    final envelope = jsonDecode(dataStr) as Map<String, dynamic>;

    if (envelope.containsKey('error')) {
      final err = envelope['error'] as Map<String, dynamic>;
      final msg = err['message']?.toString() ?? 'Error desconocido';
      AppLog.instance.server(
        toolName,
        message: msg,
        argumentos: arguments,
        respuesta: dataStr,
      );
      throw Exception(msg);
    }

    final contentList = envelope['result']['content'] as List<dynamic>;
    final text = contentList.first['text'] as String;
    final result = jsonDecode(text) as Map<String, dynamic>;

    // Server can signal error via success:false or ok:false
    final isOk = result['ok'];
    final isSuccess = result['success'];
    if (isOk == false || isSuccess == false) {
      // Si hay datos de compilaciÃ³n (lista no vacÃ­a), devolver el result
      // para que el caller pueda extraer los errores individuales
      final data = result['data'];
      if (data is List && data.isNotEmpty) {
        return result; // compile errors â€” let caller handle
      }
      final baseMsg =
          result['message']?.toString() ??
          result['error']?.toString() ??
          'Error en la operaciÃ³n';
      AppLog.instance.server(
        toolName,
        message: baseMsg,
        argumentos: arguments,
        respuesta: text,
      );
      throw Exception(baseMsg);
    }

    AppLog.instance.transaction(
      toolName,
      source: 'MCP',
      duracion: reloj.elapsed,
      datos: {
        'Ambiente': arguments['ambiente']?.toString(),
        'Filas': result['data'] is List
            ? (result['data'] as List).length.toString()
            : null,
      },
    );
    return result;
  }

  Future<List<VariableDinamica>> obtenerVariablesDinamicas({
    String? ambiente,
  }) async {
    final result = await _call('obtener_variables_dinamicas', {
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final rawList = result['data'] as List<dynamic>? ?? [];
    return rawList
        .map((e) => VariableDinamica.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ConfiguracionTipo>> obtenerConfiguraciones() async {
    final result = await _call('obtener_configuraciones', {});
    final rawList = result['data'] as List<dynamic>? ?? [];
    return rawList
        .map((e) => ConfiguracionTipo.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.deArgumento.compareTo(b.deArgumento));
  }

  Future<
    ({
      List<Procedimiento> items,
      bool tieneSiguiente,
      bool tienePrevio,
      int pagina,
    })
  >
  listarProcedimientos({
    String? busqueda,
    String? configuracion,
    String? estado = '1',
    String? ambiente,
    int top = 50,
    int pagina = 1,
  }) async {
    // El backend combina CD_PROCEDIMIENTO y DE_TEXTO con OR, por eso el mismo
    // tÃ©rmino se envÃ­a en ambos parÃ¡metros: encuentra tanto por cÃ³digo como
    // por contenido del procedimiento.
    final result = await _call('listar_procedimientos', {
      if (busqueda != null && busqueda.isNotEmpty) ...{
        'cdProcedimiento': '%$busqueda%',
        'deTexto': '%$busqueda%',
      },
      if (configuracion != null && configuracion.isNotEmpty)
        'configuracion': configuracion,
      if (estado != null && estado.isNotEmpty) 'estado': estado,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      'top': top,
      'pagina': pagina,
    });

    final data = result['data'] as Map<String, dynamic>;
    final rawItems = data['items'] as List<dynamic>? ?? [];
    return (
      items: rawItems
          .map((e) => Procedimiento.fromJson(e as Map<String, dynamic>))
          .toList(),
      tieneSiguiente: data['tieneSiguiente'] as bool? ?? false,
      tienePrevio: data['tienePrevio'] as bool? ?? false,
      pagina: (data['pagina'] as int?) ?? pagina,
    );
  }

  Future<Procedimiento> obtenerProcedimiento(
    String cdProcedimiento, {
    String? ambiente,
  }) async {
    final result = await _call('obtener_procedimiento', {
      'cdProcedimiento': cdProcedimiento,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    return Procedimiento.fromJson(result['data'] as Map<String, dynamic>);
  }

  Future<void> crearProcedimiento({
    required String cdProcedimiento,
    required String deTexto,
    required String inConfiguracion,
    required String cdUsuario,
    String? ambiente,
  }) async {
    await _call('crear_procedimiento', {
      'cdProcedimiento': cdProcedimiento,
      'deTexto': deTexto,
      'inConfiguracion': inConfiguracion,
      'cdUsuario': cdUsuario,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
  }

  Future<List<dynamic>> actualizarProcedimiento({
    required String cdProcedimiento,
    required String deTexto,
    required String cdUsuario,
    required String inConfiguracion,
    String? ambiente,
  }) async {
    final result = await _call('actualizar_procedimiento', {
      'cdProcedimiento': cdProcedimiento,
      'deTexto': deTexto,
      'cdUsuario': cdUsuario,
      'inConfiguracion': inConfiguracion,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    return _extractCompileErrors(result);
  }

  List<dynamic> _extractCompileErrors(Map<String, dynamic> result) {
    for (final key in [
      'data',
      'compileErrors',
      'errors',
      'compilationErrors',
      'compile_errors',
    ]) {
      final val = result[key];
      if (val is List && val.isNotEmpty) {
        return val;
      }
      if (val is String &&
          val.isNotEmpty &&
          (val.contains('PLS-') || val.contains('ORA-') || val.contains('/'))) {
        return [val];
      }
    }
    final msg = result['message']?.toString() ?? '';
    if (msg.isNotEmpty &&
        (msg.contains('PLS-') ||
            msg.contains('ORA-') ||
            msg.toUpperCase().contains('ERROR'))) {
      return [msg];
    }
    return [];
  }

  Future<List<dynamic>> compilarProcedimiento({
    required String cdProcedimiento,
    required String deTexto,
    required String cdUsuario,
    required String inConfiguracion,
    String? ambiente,
  }) async {
    final result = await _call('compilar_procedimiento_dinamico', {
      'cdProcedimiento': cdProcedimiento,
      'deTexto': deTexto,
      'inConfiguracion': inConfiguracion,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    return _extractCompileErrors(result);
  }

  Future<void> activarProcedimiento({
    required String cdProcedimiento,
    required String cdUsuario,
    String? ambiente,
  }) async {
    await _call('activar_procedimiento', {
      'cdProcedimiento': cdProcedimiento,
      'cdUsuario': cdUsuario,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
  }

  Future<void> desactivarProcedimiento({
    required String cdProcedimiento,
    required String cdUsuario,
    String? ambiente,
  }) async {
    await _call('desactivar_procedimiento', {
      'cdProcedimiento': cdProcedimiento,
      'cdUsuario': cdUsuario,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
  }

  /// Carga solo el encabezado del evento (definiciÃ³n y tipo).
  Future<EventoInfo> infoEventoHeader(
    String cdEvento, {
    String? ambiente,
  }) async {
    final result = await _call('info_evento', {
      'cdEvento': cdEvento,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    return EventoInfo.fromSeparateResponses(cdEvento, result, {
      'data': <dynamic>[],
    });
  }

  /// Busca registros en DATO con filtros opcionales.
  Future<List<DatoInfo>> buscarDato({
    int? cdDato,
    String? deDato,
    String? tpDato,
    int? cdTabla,
    int? inUso,
    String? ambiente,
  }) async {
    final result = await _call('buscar_dato', {
      if (cdDato != null) 'cdDato': cdDato,
      if (deDato != null) 'deDato': deDato,
      if (tpDato != null) 'tpDato': tpDato,
      if (cdTabla != null) 'cdTabla': cdTabla,
      if (inUso != null) 'inUso': inUso,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final data = result['data'];
    final rawList = data is List
        ? data
        : (data is Map<String, dynamic>
              ? (data['items'] as List<dynamic>? ?? <dynamic>[])
              : <dynamic>[]);
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(DatoInfo.fromJson)
        .toList();
  }

  /// DefiniciÃ³n de tabla desde TABLADEFINICION.
  Future<TablaDefinicion> infoTabla(int cdTabla, {String? ambiente}) async {
    final result = await _call('info_tabla', {
      'cdTabla': cdTabla,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final data = result['data'];
    if (data is Map<String, dynamic>) return TablaDefinicion.fromJson(data);
    return TablaDefinicion.fromJson(result);
  }

  /// Valores de tabla desde TABLAINFORMACION.
  Future<List<ValorTabla>> valoresTabla(
    int cdTabla, {
    String? deIndiceDato,
    String? fechaDesde,
    String? fechaHasta,
    int? inSuspendido,
    String? ambiente,
  }) async {
    final result = await _call('valores_tabla', {
      'cdTabla': cdTabla,
      if (deIndiceDato != null) 'deIndiceDato': deIndiceDato,
      if (fechaDesde != null) 'fechaDesde': fechaDesde,
      if (fechaHasta != null) 'fechaHasta': fechaHasta,
      if (inSuspendido != null) 'inSuspendido': inSuspendido,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
    final data = result['data'];
    final rawList = data is List
        ? data
        : (data is Map<String, dynamic>
              ? (data['items'] as List<dynamic>? ??
                    data['valores'] as List<dynamic>? ??
                    <dynamic>[])
              : <dynamic>[]);
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(ValorTabla.fromJson)
        .toList();
  }

  /// Consulta las autorizaciones de proceso (tabla AUTORIZACION) con
  /// paginaciÃ³n de servidor.
  ///
  /// [codigo] busca por `CD_AUTORIZACION_PROCESO` y [descripcion] por
  /// `DE_AUTORIZACION`, ambos por coincidencia parcial. Si se envÃ­an los dos,
  /// el servidor los combina con OR.
  ///
  /// La respuesta esperada es:
  /// `{ data: { items: [...], pagina, top, tieneSiguiente, tienePrevio } }`.
  Future<AutorizacionPage> listarAutorizaciones({
    String? codigo,
    String? descripcion,
    String? ambiente,
    int top = 50,
    int pagina = 1,
  }) async {
    final result = await _call(_toolAutorizaciones, {
      if (codigo != null && codigo.isNotEmpty) 'codigo': codigo,
      if (descripcion != null && descripcion.isNotEmpty)
        'descripcion': descripcion,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      'top': top,
      'pagina': pagina,
    });
    return AutorizacionPage.fromData(
      result['data'],
      paginaSolicitada: pagina,
      topSolicitado: top,
    );
  }

  /// Consulta los valores del evento filtrando por Ã­ndice (servidor).
  Future<List<EventoValor>> valoresEvento(
    String cdEvento, {
    required String deIndiceEvento,
    String? ambiente,
    String? fechaDesde,
    String? fechaHasta,
  }) async {
    final result = await _call('valores_evento', {
      'cdEvento': cdEvento,
      'deIndiceEvento': deIndiceEvento,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
      if (fechaDesde != null) 'fechaDesde': fechaDesde,
      if (fechaHasta != null) 'fechaHasta': fechaHasta,
    });
    final data = result['data'];
    final rawList = data is List<dynamic>
        ? data
        : (data is Map<String, dynamic>
              ? (data['items'] as List<dynamic>? ??
                    data['valores'] as List<dynamic>? ??
                    <dynamic>[])
              : <dynamic>[]);
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(EventoValor.fromJson)
        .toList();
  }

  /// Consulta dÃ³nde se utiliza un procedimiento dinÃ¡mico (tabla + columna).
  ///
  /// Endpoint REST (no MCP):
  /// `GET /tools/procedimiento-dinamico/{cdProcedimiento}/usos`
  Future<UsosProcedimiento> usosProcedimiento(
    String cdProcedimiento, {
    String? ambiente,
    int timeoutPorTablaSegundos = 20,
  }) async {
    final uri =
        Uri.parse(
          '$_host/tools/procedimiento-dinamico/'
          '${Uri.encodeComponent(cdProcedimiento)}/usos',
        ).replace(
          queryParameters: {
            if (ambiente != null && ambiente.isNotEmpty && ambiente != 'Desa')
              'ambiente': ambiente,
            'timeoutPorTablaSegundos': '$timeoutPorTablaSegundos',
          },
        );

    final response = await guardRequest(
      () => _client.get(uri, headers: {'Accept': 'application/json'}),
      // La consulta de usos recorre varias tablas: le damos margen extra.
      timeout: Duration(seconds: timeoutPorTablaSegundos * 6),
      contexto: 'el servidor SirWeb',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Error ${response.statusCode} al consultar los usos del procedimiento',
      );
    }

    final envelope =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (envelope['success'] == false) {
      throw Exception(
        envelope['message']?.toString() ??
            envelope['error']?.toString() ??
            'Error al consultar los usos del procedimiento',
      );
    }

    final data = envelope['data'];
    if (data is Map<String, dynamic>) return UsosProcedimiento.fromJson(data);
    return const UsosProcedimiento();
  }

  /// Ejecuta un procedimiento dinámico contra Oracle en modo prueba.
  ///
  /// Endpoint REST (no MCP):
  /// `POST /tools/procedimiento-dinamico/{cdProcedimiento}/ejecutar`
  ///
  /// El backend arma el record de contexto según los identificadores enviados
  /// en [request] y devuelve las salidas, la traza y el error Oracle si lo hay.
  Future<EjecucionResultado> ejecutarProcedimiento(
    String cdProcedimiento, {
    required EjecucionRequest request,
    http.Client? client,
    bool Function()? cancelado,
  }) async {
    final uri = Uri.parse(
      '$_host/tools/procedimiento-dinamico/'
      '${Uri.encodeComponent(cdProcedimiento)}/ejecutar',
    );

    return _postEjecucion(
      uri,
      request.toJson(),
      request.timeoutSegundos,
      client: client,
      cancelado: cancelado,
    );
  }

  /// Ejecuta el código que el usuario tiene en el editor **sin guardarlo**.
  ///
  /// Endpoint REST (no MCP):
  /// `POST /tools/procedimiento-dinamico/ejecutar-borrador`
  ///
  /// A diferencia de [ejecutarProcedimiento], el backend no lee el texto de
  /// `PROCEDIMIENTODINAMICO`: usa el [deTexto] enviado con su
  /// [inConfiguracion] para armar el wrapper y ejecutarlo en modo prueba.
  Future<EjecucionResultado> ejecutarBorrador({
    required String deTexto,
    String? inConfiguracion,
    required EjecucionRequest request,
    http.Client? client,
    bool Function()? cancelado,
  }) async {
    final uri = Uri.parse(
      '$_host/tools/procedimiento-dinamico/ejecutar-borrador',
    );

    return _postEjecucion(
      uri,
      request.toBorradorJson(
        deTexto: deTexto,
        inConfiguracion: inConfiguracion,
      ),
      request.timeoutSegundos,
      client: client,
      cancelado: cancelado,
    );
  }

  /// Invoca un objeto PL/SQL cualquiera (procedure, function o miembro de un
  /// package) mandando la firma con los valores de entrada.
  ///
  /// Endpoint REST (no MCP): `POST /tools/plsql/llamada`
  ///
  /// El backend resuelve la firma real en Oracle, agrega los parámetros `OUT`
  /// que falten, ejecuta dentro de un bloque anónimo y hace ROLLBACK.
  ///
  /// A diferencia de [ejecutarProcedimiento], acá el envelope con
  /// `success: false` **no trae `data`** (el fallo ocurre antes de ejecutar:
  /// objeto inexistente, argumentos obligatorios faltantes…), por eso se
  /// traduce a excepción con el mensaje del servidor.
  Future<LlamadaResultado> ejecutarLlamada(
    LlamadaRequest request, {
    http.Client? client,
    bool Function()? cancelado,
  }) async {
    final uri = Uri.parse('$_host/tools/plsql/llamada');
    final segundos = request.timeoutSegundos ?? 30;
    final httpClient = client ?? _client;

    final response = await guardRequest(
      () => httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      ),
      timeout: Duration(seconds: segundos + 15),
      contexto: 'el servidor SirWeb',
      cancelado: cancelado,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detalle = _mensajeDeEnvelope(response.bodyBytes);
      final msg =
          detalle ?? 'Error ${response.statusCode} al ejecutar la llamada';
      AppLog.instance.server(
        uri.path,
        message: msg,
        statusCode: response.statusCode,
        argumentos: request.toJson(),
        respuesta: _cuerpo(response.bodyBytes),
      );
      throw Exception(msg);
    }

    final envelope =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final data = envelope['data'];
    final dataMap = data is Map
        ? data.map((k, v) => MapEntry(k.toString(), v))
        : null;

    if (envelope['success'] == false) {
      final msg =
          envelope['error']?.toString() ??
          envelope['message']?.toString() ??
          'Error al ejecutar la llamada';
      AppLog.instance.server(
        uri.path,
        message: msg,
        statusCode: response.statusCode,
        argumentos: request.toJson(),
        respuesta: _cuerpo(response.bodyBytes),
      );
      // Si el backend igual devolvió data (p. ej. error Oracle con traza), se
      // muestra: es justo lo que el usuario necesita ver.
      if (dataMap != null) return LlamadaResultado.fromJson(dataMap);
      throw Exception(msg);
    }

    AppLog.instance.transaction(
      'Ejecutar llamada PL/SQL',
      source: 'Ejecución',
      datos: {
        'Objeto': request.toJson()['nombre']?.toString(),
        'Ambiente': request.toJson()['ambiente']?.toString(),
      },
    );

    if (dataMap != null) return LlamadaResultado.fromJson(dataMap);
    return const LlamadaResultado();
  }

  /// POST + parseo del envelope comunes a `/ejecutar` y `/ejecutar-borrador`.
  Future<EjecucionResultado> _postEjecucion(
    Uri uri,
    Map<String, dynamic> body,
    int? timeoutSegundos, {
    http.Client? client,
    bool Function()? cancelado,
  }) async {
    // La ejecución puede tardar: se respeta el timeout pedido con margen extra
    // para el viaje de red y el armado del contexto.
    final segundos = timeoutSegundos ?? 30;
    final httpClient = client ?? _client;
    final reloj = Stopwatch()..start();

    final response = await guardRequest(
      () => httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ),
      timeout: Duration(seconds: segundos + 15),
      contexto: 'el servidor SirWeb',
      cancelado: cancelado,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // El backend suele devolver el detalle del fallo en el envelope aun con
      // status de error: se intenta leerlo antes de tirar el mensaje genérico.
      final detalle = _mensajeDeEnvelope(response.bodyBytes);
      final msg =
          detalle ??
          'Error ${response.statusCode} al ejecutar el procedimiento';
      AppLog.instance.server(
        uri.path,
        message: msg,
        statusCode: response.statusCode,
        argumentos: body,
        respuesta: _cuerpo(response.bodyBytes),
      );
      throw Exception(msg);
    }

    final envelope =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final data = envelope['data'];
    final dataMap = data is Map
        ? data.map((k, v) => MapEntry(k.toString(), v))
        : null;

    if (envelope['success'] == false) {
      final msg =
          envelope['message']?.toString() ??
          envelope['error']?.toString() ??
          'Error al ejecutar el procedimiento';
      AppLog.instance.server(
        uri.path,
        message: msg,
        statusCode: response.statusCode,
        argumentos: body,
        respuesta: _cuerpo(response.bodyBytes),
      );
      // Si vino data, se devuelve igual: contiene errorOracle y traza, que es
      // justo lo que el usuario necesita ver cuando la ejecución falla.
      if (dataMap != null) return EjecucionResultado.fromJson(dataMap);
      throw Exception(msg);
    }

    AppLog.instance.transaction(
      'Ejecutar procedimiento',
      source: 'Ejecución',
      duracion: reloj.elapsed,
      datos: {
        'Endpoint': uri.path,
        'Código': body['cdProcedimiento']?.toString(),
        'Ambiente': body['ambiente']?.toString(),
      },
    );

    if (dataMap != null) return EjecucionResultado.fromJson(dataMap);
    return const EjecucionResultado();
  }

  /// Cuerpo de la respuesta como texto, para dejarlo en el log.
  static String _cuerpo(List<int> bodyBytes) {
    try {
      return utf8.decode(bodyBytes);
    } catch (_) {
      return '(cuerpo no textual, ${bodyBytes.length} bytes)';
    }
  }

  /// Extrae `message`/`error` de una respuesta de error, si es JSON válido.
  String? _mensajeDeEnvelope(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final msg =
            decoded['message']?.toString() ?? decoded['error']?.toString();
        if (msg != null && msg.isNotEmpty) return msg;
      }
    } catch (_) {
      // Cuerpo no JSON (HTML de error, texto plano…): se ignora.
    }
    return null;
  }
}

/// Error de conectividad con el backend (timeout, socket caÃ­do, TLS, etc.).
/// Se expone como tipo propio para que la UI pueda distinguirlo de los
/// errores funcionales devueltos por Oracle y mostrar un mensaje adecuado.
class SirwebConnectionException implements Exception {
  SirwebConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// La petición se abortó porque el usuario la canceló desde la UI.
///
/// No implica que el backend se haya caído: por eso **no** actualiza el
/// indicador de conexión ni dispara reintentos.
class SirwebCancelledException implements Exception {
  const SirwebCancelledException([
    this.message = 'Petición cancelada por el usuario.',
  ]);

  final String message;

  @override
  String toString() => message;
}
