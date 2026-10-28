import 'dart:io';

/// Representa un script SQL o archivo de ingeniería inversa (RSQL) con su
/// identificador, nombre, contenido y fecha de creación en la base de datos del servidor.
class DeployTicketScript {
  final String? id;
  final String nombre;
  final String contenido;
  final DateTime? createdAt;

  const DeployTicketScript({
    this.id,
    required this.nombre,
    this.contenido = '',
    this.createdAt,
  });

  DeployTicketScript copyWith({
    String? id,
    String? nombre,
    String? contenido,
    DateTime? createdAt,
  }) {
    return DeployTicketScript(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      contenido: contenido ?? this.contenido,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory DeployTicketScript.fromJson(dynamic json) {
    if (json == null) {
      return const DeployTicketScript(nombre: '');
    }
    if (json is String) {
      return DeployTicketScript(nombre: json.trim());
    }
    if (json is Map<String, dynamic>) {
      DateTime? parseDate(dynamic val) {
        if (val == null || val is! String) return null;
        return DateTime.tryParse(val);
      }

      return DeployTicketScript(
        id: json['id']?.toString(),
        nombre: json['nombre']?.toString() ?? '',
        contenido: json['contenido']?.toString() ?? '',
        createdAt: parseDate(json['createdAt']),
      );
    }
    return DeployTicketScript(nombre: json.toString().trim());
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'contenido': contenido,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> toJsonForPayload() {
    return {
      if (id != null && id!.isNotEmpty) 'id': id,
      'nombre': nombre,
      'contenido': contenido,
    };
  }

  @override
  String toString() => nombre;
}

/// Modelo que representa un Ticket de Despliegue / Ficha de Pase Git
/// para la gestión de pases de base de datos e integración con el archivo index.txt.
class DeployTicket {
  final String id;
  final int version;
  final String autoriza;
  final String? url;
  final String tipoSolicitud;
  final String numeroSolicitud;
  final List<String> reglasNegocio;
  final List<String> paquetes;
  final List<String> funciones;
  final List<DeployTicketScript> sql;
  final List<DeployTicketScript> reverseSql;
  final List<String> objetos;
  final List<String> triggers;
  final List<DeployTicketScript> bloqueLogico;
  final String? database;
  final String? databaseDestino;
  final String? rutaDirectorioLocal;
  final String? rutaRepositorio;
  final String usuarioCrea;
  final String? usuarioActualiza;
  final DateTime? fechaCreacion;
  final DateTime? fechaModificacion;

  const DeployTicket({
    this.id = '',
    this.version = 1,
    this.autoriza = '',
    this.url,
    this.tipoSolicitud = '',
    this.numeroSolicitud = '',
    this.reglasNegocio = const [],
    this.paquetes = const [],
    this.funciones = const [],
    this.sql = const [],
    this.reverseSql = const [],
    this.objetos = const [],
    this.triggers = const [],
    this.bloqueLogico = const [],
    this.database,
    this.databaseDestino,
    this.rutaDirectorioLocal,
    this.rutaRepositorio,
    this.usuarioCrea = '',
    this.usuarioActualiza,
    this.fechaCreacion,
    this.fechaModificacion,
  });

  bool get isPersisted => id.isNotEmpty;

  List<String> get sqlNames =>
      sql.map((e) => e.nombre).where((e) => e.isNotEmpty).toList();
  List<String> get reverseSqlNames =>
      reverseSql.map((e) => e.nombre).where((e) => e.isNotEmpty).toList();
  List<String> get bloqueLogicoNames =>
      bloqueLogico.map((e) => e.nombre).where((e) => e.isNotEmpty).toList();

  DeployTicket copyWith({
    String? id,
    int? version,
    String? autoriza,
    String? url,
    String? tipoSolicitud,
    String? numeroSolicitud,
    List<String>? reglasNegocio,
    List<String>? paquetes,
    List<String>? funciones,
    List<DeployTicketScript>? sql,
    List<DeployTicketScript>? reverseSql,
    List<String>? objetos,
    List<String>? triggers,
    List<DeployTicketScript>? bloqueLogico,
    String? database,
    String? databaseDestino,
    String? rutaDirectorioLocal,
    String? rutaRepositorio,
    String? usuarioCrea,
    String? usuarioActualiza,
    DateTime? fechaCreacion,
    DateTime? fechaModificacion,
  }) {
    return DeployTicket(
      id: id ?? this.id,
      version: version ?? this.version,
      autoriza: autoriza ?? this.autoriza,
      url: url ?? this.url,
      tipoSolicitud: tipoSolicitud ?? this.tipoSolicitud,
      numeroSolicitud: numeroSolicitud ?? this.numeroSolicitud,
      reglasNegocio: reglasNegocio ?? this.reglasNegocio,
      paquetes: paquetes ?? this.paquetes,
      funciones: funciones ?? this.funciones,
      sql: sql ?? this.sql,
      reverseSql: reverseSql ?? this.reverseSql,
      objetos: objetos ?? this.objetos,
      triggers: triggers ?? this.triggers,
      bloqueLogico: bloqueLogico ?? this.bloqueLogico,
      database: database ?? this.database,
      databaseDestino: databaseDestino ?? this.databaseDestino,
      rutaDirectorioLocal: rutaDirectorioLocal ?? this.rutaDirectorioLocal,
      rutaRepositorio: rutaRepositorio ?? this.rutaRepositorio,
      usuarioCrea: usuarioCrea ?? this.usuarioCrea,
      usuarioActualiza: usuarioActualiza ?? this.usuarioActualiza,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaModificacion: fechaModificacion ?? this.fechaModificacion,
    );
  }

  factory DeployTicket.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic val) {
      if (val == null) return const [];
      if (val is List) {
        return val
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (val is String) {
        return val
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    List<DeployTicketScript> parseScriptList(dynamic val) {
      if (val == null) return const [];
      if (val is List) {
        return val
            .map((e) => DeployTicketScript.fromJson(e))
            .where((e) => e.nombre.isNotEmpty)
            .toList();
      }
      if (val is String) {
        return val
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((name) => DeployTicketScript(nombre: name))
            .toList();
      }
      return const [];
    }

    DateTime? parseDate(dynamic val) {
      if (val == null || val is! String) return null;
      return DateTime.tryParse(val);
    }

    return DeployTicket(
      id: json['id']?.toString() ?? '',
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse(json['version']?.toString() ?? '1') ?? 1,
      autoriza: json['autoriza']?.toString() ?? '',
      url: json['url']?.toString(),
      tipoSolicitud: json['tipoSolicitud']?.toString() ?? '',
      numeroSolicitud: json['numeroSolicitud']?.toString() ?? '',
      reglasNegocio: parseStringList(json['reglasNegocio']),
      paquetes: parseStringList(json['paquetes']),
      funciones: parseStringList(json['funciones']),
      sql: parseScriptList(json['sql']),
      reverseSql: parseScriptList(json['reverseSql']),
      objetos: parseStringList(json['objetos']),
      triggers: parseStringList(json['triggers']),
      bloqueLogico: parseScriptList(json['bloqueLogico']),
      database: json['database']?.toString(),
      databaseDestino: json['databaseDestino']?.toString(),
      rutaDirectorioLocal: json['rutaDirectorioLocal']?.toString(),
      rutaRepositorio: json['rutaRepositorio']?.toString(),
      usuarioCrea: json['usuarioCrea']?.toString() ?? '',
      usuarioActualiza: json['usuarioActualiza']?.toString(),
      fechaCreacion: parseDate(json['fechaCreacion']),
      fechaModificacion: parseDate(json['fechaModificacion']),
    );
  }

  Map<String, dynamic> toJsonForCreate() {
    String? joinOrNull(List<String> list) =>
        list.isEmpty ? null : list.join(',');

    List<Map<String, dynamic>>? scriptsOrNull(List<DeployTicketScript> list) {
      final valid = list.where((e) => e.nombre.isNotEmpty).toList();
      if (valid.isEmpty) return null;
      return valid.map((e) => e.toJsonForPayload()).toList();
    }

    return {
      'version': version,
      'autoriza': autoriza,
      'tipoSolicitud': tipoSolicitud,
      'numeroSolicitud': numeroSolicitud,
      'usuarioCrea': usuarioCrea,
      'url': url?.trim().isEmpty ?? true ? null : url!.trim(),
      'reglasNegocio': joinOrNull(reglasNegocio),
      'paquetes': joinOrNull(paquetes),
      'funciones': joinOrNull(funciones),
      'sql': scriptsOrNull(sql),
      'reverseSql': scriptsOrNull(reverseSql),
      'objetos': joinOrNull(objetos),
      'triggers': joinOrNull(triggers),
      'bloqueLogico': scriptsOrNull(bloqueLogico),
      'database': database?.trim().isEmpty ?? true ? null : database!.trim(),
      'databaseDestino': databaseDestino?.trim().isEmpty ?? true
          ? null
          : databaseDestino!.trim(),
      'rutaDirectorioLocal': rutaDirectorioLocal?.trim().isEmpty ?? true
          ? null
          : rutaDirectorioLocal!.trim(),
      'rutaRepositorio': rutaRepositorio?.trim().isEmpty ?? true
          ? null
          : rutaRepositorio!.trim(),
      'id': null,
    };
  }

  Map<String, dynamic> toJsonForUpdate() {
    String? joinOrNull(List<String> list) =>
        list.isEmpty ? null : list.join(',');

    List<Map<String, dynamic>>? scriptsOrNull(List<DeployTicketScript> list) {
      final valid = list.where((e) => e.nombre.isNotEmpty).toList();
      if (valid.isEmpty) return null;
      return valid.map((e) => e.toJsonForPayload()).toList();
    }

    return {
      'version': version,
      'autoriza': autoriza,
      'tipoSolicitud': tipoSolicitud,
      'numeroSolicitud': numeroSolicitud,
      'database': database ?? '',
      'databaseDestino': databaseDestino ?? '',
      'rutaDirectorioLocal': rutaDirectorioLocal?.trim().isEmpty ?? true
          ? null
          : rutaDirectorioLocal!.trim(),
      'rutaRepositorio': rutaRepositorio?.trim().isEmpty ?? true
          ? null
          : rutaRepositorio!.trim(),
      'usuarioActualiza': (usuarioActualiza?.trim().isNotEmpty ?? false)
          ? usuarioActualiza!.trim()
          : (Platform.environment['USERNAME'] ?? '').toUpperCase(),
      'url': url?.trim().isEmpty ?? true ? null : url!.trim(),
      'reglasNegocio': joinOrNull(reglasNegocio),
      'paquetes': joinOrNull(paquetes),
      'funciones': joinOrNull(funciones),
      'sql': scriptsOrNull(sql),
      'reverseSql': scriptsOrNull(reverseSql),
      'objetos': joinOrNull(objetos),
      'triggers': joinOrNull(triggers),
      'bloqueLogico': scriptsOrNull(bloqueLogico),
    };
  }

  /// Parsea el contenido textual de un archivo `index.txt` estándar.
  factory DeployTicket.parseIndexTxt(
    String content, {
    String currentUser = '',
  }) {
    int parsedVersion = 1;
    String parsedAutoriza = '';
    String? parsedUrl;
    String parsedTipoSolicitud = '';
    String parsedNumeroSolicitud = '';
    String? parsedDb;
    String? parsedDbd;

    final reglasNegocio = <String>[];
    final paquetes = <String>[];
    final funciones = <String>[];
    final sql = <DeployTicketScript>[];
    final reverseSql = <DeployTicketScript>[];
    final objetos = <String>[];
    final triggers = <String>[];
    final bloqueLogico = <DeployTicketScript>[];

    final lines = content.split(RegExp(r'\r?\n'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) continue;

      final key = line.substring(0, colonIdx).trim().toUpperCase();
      final val = line.substring(colonIdx + 1).trim();
      if (val.isEmpty) continue;

      switch (key) {
        case 'V':
          parsedVersion = int.tryParse(val) ?? 1;
          break;
        case 'AUT':
          parsedAutoriza = val;
          break;
        case 'URL':
          parsedUrl = val;
          break;
        case 'TPSOL':
          parsedTipoSolicitud = val;
          break;
        case 'NUSOL':
          parsedNumeroSolicitud = val;
          break;
        case 'DB':
          parsedDb = val;
          break;
        case 'DBD':
          parsedDbd = val;
          break;
        case 'RN':
        case 'PROC':
          _addCommaSeparated(reglasNegocio, val);
          break;
        case 'PCK':
          _addCommaSeparated(paquetes, val);
          break;
        case 'FUN':
          _addCommaSeparated(funciones, val);
          break;
        case 'SQL':
          _addScriptsCommaSeparated(sql, val);
          break;
        case 'RSQL':
          _addScriptsCommaSeparated(reverseSql, val);
          break;
        case 'OBJ':
          _addCommaSeparated(objetos, val);
          break;
        case 'TRG':
          _addCommaSeparated(triggers, val);
          break;
        case 'BLK':
          _addScriptsCommaSeparated(bloqueLogico, val);
          break;
      }
    }

    return DeployTicket(
      version: parsedVersion,
      autoriza: parsedAutoriza,
      url: parsedUrl,
      tipoSolicitud: parsedTipoSolicitud,
      numeroSolicitud: parsedNumeroSolicitud,
      reglasNegocio: reglasNegocio,
      paquetes: paquetes,
      funciones: funciones,
      sql: sql,
      reverseSql: reverseSql,
      objetos: objetos,
      triggers: triggers,
      bloqueLogico: bloqueLogico,
      database: parsedDb,
      databaseDestino: parsedDbd,
      usuarioCrea: currentUser,
    );
  }

  static void _addCommaSeparated(List<String> list, String text) {
    for (final part in text.split(',')) {
      final clean = part.trim();
      if (clean.isNotEmpty && !list.contains(clean)) {
        list.add(clean);
      }
    }
  }

  static void _addScriptsCommaSeparated(
    List<DeployTicketScript> list,
    String text,
  ) {
    for (final part in text.split(',')) {
      final clean = part.trim();
      if (clean.isNotEmpty && !list.any((e) => e.nombre == clean)) {
        list.add(DeployTicketScript(nombre: clean));
      }
    }
  }

  /// Genera la representación en formato `index.txt`
  String toIndexTxt() {
    final sb = StringBuffer();
    sb.writeln('# 			ARCHIVO DE CONFIGURACION PARA PASES POR GIT SIRWEB ');
    sb.writeln(
      '# =======================================================================================================',
    );
    sb.writeln('#			 		EPG Sirweb');
    sb.writeln('#		    __________  ______   _____ _                    __  ');
    sb.writeln('#		   / ____/ __ \\/ ____/  / ___/(_)_____      _____  / /_ ');
    sb.writeln(
      '#		  / __/ / /_/ / / __    \\__ \\/ / ___/ | /| / / _ \\/ __ \\',
    );
    sb.writeln('#		 / /___/ ____/ /_/ /   ___/ / / /   | |/ |/ /  __/ /_/ /');
    sb.writeln('#		/_____/_/    \\____/   /____/_/_/    |__/|__/\\___/_.___/ ');
    sb.writeln('#');
    sb.writeln(
      '# 	Este archivo le permite extraer los cambios realizado en la base de datos especificada.',
    );
    sb.writeln('#');
    sb.writeln('# 	Claves reservadas:');
    sb.writeln('# 	V 	     Versión.');
    sb.writeln('#	AUT 	 Usuario que autoriza.');
    sb.writeln('#	URL	     Enlace o ruta del ticket asociado.');
    sb.writeln('#	TPSOL	 Tipo de solicitud (por ejemplo, Matriz).');
    sb.writeln('#	NUSOL	 Número de solicitud.');
    sb.writeln(
      '#	RN:	     Nombre(s) de la(s) regla(s) de negocio / procedimiento(s).',
    );
    sb.writeln('#	PROC:	 Procedimiento almacenado.');
    sb.writeln('#	PCK:	 Nombre(s) del paquete.');
    sb.writeln('#	FUN:	 Nombre(s) de la(s) función(es).');
    sb.writeln('#	SQL:	 Nombre(s) de script(s) personalizado(s).');
    sb.writeln('#	RSQL:	 Archivo yaml / ingeniería inversa.');
    sb.writeln('#	OBJ:	 Objeto(s) de base de datos.');
    sb.writeln('#	TRG:	 Disparador (Trigger).');
    sb.writeln('#	BLK:	 Bloque(s) lógico(s).');
    sb.writeln('#	DB:	     Base de datos fuente de extracción (default DESA).');
    sb.writeln('#	DBD:	 Base de datos destino de exportación (default PROD).');
    sb.writeln(
      '# =======================================================================================================',
    );
    sb.writeln();

    sb.writeln('V:$version');
    if (autoriza.isNotEmpty) sb.writeln('AUT:$autoriza');
    if (url != null && url!.isNotEmpty) sb.writeln('URL:$url');
    if (tipoSolicitud.isNotEmpty) sb.writeln('TPSOL:$tipoSolicitud');
    if (numeroSolicitud.isNotEmpty) sb.writeln('NUSOL:$numeroSolicitud');
    if (database != null && database!.isNotEmpty) sb.writeln('DB:$database');
    if (databaseDestino != null && databaseDestino!.isNotEmpty) {
      sb.writeln('DBD:$databaseDestino');
    }

    if (reglasNegocio.isNotEmpty) sb.writeln('RN:${reglasNegocio.join(',')}');
    if (paquetes.isNotEmpty) sb.writeln('PCK:${paquetes.join(',')}');
    if (funciones.isNotEmpty) sb.writeln('FUN:${funciones.join(',')}');
    if (sql.isNotEmpty) sb.writeln('SQL:${sqlNames.join(',')}');
    if (reverseSql.isNotEmpty) sb.writeln('RSQL:${reverseSqlNames.join(',')}');
    if (objetos.isNotEmpty) sb.writeln('OBJ:${objetos.join(',')}');
    if (triggers.isNotEmpty) sb.writeln('TRG:${triggers.join(',')}');
    if (bloqueLogico.isNotEmpty) {
      sb.writeln('BLK:${bloqueLogicoNames.join(',')}');
    }

    return sb.toString();
  }
}
