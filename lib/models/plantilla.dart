/// Representa una plantilla de código predefinida para la creación de
/// procedimientos dinámicos, procedimientos almacenados, funciones,
/// paquetes o scripts PL/SQL y JavaScript.
///
/// Interactúa directamente con el endpoint REST `/tools/plantillas`.
class Plantilla {
  /// Identificador único generado por el servidor o base de datos.
  /// Es cadena vacía o `null` si aún no ha sido persistida.
  final String id;

  /// Nombre identificador de la plantilla (ej. 'Procedimiento Dinámico Estándar').
  final String nombre;

  /// Categoría del objeto destino.
  /// Ejemplos: 'PROCEDIMIENTO_DINAMICO', 'PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE_BODY', 'TRIGGER', 'OTRO'
  final String categoria;

  /// Cuerpo/contenido de la plantilla de código.
  /// Admite marcadores como `{NOMBRE}`, `{NOMBRE_PROC}`, `{USUARIO}`, `{FECHA}`.
  final String contenido;

  /// Descripción detallada del propósito o uso de la plantilla.
  final String? descripcion;

  /// Usuario propietario o creador de la plantilla.
  final String ownerUser;

  /// Indica si la plantilla se encuentra activa (baja lógica).
  final bool isActive;

  /// Versión de concurrencia optimista gestionada por el backend.
  final int version;

  /// Fecha de última modificación (opcional/informativa).
  final DateTime? updatedAt;

  const Plantilla({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.contenido,
    this.descripcion,
    this.ownerUser = '',
    this.isActive = true,
    this.version = 0,
    this.updatedAt,
  });

  bool get isPersisted => id.isNotEmpty;

  /// Categorías comunes estándar
  static const String catProcDinamico = 'PROCEDIMIENTO_DINAMICO';
  static const String catProcedure = 'PROCEDURE';
  static const String catFunction = 'FUNCTION';
  static const String catPackage = 'PACKAGE';
  static const String catPackageBody = 'PACKAGE_BODY';
  static const String catTrigger = 'TRIGGER';
  static const String catOtro = 'OTRO';

  static const List<String> categoriasValidas = [
    catProcDinamico,
    catProcedure,
    catFunction,
    catPackage,
    catPackageBody,
    catTrigger,
    catOtro,
  ];

  /// Devuelve el lenguaje Monaco adecuado según la categoría y contenido.
  String get monacoLanguage {
    if (categoria == catProcDinamico &&
        (contenido.contains('jQuery') ||
            contenido.contains('function') ||
            contenido.contains('javascript'))) {
      return 'javascript';
    }
    return 'sql';
  }

  /// Aplica sustituciones de variables estándar en el contenido de la plantilla.
  String aplicarParametros({String? nombreObjeto, String? usuario}) {
    var res = contenido;
    final obj = (nombreObjeto ?? 'NOMBRE_OBJETO').trim().toUpperCase();
    final usr = (usuario ?? ownerUser).trim().toUpperCase();
    final fecha = DateTime.now();
    final fechaStr =
        '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

    res = res.replaceAll('{NOMBRE}', obj);
    res = res.replaceAll('{NOMBRE_PROC}', obj);
    res = res.replaceAll('{USUARIO}', usr);
    res = res.replaceAll('{FECHA}', fechaStr);
    return res;
  }

  Plantilla copyWith({
    String? id,
    String? nombre,
    String? categoria,
    String? contenido,
    String? descripcion,
    String? ownerUser,
    bool? isActive,
    int? version,
    DateTime? updatedAt,
  }) {
    return Plantilla(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      categoria: categoria ?? this.categoria,
      contenido: contenido ?? this.contenido,
      descripcion: descripcion ?? this.descripcion,
      ownerUser: ownerUser ?? this.ownerUser,
      isActive: isActive ?? this.isActive,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Coincidencia de búsqueda local por texto.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nombre.toLowerCase().contains(q) ||
        categoria.toLowerCase().contains(q) ||
        (descripcion?.toLowerCase().contains(q) ?? false) ||
        contenido.toLowerCase().contains(q);
  }

  factory Plantilla.fromJson(Map<String, dynamic> json) {
    String str(List<String> keys, [String fallback = '']) {
      for (final k in keys) {
        final val = json[k];
        if (val != null) return val.toString();
      }
      return fallback;
    }

    String? strOrNull(List<String> keys) {
      for (final k in keys) {
        final val = json[k];
        if (val != null && val.toString().trim().isNotEmpty) {
          return val.toString();
        }
      }
      return null;
    }

    bool parseBool(List<String> keys, [bool fallback = true]) {
      for (final k in keys) {
        final val = json[k];
        if (val is bool) return val;
        if (val is num) return val != 0;
        if (val is String) {
          final s = val.toLowerCase();
          if (s == 'true' || s == '1') return true;
          if (s == 'false' || s == '0') return false;
        }
      }
      return fallback;
    }

    int parseInt(List<String> keys, [int fallback = 0]) {
      for (final k in keys) {
        final val = json[k];
        if (val is num) return val.toInt();
        if (val is String) {
          final parsed = int.tryParse(val);
          if (parsed != null) return parsed;
        }
      }
      return fallback;
    }

    DateTime? parseDate(List<String> keys) {
      for (final k in keys) {
        final val = json[k];
        if (val is String && val.isNotEmpty) {
          try {
            return DateTime.parse(val);
          } catch (_) {}
        }
      }
      return null;
    }

    return Plantilla(
      id: str(['id', 'ID', '_id']),
      nombre: str(['nombre', 'NOMBRE', 'name', 'NAME'], 'Sin Nombre'),
      categoria: str(['categoria', 'CATEGORIA', 'category', 'tipo'], catOtro),
      contenido: str([
        'contenido',
        'CONTENIDO',
        'body',
        'content',
        'codigo',
      ], ''),
      descripcion: strOrNull(['descripcion', 'DESCRIPCION', 'description']),
      ownerUser: str([
        'ownerUser',
        'OWNERUSER',
        'usuario',
        'usuarioCreacion',
      ], ''),
      isActive: parseBool(['isActive', 'ISACTIVE', 'activo', 'stActivo'], true),
      version: parseInt(['version', 'VERSION'], 0),
      updatedAt: parseDate([
        'updatedAt',
        'UPDATEDAT',
        'fechaModificacion',
        'fecha',
      ]),
    );
  }

  /// Payload para crear (POST /tools/plantillas)
  Map<String, dynamic> toCreateJson() {
    return {
      'id': id.isEmpty ? null : id,
      'nombre': nombre.trim(),
      'categoria': categoria.trim(),
      'contenido': contenido,
      'descripcion': descripcion?.trim().isEmpty ?? true
          ? null
          : descripcion!.trim(),
      'ownerUser': ownerUser.trim(),
      'isActive': isActive,
    };
  }

  /// Payload para actualizar (PUT /tools/plantillas/{id})
  Map<String, dynamic> toUpdateJson() {
    return {
      'id': id,
      'nombre': nombre.trim(),
      'categoria': categoria.trim(),
      'contenido': contenido,
      'descripcion': descripcion?.trim().isEmpty ?? true
          ? null
          : descripcion!.trim(),
      'ownerUser': ownerUser.trim(),
      'isActive': isActive,
      'version': version,
    };
  }

  Map<String, dynamic> toJson() => toUpdateJson();

  @override
  String toString() =>
      'Plantilla(id: $id, nombre: $nombre, categoria: $categoria)';
}
