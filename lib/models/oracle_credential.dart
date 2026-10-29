library;

/// Modelos para el módulo de Credenciales de Ambientes Oracle
/// que interactúa con los endpoints `/tools/oracle-credenciales` del servidor.

/// Estado actual de las credenciales Oracle por ambiente.
class OracleCredentialStatus {
  final String ambiente;
  final String userId;
  final String password;
  final String? host;
  final String? port;
  final String origen; // "Config" o "Override"

  const OracleCredentialStatus({
    required this.ambiente,
    required this.userId,
    required this.password,
    this.host,
    this.port,
    required this.origen,
  });

  bool get isOverride => origen.toLowerCase() == 'override';

  factory OracleCredentialStatus.fromJson(Map<String, dynamic> json) {
    return OracleCredentialStatus(
      ambiente: json['ambiente']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      host: json['host']?.toString(),
      port: json['port']?.toString(),
      origen: json['origen']?.toString() ?? 'Config',
    );
  }

  Map<String, dynamic> toJson() => {
    'ambiente': ambiente,
    'userId': userId,
    'password': password,
    if (host != null) 'host': host,
    if (port != null) 'port': port,
    'origen': origen,
  };

  OracleCredentialStatus copyWith({
    String? ambiente,
    String? userId,
    String? password,
    String? host,
    String? port,
    String? origen,
  }) {
    return OracleCredentialStatus(
      ambiente: ambiente ?? this.ambiente,
      userId: userId ?? this.userId,
      password: password ?? this.password,
      host: host ?? this.host,
      port: port ?? this.port,
      origen: origen ?? this.origen,
    );
  }
}

/// Registro en el historial de auditoría de cambios de credenciales Oracle.
class OracleCredencialHistorialEntry {
  final String id;
  final String ambiente;
  final String cdUsuario;
  final DateTime fechaCambioUtc;
  final String accion; // "Actualizar" o "Restablecer"
  final String userIdAntes;
  final String passwordAntes;
  final String userIdDespues;
  final String passwordDespues;
  final String? hostAntes;
  final String? puertoAntes;
  final String? hostDespues;
  final String? puertoDespues;

  const OracleCredencialHistorialEntry({
    required this.id,
    required this.ambiente,
    required this.cdUsuario,
    required this.fechaCambioUtc,
    required this.accion,
    required this.userIdAntes,
    required this.passwordAntes,
    required this.userIdDespues,
    required this.passwordDespues,
    this.hostAntes,
    this.puertoAntes,
    this.hostDespues,
    this.puertoDespues,
  });

  factory OracleCredencialHistorialEntry.fromJson(Map<String, dynamic> json) {
    final rawDate = json['fechaCambioUtc']?.toString();
    DateTime parsedDate;
    if (rawDate != null && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now().toUtc();
    } else {
      parsedDate = DateTime.now().toUtc();
    }

    return OracleCredencialHistorialEntry(
      id: json['id']?.toString() ?? '',
      ambiente: json['ambiente']?.toString() ?? '',
      cdUsuario: json['cdUsuario']?.toString() ?? '',
      fechaCambioUtc: parsedDate,
      accion: json['accion']?.toString() ?? 'Actualizar',
      userIdAntes: json['userIdAntes']?.toString() ?? '',
      passwordAntes: json['passwordAntes']?.toString() ?? '',
      userIdDespues: json['userIdDespues']?.toString() ?? '',
      passwordDespues: json['passwordDespues']?.toString() ?? '',
      hostAntes: json['hostAntes']?.toString(),
      puertoAntes: json['puertoAntes']?.toString(),
      hostDespues: json['hostDespues']?.toString(),
      puertoDespues: json['puertoDespues']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ambiente': ambiente,
    'cdUsuario': cdUsuario,
    'fechaCambioUtc': fechaCambioUtc.toIso8601String(),
    'accion': accion,
    'userIdAntes': userIdAntes,
    'passwordAntes': passwordAntes,
    'userIdDespues': userIdDespues,
    'passwordDespues': passwordDespues,
    if (hostAntes != null) 'hostAntes': hostAntes,
    if (puertoAntes != null) 'puertoAntes': puertoAntes,
    if (hostDespues != null) 'hostDespues': hostDespues,
    if (puertoDespues != null) 'puertoDespues': puertoDespues,
  };
}

/// Contenedor paginado del historial de auditoría.
class OracleCredencialHistorialPagedResult {
  final List<OracleCredencialHistorialEntry> items;
  final int total;
  final int pagina;
  final int top;

  const OracleCredencialHistorialPagedResult({
    required this.items,
    required this.total,
    required this.pagina,
    required this.top,
  });

  factory OracleCredencialHistorialPagedResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return OracleCredencialHistorialPagedResult(
      items: rawItems
          .map(
            (e) => OracleCredencialHistorialEntry.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? rawItems.length,
      pagina: (json['pagina'] as num?)?.toInt() ?? 1,
      top: (json['top'] as num?)?.toInt() ?? 50,
    );
  }
}
