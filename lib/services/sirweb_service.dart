import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/procedimiento.dart';
import '../models/configuracion_tipo.dart';
import '../models/variable_dinamica.dart';

class SirwebService {
  static const String _baseUrl = 'http://localhost:5179/mcp';
  int _nextId = 1;

  Future<Map<String, dynamic>> _call(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/call',
        'params': {'name': toolName, 'arguments': arguments},
      }),
    );

    final dataStr = _extractSseData(response.body);
    final envelope = jsonDecode(dataStr) as Map<String, dynamic>;

    if (envelope.containsKey('error')) {
      final err = envelope['error'] as Map<String, dynamic>;
      throw Exception(err['message']?.toString() ?? 'Error desconocido');
    }

    final contentList = envelope['result']['content'] as List<dynamic>;
    final text = contentList.first['text'] as String;
    final result = jsonDecode(text) as Map<String, dynamic>;

    if (result['success'] == false) {
      throw Exception(result['message']?.toString() ?? 'Error en la operación');
    }

    return result;
  }

  String _extractSseData(String raw) {
    for (final line in raw.split('\n')) {
      if (line.startsWith('data: ')) return line.substring(6);
    }
    return raw;
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

  Future<({List<Procedimiento> items, bool tieneSiguiente, bool tienePrevio, int pagina})>
      listarProcedimientos({
    String? busqueda,
    String? configuracion,
    String? estado = '1',
    String? ambiente,
    int top = 50,
    int pagina = 1,
  }) async {
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

  Future<void> actualizarProcedimiento({
    required String cdProcedimiento,
    required String deTexto,
    required String cdUsuario,
    String? inConfiguracion,
    String? ambiente,
  }) async {
    await _call('actualizar_procedimiento', {
      'cdProcedimiento': cdProcedimiento,
      'deTexto': deTexto,
      'cdUsuario': cdUsuario,
      // ignore: use_null_aware_elements
      if (inConfiguracion != null) 'inConfiguracion': inConfiguracion,
      if (ambiente != null && ambiente != 'Desa') 'ambiente': ambiente,
    });
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
}
