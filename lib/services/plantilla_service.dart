import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plantilla.dart';
import 'app_log.dart';
import 'server_config_service.dart';

/// Cliente HTTP remoto para el mantenimiento y consulta de Plantillas (/tools/plantillas).
///
/// Soporta fallback a caché local (SharedPreferences) y si el catálogo está vacío
/// o el servidor inaccesible, provee plantillas predefinidas de fábrica para
/// Procedimientos Dinámicos, Stored Procedures, Functions y Packages.
class PlantillaService {
  PlantillaService._();

  static final PlantillaService instance = PlantillaService._();

  static const String _cacheKey = 'user_plantillas_cache';
  static http.Client _client = http.Client();

  @visibleForTesting
  static void setHttpClientForTesting(http.Client? client) {
    _client = client ?? http.Client();
  }

  /// Usuario Windows / sesión por defecto
  static String currentUser =
      (Platform.environment['USERNAME'] ?? '').toUpperCase();

  /// Resuelve la URL base dinámica hacia el endpoint de plantillas
  static Future<String> getBaseUrl() async {
    final baseUrl = await ServerConfigService().getBaseUrl();
    return '$baseUrl/tools/plantillas';
  }

  // ------------------------------------------------------------------ Consultas

  /// Carga todas las plantillas (del backend o de la caché local si falla).
  Future<List<Plantilla>> loadAll({
    String? categoria,
    String? query,
    bool? isActive = true,
    String? ownerUser,
  }) async {
    try {
      final items = await search(
        categoria: categoria,
        query: query,
        isActive: isActive,
        ownerUser: ownerUser,
      );
      if (items.isNotEmpty) {
        return items;
      }
      // Si el backend no tiene plantillas aún, enriquecer con las de fábrica
      final cached = await loadCached();
      if (cached.isNotEmpty) {
        return _filtrarLocal(cached, categoria, query, isActive);
      }
      return _filtrarLocal(plantillasPorDefecto(), categoria, query, isActive);
    } catch (e) {
      AppLog.instance.error('Error cargando plantillas desde server: $e');
      final cached = await loadCached();
      if (cached.isNotEmpty) {
        return _filtrarLocal(cached, categoria, query, isActive);
      }
      return _filtrarLocal(plantillasPorDefecto(), categoria, query, isActive);
    }
  }

  /// Consulta al backend vía GET `/tools/plantillas`
  Future<List<Plantilla>> search({
    String? categoria,
    String? query,
    bool? isActive = true,
    String? ownerUser,
  }) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        if (categoria != null && categoria.trim().isNotEmpty)
          'categoria': categoria.trim(),
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if (isActive != null) 'isActive': isActive.toString(),
        if (ownerUser != null && ownerUser.trim().isNotEmpty)
          'ownerUser': ownerUser.trim(),
      },
    );

    final res = await _client.get(uri, headers: const {'Accept': '*/*'});
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      List<dynamic> list = [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['data'] is List) {
          list = decoded['data'] as List;
        } else if (decoded['items'] is List) {
          list = decoded['items'] as List;
        }
      }

      final items = list
          .whereType<Map<String, dynamic>>()
          .map((m) => Plantilla.fromJson(m))
          .toList();

      if (items.isNotEmpty) {
        unawaited(_saveToCache(items));
      }
      return items;
    } else {
      throw HttpException('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  /// Obtiene una plantilla puntual por su ID
  Future<Plantilla?> getById(String id) async {
    try {
      final baseUrl = await getBaseUrl();
      final uri = Uri.parse('$baseUrl/${Uri.encodeComponent(id)}');
      final res = await _client.get(uri, headers: const {'Accept': '*/*'});
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'] is Map<String, dynamic>
              ? decoded['data'] as Map<String, dynamic>
              : decoded;
          return Plantilla.fromJson(data);
        }
      }
      return null;
    } catch (_) {
      final cached = await loadCached();
      return cached.where((p) => p.id == id).firstOrNull;
    }
  }

  // ------------------------------------------------------------------ Escritura

  /// Crea una nueva plantilla en el servidor (POST /tools/plantillas)
  Future<Plantilla> create(Plantilla plantilla) async {
    final payload = plantilla.copyWith(
      ownerUser: plantilla.ownerUser.isEmpty ? currentUser : plantilla.ownerUser,
    );
    final baseUrl = await getBaseUrl();
    final res = await _client.post(
      Uri.parse(baseUrl),
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode(payload.toCreateJson()),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      Plantilla saved = payload;
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'] is Map<String, dynamic>
            ? decoded['data'] as Map<String, dynamic>
            : decoded;
        saved = Plantilla.fromJson(data);
      }
      unawaited(_updateCacheWith(saved));
      AppLog.instance.info('Plantilla creada exitosamente: ${saved.nombre}');
      return saved;
    } else {
      throw HttpException('Error creando plantilla: ${res.statusCode} - ${res.body}');
    }
  }

  /// Actualiza una plantilla existente (PUT /tools/plantillas/{id})
  Future<Plantilla> update(Plantilla plantilla) async {
    if (plantilla.id.isEmpty) {
      return create(plantilla);
    }
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/${Uri.encodeComponent(plantilla.id)}');
    final res = await _client.put(
      uri,
      headers: const {'Content-Type': 'application/json', 'Accept': '*/*'},
      body: jsonEncode(plantilla.toUpdateJson()),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      Plantilla updated = plantilla;
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'] is Map<String, dynamic>
            ? decoded['data'] as Map<String, dynamic>
            : decoded;
        updated = Plantilla.fromJson(data);
      }
      unawaited(_updateCacheWith(updated));
      AppLog.instance.info('Plantilla actualizada: ${updated.nombre}');
      return updated;
    } else {
      throw HttpException('Error actualizando plantilla: ${res.statusCode} - ${res.body}');
    }
  }

  /// Guarda (crea si no tiene ID o actualiza si ya tiene ID)
  Future<Plantilla> save(Plantilla plantilla) {
    if (plantilla.isPersisted) {
      return update(plantilla);
    } else {
      return create(plantilla);
    }
  }

  /// Elimina o desactiva lógicamente una plantilla (DELETE /tools/plantillas/{id})
  Future<bool> delete(Plantilla plantilla) async {
    if (!plantilla.isPersisted) return false;
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/${Uri.encodeComponent(plantilla.id)}');
    final res = await _client.delete(uri, headers: const {'Accept': '*/*'});

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (ok) {
      unawaited(_removeFromCache(plantilla.id));
      AppLog.instance.info('Plantilla eliminada: ${plantilla.id}');
    }
    return ok;
  }

  // ------------------------------------------------------------- Caché & Semilla

  Future<List<Plantilla>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => Plantilla.fromJson(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveToCache(List<Plantilla> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(list.map((p) => p.toJson()).toList());
      await prefs.setString(_cacheKey, jsonStr);
    } catch (_) {}
  }

  Future<void> _updateCacheWith(Plantilla item) async {
    final list = await loadCached();
    final idx = list.indexWhere((p) => p.id == item.id);
    if (idx >= 0) {
      list[idx] = item;
    } else {
      list.insert(0, item);
    }
    await _saveToCache(list);
  }

  Future<void> _removeFromCache(String id) async {
    final list = await loadCached();
    list.removeWhere((p) => p.id == id);
    await _saveToCache(list);
  }

  List<Plantilla> _filtrarLocal(
    List<Plantilla> items,
    String? categoria,
    String? query,
    bool? isActive,
  ) {
    return items.where((p) {
      if (isActive != null && p.isActive != isActive) return false;
      if (categoria != null &&
          categoria.isNotEmpty &&
          p.categoria.toUpperCase() != categoria.toUpperCase()) {
        return false;
      }
      if (query != null && query.isNotEmpty && !p.matches(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Catálogo de plantillas predefinidas de fábrica
  static List<Plantilla> plantillasPorDefecto() {
    return [
      // 1. Procedimiento Dinámico SirWeb Estándar
      const Plantilla(
        id: 'seed-proc-dinamico-std',
        nombre: 'Procedimiento Dinámico Estándar',
        categoria: Plantilla.catProcDinamico,
        descripcion: 'Estructura PL/SQL con control de excepciones y variable de estado W_STAT',
        contenido: 'BEGIN\n'
            '  DECLARE\n'
            "    W_STAT VARCHAR2(5) := '0';\n"
            '  BEGIN\n'
            '    -- 1. Inicialización y lógica de negocio\n'
            '    W_STAT := \'10\';\n'
            '    NULL;\n'
            '  EXCEPTION\n'
            '    WHEN OTHERS THEN\n'
            "      :P_ERROR := '{NOMBRE_PROC} EN ' || W_STAT || ' ** ' || SQLERRM;\n"
            '  END;\n'
            'END;',
      ),
      // 2. Procedimiento Dinámico SirWeb JavaScript
      const Plantilla(
        id: 'seed-proc-dinamico-js',
        nombre: 'Procedimiento Dinámico JavaScript',
        categoria: Plantilla.catProcDinamico,
        descripcion: 'Estructura con jQuery ready y función con bloque try-catch',
        contenido: 'jQuery(document).ready(function () {\n'
            '  // Inicialización de componentes en la vista\n'
            '});\n\n'
            'function {NOMBRE_PROC}() {\n'
            '  try {\n'
            '    // Lógica principal de ejecución\n'
            '  } catch (e) {\n'
            '    console.error(\'{NOMBRE_PROC}:\', e);\n'
            '    alert(\'Error en {NOMBRE_PROC}: \' + e.message);\n'
            '  }\n'
            '}',
      ),
      // 3. Procedimiento Almacenado Oracle (DDL)
      const Plantilla(
        id: 'seed-oracle-procedure',
        nombre: 'Stored Procedure Oracle (DDL)',
        categoria: Plantilla.catProcedure,
        descripcion: 'Procedimiento almacenado con parámetros de entrada/salida y manejo de errores',
        contenido: 'CREATE OR REPLACE PROCEDURE {NOMBRE} (\n'
            '    p_id          IN  NUMBER,\n'
            '    p_resultado   OUT VARCHAR2,\n'
            '    p_error       OUT VARCHAR2\n'
            ') IS\n'
            '    v_paso VARCHAR2(10) := \'00\';\n'
            'BEGIN\n'
            '    v_paso := \'01\';\n'
            '    p_resultado := \'OK\';\n'
            '    p_error := NULL;\n'
            'EXCEPTION\n'
            '    WHEN OTHERS THEN\n'
            '        p_resultado := \'ERROR\';\n'
            '        p_error := \'{NOMBRE} en paso \' || v_paso || \': \' || SQLERRM;\n'
            'END {NOMBRE};\n/',
      ),
      // 4. Función Oracle (DDL)
      const Plantilla(
        id: 'seed-oracle-function',
        nombre: 'Function Oracle (DDL)',
        categoria: Plantilla.catFunction,
        descripcion: 'Función determinista o escalar con retorno de valor',
        contenido: 'CREATE OR REPLACE FUNCTION {NOMBRE} (\n'
            '    p_parametro IN VARCHAR2\n'
            ') RETURN VARCHAR2 IS\n'
            '    v_retorno VARCHAR2(4000);\n'
            'BEGIN\n'
            '    -- Lógica de transformación o cálculo\n'
            '    v_retorno := TRIM(p_parametro);\n'
            '    RETURN v_retorno;\n'
            'EXCEPTION\n'
            '    WHEN OTHERS THEN\n'
            '        RETURN NULL;\n'
            'END {NOMBRE};\n/',
      ),
      // 5. Package Specification (DDL)
      const Plantilla(
        id: 'seed-oracle-package-spec',
        nombre: 'Package Specification (DDL)',
        categoria: Plantilla.catPackage,
        descripcion: 'Especificación de paquete con declaración de tipos y firmas públicas',
        contenido: 'CREATE OR REPLACE PACKAGE {NOMBRE} AS\n'
            '    -- Tipos y constantes\n'
            '    TYPE t_cursor IS REF CURSOR;\n\n'
            '    -- Firmas de procedimientos y funciones públicas\n'
            '    PROCEDURE inicializar;\n\n'
            '    FUNCTION obtener_estado (\n'
            '        p_id IN NUMBER\n'
            '    ) RETURN VARCHAR2;\n'
            'END {NOMBRE};\n/',
      ),
      // 6. Package Body (DDL)
      const Plantilla(
        id: 'seed-oracle-package-body',
        nombre: 'Package Body (DDL)',
        categoria: Plantilla.catPackageBody,
        descripcion: 'Cuerpo de paquete con implementación de lógica y métodos privados',
        contenido: 'CREATE OR REPLACE PACKAGE BODY {NOMBRE} AS\n\n'
            '    PROCEDURE inicializar IS\n'
            '    BEGIN\n'
            '        NULL;\n'
            '    END inicializar;\n\n'
            '    FUNCTION obtener_estado (\n'
            '        p_id IN NUMBER\n'
            '    ) RETURN VARCHAR2 IS\n'
            '    BEGIN\n'
            '        RETURN \'ACTIVO\';\n'
            '    END obtener_estado;\n\n'
            'END {NOMBRE};\n/',
      ),
    ];
  }
}
