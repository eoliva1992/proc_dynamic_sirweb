class VariableDinamica {
  final String cdVariable;
  final String deVariable;
  final String inConfiguracion;

  const VariableDinamica({
    required this.cdVariable,
    required this.deVariable,
    required this.inConfiguracion,
  });

  factory VariableDinamica.fromJson(Map<String, dynamic> json) {
    return VariableDinamica(
      cdVariable: json['cd_variable']?.toString() ??
          json['cdVariable']?.toString() ??
          '',
      deVariable: json['de_variable']?.toString() ??
          json['deVariable']?.toString() ??
          json['deArgumento']?.toString() ??
          '',
      inConfiguracion: json['in_configuracion']?.toString() ??
          json['inConfiguracion']?.toString() ??
          '',
    );
  }
}
