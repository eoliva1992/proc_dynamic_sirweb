class Procedimiento {
  final String cdProcedimiento;
  final String deTexto;
  final String inConfiguracion;
  final int version;
  final String stProcedimiento;
  final String? feModificacion;
  final String? cdUsuario;

  const Procedimiento({
    required this.cdProcedimiento,
    required this.deTexto,
    required this.inConfiguracion,
    required this.version,
    required this.stProcedimiento,
    this.feModificacion,
    this.cdUsuario,
  });

  bool get activo => stProcedimiento == '1';

  factory Procedimiento.fromJson(Map<String, dynamic> json) {
    final versionRaw = json['version'];
    return Procedimiento(
      cdProcedimiento: json['cdProcedimiento']?.toString() ?? '',
      deTexto: json['deTexto']?.toString() ?? '',
      inConfiguracion: json['inConfiguracion']?.toString() ?? '',
      version: versionRaw is int
          ? versionRaw
          : int.tryParse(versionRaw?.toString() ?? '') ?? 0,
      stProcedimiento: json['stProcedimiento']?.toString() ?? '1',
      feModificacion: json['feModificacion']?.toString(),
      cdUsuario: json['cdUsuario']?.toString(),
    );
  }

  Procedimiento copyWith({
    String? cdProcedimiento,
    String? deTexto,
    String? inConfiguracion,
    int? version,
    String? stProcedimiento,
    String? feModificacion,
    String? cdUsuario,
  }) {
    return Procedimiento(
      cdProcedimiento: cdProcedimiento ?? this.cdProcedimiento,
      deTexto: deTexto ?? this.deTexto,
      inConfiguracion: inConfiguracion ?? this.inConfiguracion,
      version: version ?? this.version,
      stProcedimiento: stProcedimiento ?? this.stProcedimiento,
      feModificacion: feModificacion ?? this.feModificacion,
      cdUsuario: cdUsuario ?? this.cdUsuario,
    );
  }
}
