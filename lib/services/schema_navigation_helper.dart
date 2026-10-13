import 'dart:async';
import 'package:flutter/foundation.dart';

import 'schema_service.dart';

/// Helper centralizado para resolver identificadores hacia objetos de esquema Oracle
/// (tablas, procedimientos, paquetes, funciones, tipos y vistas).
///
/// Soporta identificadores simples ("USUARIO"), nombres entrecomillados ("\"USUARIO\""),
/// cualificados por esquema ("PRODUCCION.MI_TABLA") o cualificados por paquete ("PKG_UTILS.MI_PROC").
Future<({String name, String objectType})?> resolveSchemaDefinition(
  String rawWord, {
  required String ambiente,
}) async {
  final clean = rawWord.trim().replaceAll('"', '');
  if (clean.isEmpty) return null;

  var schema = SchemaService.instance.getCached(ambiente: ambiente);
  if (schema == null) {
    try {
      schema = await SchemaService.instance.getMetadata(ambiente: ambiente);
    } catch (e) {
      debugPrint('[resolveSchemaDefinition] Error al cargar metadata: $e');
    }
  }
  if (schema == null) return null;

  return findSchemaObjectInMetadata(clean, schema);
}

/// Busca de forma sincrónica un identificador dentro de [SchemaMetadata].
({String name, String objectType})? findSchemaObjectInMetadata(
  String identifier,
  SchemaMetadata schema,
) {
  final upper = identifier.trim().replaceAll('"', '').toUpperCase();
  if (upper.isEmpty) return null;

  // 1. Si viene cualificado (ej. SCHEMA.TABLA o PKG.PROCEDURE)
  final parts = upper.split('.');
  if (parts.length >= 2) {
    final first = parts[0].trim();
    final second = parts[1].trim();

    // ¿El primer elemento es un PACKAGE o TYPE?
    final parentObj = schema.objects
        .where(
          (o) => o.name == first && (o.type == 'PACKAGE' || o.type == 'TYPE'),
        )
        .firstOrNull;
    if (parentObj != null) {
      return (name: parentObj.name, objectType: parentObj.type);
    }

    // ¿El segundo elemento es un objeto del esquema ignorando el owner?
    final directObj = _findDirect(second, schema);
    if (directObj != null) return directObj;

    // Fallback: buscar por el primer elemento
    final firstObj = _findDirect(first, schema);
    if (firstObj != null) return firstObj;
  }

  // 2. Búsqueda directa del identificador
  return _findDirect(upper, schema);
}

({String name, String objectType})? _findDirect(
  String upper,
  SchemaMetadata schema,
) {
  // a) Objetos con código fuente (PROCEDURE, FUNCTION, PACKAGE, TYPE, etc.)
  final obj = schema.objects.where((o) => o.name == upper).firstOrNull;
  if (obj != null) {
    return (name: obj.name, objectType: obj.type);
  }

  // b) Tablas del esquema
  if (schema.tables.contains(upper)) {
    return (name: upper, objectType: 'TABLE');
  }

  // c) Vistas del esquema
  if (schema.views.contains(upper)) {
    return (name: upper, objectType: 'VIEW');
  }

  return null;
}
