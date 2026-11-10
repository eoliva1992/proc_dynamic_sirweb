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

  /// Usuario que realizó la última modificación (opcional/informativa).
  final String? modifiedBy;

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
    this.modifiedBy,
    this.isActive = true,
    this.version = 0,
    this.updatedAt,
  });

  bool get isPersisted => id.isNotEmpty;

  /// Retorna `true` si el usuario indicado es el propietario creador de la plantilla.
  /// Si la plantilla no tiene `ownerUser` definido, se considera abierta al usuario actual.
  bool esPropietario(String usuario) {
    final usr = usuario.trim().toUpperCase();
    final owner = ownerUser.trim().toUpperCase();
    if (owner.isEmpty) return true;
    return usr.isNotEmpty && usr == owner;
  }

  /// Categorías comunes estándar
  static const String catProcDinamico = 'PROCEDIMIENTO_DINAMICO';
  static const String catProcedure = 'PROCEDURE';
  static const String catFunction = 'FUNCTION';
  static const String catPackage = 'PACKAGE';
  static const String catPackageBody = 'PACKAGE_BODY';
  static const String catTrigger = 'TRIGGER';
  static const String catType = 'TYPE';
  static const String catOtro = 'OTRO';

  static const List<String> categoriasValidas = [
    catProcDinamico,
    catProcedure,
    catFunction,
    catPackage,
    catPackageBody,
    catTrigger,
    catType,
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

  /// Determina si esta plantilla es compatible con el tipo de configuración dado.
  /// Si [isJs] es true, requiere que la plantilla sea JavaScript.
  /// Si es false, requiere que la plantilla sea PL/SQL (SQL).
  bool esCompatibleConConfig({required bool isJs}) {
    if (categoria != catProcDinamico && categoria != catProcedure) {
      // Si no es procedimiento dinámico ni procedimiento estándar, no aplica a este modal
      return false;
    }
    final lang = monacoLanguage;
    return isJs ? lang == 'javascript' : lang == 'sql';
  }

  /// Formatea una fecha según un patrón (ej. dd/mm/yyyy, yyyy-mm-dd, dd-mm-yyyy hh24:mi:ss, etc.).
  /// Si [formato] es nulo o vacío, usa por defecto `dd/mm/yyyy`.
  static String formatearFecha(DateTime dt, [String? formato]) {
    final f = (formato == null || formato.trim().isEmpty)
        ? 'dd/mm/yyyy'
        : formato.trim();

    final yyyy = dt.year.toString().padLeft(4, '0');
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh24 = dt.hour.toString().padLeft(2, '0');
    final hh = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(
      2,
      '0',
    );
    final mi = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';

    var res = f;
    // Formato insensible a mayúsculas/minúsculas
    res = res.replaceAll(RegExp('yyyy', caseSensitive: false), yyyy);
    res = res.replaceAll(RegExp('hh24', caseSensitive: false), hh24);
    res = res.replaceAll(RegExp('hh12', caseSensitive: false), hh);
    res = res.replaceAll(RegExp('hh', caseSensitive: false), hh24);
    res = res.replaceAll(RegExp('mi', caseSensitive: false), mi);
    res = res.replaceAll(RegExp('ss', caseSensitive: false), ss);
    res = res.replaceAll(RegExp('am|pm', caseSensitive: false), ampm);
    res = res.replaceAll(RegExp('mm', caseSensitive: false), mm);
    res = res.replaceAll(RegExp('dd', caseSensitive: false), dd);
    res = res.replaceAll(RegExp('yy', caseSensitive: false), yy);

    return res;
  }

  /// Sustituye placeholders en el contenido de la plantilla para texto plano.
  ///
  /// Soporta el formato estándar de snippets Monaco:
  /// - `${0:usuario}`, `${usuario}`, `${1:nombre_proc}`, `${nombre}`, `${2:fecha}`, `${fecha}`
  /// - También conserva compatibilidad con `{NOMBRE_PROC}`, `{NOMBRE}`, `{USUARIO}`, `{FECHA}`.
  /// - Soporta {sysdate: formato} dinámico (ej. {sysdate: dd/mm/yyyy}, {sysdate: yyyy-mm-dd}, etc.).
  /// - Cualquier otro placeholder `${n:default}` o `$n` no provisto es reemplazado por su valor por defecto o texto interno.
  String aplicarParametros({String? nombreObjeto, String? usuario}) {
    var res = contenido;
    final obj = (nombreObjeto ?? 'NOMBRE_OBJETO').trim().toUpperCase();
    final usr = (usuario ?? (ownerUser.isNotEmpty ? ownerUser : 'USUARIO'))
        .trim()
        .toUpperCase();
    final fecha = DateTime.now();
    final fechaStrDefault = formatearFecha(fecha, 'dd/mm/yyyy');

    // 1. Compatibilidad retroactiva {TOKEN} y {sysdate: formato}
    res = res.replaceAll('{NOMBRE}', obj);
    res = res.replaceAll('{NOMBRE_PROC}', obj);
    res = res.replaceAll('{USUARIO}', usr);
    res = res.replaceAll('{FECHA}', fechaStrDefault);

    // Reemplazo dinámico de {sysdate} o {sysdate: <formato>} o {fecha: <formato>}
    final sysdateBracketsRegExp = RegExp(
      r'\{(?:sysdate|fecha)(?::\s*([^}]+))?\}',
      caseSensitive: false,
    );
    res = res.replaceAllMapped(sysdateBracketsRegExp, (m) {
      final customFmt = m.group(1);
      return formatearFecha(fecha, customFmt);
    });

    // 2. Procesamiento de sintaxis de snippet: ${n:nombre}, ${variable}, etc.
    // Regex para placeholders de la forma: ${0:usuario}, ${1:nombre_proc}, ${nombre}, etc.
    final snippetPattern = RegExp(r'\$\{(\d+):?([^}]*)\}');
    res = res.replaceAllMapped(snippetPattern, (m) {
      final tabStop = m.group(1);
      final rawLabel = (m.group(2) ?? '').trim();
      final labelLower = rawLabel.toLowerCase();

      if (labelLower.contains('usuario') ||
          labelLower.contains('user') ||
          tabStop == '0') {
        return usr;
      } else if (labelLower.contains('nombre') ||
          labelLower.contains('proc') ||
          labelLower.contains('objeto')) {
        return obj;
      } else if (labelLower.startsWith('fecha:') ||
          labelLower.startsWith('date:') ||
          labelLower.startsWith('sysdate:')) {
        final fmt = rawLabel.substring(rawLabel.indexOf(':') + 1).trim();
        return formatearFecha(fecha, fmt);
      } else if (labelLower.contains('fecha') ||
          labelLower.contains('date') ||
          labelLower.contains('sysdate')) {
        return fechaStrDefault;
      }
      // Si tiene un valor por defecto no reconocido, devolver ese valor por defecto
      final defVal = m.group(2) ?? '';
      return defVal.isNotEmpty ? defVal : obj;
    });

    // 3. Placeholders simples sin número: ${usuario}, ${nombre}, ${fecha}, ${sysdate: fmt}
    final namedVarPattern = RegExp(r'\$\{([a-zA-Z_0-9:\s\/\.\-]+)\}');
    res = res.replaceAllMapped(namedVarPattern, (m) {
      final content = m.group(1)!.trim();
      final contentLower = content.toLowerCase();
      if (contentLower.contains('usuario') || contentLower.contains('user')) {
        return usr;
      }
      if (contentLower.contains('nombre') ||
          contentLower.contains('proc') ||
          contentLower.contains('objeto')) {
        return obj;
      }
      if (contentLower.startsWith('fecha:') ||
          contentLower.startsWith('date:') ||
          contentLower.startsWith('sysdate:')) {
        final fmt = content.substring(content.indexOf(':') + 1).trim();
        return formatearFecha(fecha, fmt);
      }
      if (contentLower.contains('fecha') ||
          contentLower.contains('date') ||
          contentLower.contains('sysdate')) {
        return fechaStrDefault;
      }
      return m.group(0)!;
    });

    // 4. Limpiar tabstops planos restantes ($0, $1, etc.)
    res = res.replaceAll(RegExp(r'\$\d+'), '');

    return res;
  }

  /// Prepara el código como un snippet de Monaco:
  /// Pre-rellena valores conocidos del entorno (usuario, nombre, fecha)
  /// pero CONSERVA placeholders desconocidos y el cursor `$0` para permitir
  /// la navegación interactiva con Tab/Shift+Tab dentro de Monaco.
  String prepararParaInsercionSnippet({String? nombreObjeto, String? usuario}) {
    var res = contenido;
    final obj = (nombreObjeto ?? '').trim();
    final usr = (usuario ?? ownerUser).trim();
    final fecha = DateTime.now();
    final fechaStrDefault = formatearFecha(fecha, 'dd/mm/yyyy');

    // Si viene un nombre de objeto definido, reemplazarlo en los tokens de nombre
    if (obj.isNotEmpty) {
      res = res.replaceAll('{NOMBRE}', obj.toUpperCase());
      res = res.replaceAll('{NOMBRE_PROC}', obj.toUpperCase());
      res = res.replaceAllMapped(RegExp(r'\$\{(\d+):(nombre[^}]*)\}'), (m) {
        return obj.toUpperCase();
      });
      res = res.replaceAllMapped(RegExp(r'\$\{(nombre[^}]*)\}'), (m) {
        return obj.toUpperCase();
      });
    }

    // Reemplazar usuario si está disponible
    if (usr.isNotEmpty) {
      res = res.replaceAll('{USUARIO}', usr.toUpperCase());
      res = res.replaceAllMapped(RegExp(r'\$\{(\d+):(usuario|user)[^}]*\}'), (
        m,
      ) {
        return usr.toUpperCase();
      });
      res = res.replaceAllMapped(RegExp(r'\$\{(usuario|user)[^}]*\}'), (m) {
        return usr.toUpperCase();
      });
    }

    // Reemplazar fecha fija
    res = res.replaceAll('{FECHA}', fechaStrDefault);

    // Reemplazo dinámico de {sysdate} o {sysdate: <formato>} o {fecha: <formato>}
    final sysdateBracketsRegExp = RegExp(
      r'\{(?:sysdate|fecha)(?::\s*([^}]+))?\}',
      caseSensitive: false,
    );
    res = res.replaceAllMapped(sysdateBracketsRegExp, (m) {
      final customFmt = m.group(1);
      return formatearFecha(fecha, customFmt);
    });

    // Reemplazo en placeholders de snippet interactivos de fecha/sysdate con o sin formato:
    // ej. ${2:sysdate}, ${2:sysdate:yyyy-mm-dd}, ${sysdate:dd/mm/yyyy}
    res = res.replaceAllMapped(
      RegExp(
        r'\$\{(\d+):(fecha|date|sysdate)(?::\s*([^}]+))?\}',
        caseSensitive: false,
      ),
      (m) {
        final customFmt = m.group(3);
        return formatearFecha(fecha, customFmt);
      },
    );
    res = res.replaceAllMapped(
      RegExp(
        r'\$\{(fecha|date|sysdate)(?::\s*([^}]+))?\}',
        caseSensitive: false,
      ),
      (m) {
        final customFmt = m.group(2);
        return formatearFecha(fecha, customFmt);
      },
    );

    return res;
  }

  /// Sustituye ÚNICAMENTE las variables de usuario y fecha/sysdate,
  /// conservando intactos y literales todos los demás marcadores como
  /// `${1:...}`, `${2:...}`, `${3:...}`, `$0`, etc.
  ///
  /// Útil para el Editor SQL cuando se requiere que la plantilla conserve
  /// exactamente su texto sin que Monaco lo consuma como snippet interactivo.
  String aplicarSoloUsuarioYFecha({String? usuario}) {
    var res = contenido;
    final usr = (usuario ?? (ownerUser.isNotEmpty ? ownerUser : 'USUARIO'))
        .trim()
        .toUpperCase();
    final fecha = DateTime.now();
    final fechaStrDefault = formatearFecha(fecha, 'dd/mm/yyyy');

    // 1. Tokens en llaves simples {USUARIO}, {FECHA}, {sysdate}
    res = res.replaceAll('{USUARIO}', usr);
    res = res.replaceAll('{FECHA}', fechaStrDefault);

    final sysdateBracketsRegExp = RegExp(
      r'\{(?:sysdate|fecha)(?::\s*([^}]+))?\}',
      caseSensitive: false,
    );
    res = res.replaceAllMapped(sysdateBracketsRegExp, (m) {
      final customFmt = m.group(1);
      return formatearFecha(fecha, customFmt);
    });

    // 2. Placeholders de usuario: ${0:usuario}, ${0:user}, ${usuario}, ${user}
    res = res.replaceAllMapped(
      RegExp(r'\$\{(\d+):(usuario|user)[^}]*\}', caseSensitive: false),
      (m) => usr,
    );
    res = res.replaceAllMapped(
      RegExp(r'\$\{(usuario|user)[^}]*\}', caseSensitive: false),
      (m) => usr,
    );

    // 3. Placeholders de fecha / sysdate: ${2:fecha}, ${fecha:fmt}, ${sysdate:fmt}
    res = res.replaceAllMapped(
      RegExp(
        r'\$\{(\d+):(fecha|date|sysdate)(?::\s*([^}]+))?\}',
        caseSensitive: false,
      ),
      (m) {
        final customFmt = m.group(3);
        return formatearFecha(fecha, customFmt);
      },
    );
    res = res.replaceAllMapped(
      RegExp(
        r'\$\{(fecha|date|sysdate)(?::\s*([^}]+))?\}',
        caseSensitive: false,
      ),
      (m) {
        final customFmt = m.group(2);
        return formatearFecha(fecha, customFmt);
      },
    );

    return res;
  }

  /// Indica si el contenido contiene sintaxis de snippet interactivo
  /// (como `${1:placeholder}`, `${nombre:val}`, o `$0`..`$9`).
  bool get tieneSintaxisSnippet => contieneSintaxisSnippet(contenido);

  /// Evalúa si un texto dado contiene marcas de snippets interactivos de Monaco.
  static bool contieneSintaxisSnippet(String texto) {
    if (texto.isEmpty) return false;
    final snippetRegExp = RegExp(r'\$\{\d+:?[^}]*\}|\$\d+');
    return snippetRegExp.hasMatch(texto);
  }

  Plantilla copyWith({
    String? id,
    String? nombre,
    String? categoria,
    String? contenido,
    String? descripcion,
    String? ownerUser,
    String? modifiedBy,
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
      modifiedBy: modifiedBy ?? this.modifiedBy,
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
        'owner_user',
        'OWNER_USER',
        'usuario',
        'usuarioCreacion',
      ], ''),
      modifiedBy: strOrNull([
        'modifiedBy',
        'MODIFIEDBY',
        'modified_by',
        'MODIFIED_BY',
        'updatedBy',
        'updated_by',
        'usuarioModificacion',
      ]),
      isActive: parseBool([
        'isActive',
        'ISACTIVE',
        'is_active',
        'IS_ACTIVE',
        'activo',
        'stActivo',
      ], true),
      version: parseInt(['version', 'VERSION'], 0),
      updatedAt: parseDate([
        'updatedAt',
        'UPDATEDAT',
        'updated_at',
        'UPDATED_AT',
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
      if (modifiedBy != null && modifiedBy!.trim().isNotEmpty)
        'modifiedBy': modifiedBy!.trim(),
      'isActive': isActive,
    };
  }

  /// Payload para actualizar (PUT /tools/plantillas/{id})
  Map<String, dynamic> toUpdateJson({String? modifiedByUser}) {
    final effectiveModifiedBy =
        (modifiedByUser != null && modifiedByUser.trim().isNotEmpty)
        ? modifiedByUser.trim()
        : (modifiedBy != null && modifiedBy!.trim().isNotEmpty)
        ? modifiedBy!.trim()
        : (ownerUser.trim().isNotEmpty ? ownerUser.trim() : 'USUARIO');

    return {
      'id': id,
      'nombre': nombre.trim(),
      'categoria': categoria.trim(),
      'contenido': contenido,
      'descripcion': descripcion?.trim().isEmpty ?? true
          ? null
          : descripcion!.trim(),
      'ownerUser': ownerUser.trim().isEmpty
          ? effectiveModifiedBy
          : ownerUser.trim(),
      'modifiedBy': effectiveModifiedBy,
      'isActive': isActive,
      'version': version > 0 ? version : 1,
    };
  }

  Map<String, dynamic> toJson() => {
    ...toUpdateJson(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  @override
  String toString() =>
      'Plantilla(id: $id, nombre: $nombre, categoria: $categoria)';
}
