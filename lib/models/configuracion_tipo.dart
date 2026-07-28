class ConfiguracionTipo {
  final String cdModulo;
  final String deArgumento;

  const ConfiguracionTipo({
    required this.cdModulo,
    required this.deArgumento,
  });

  factory ConfiguracionTipo.fromJson(Map<String, dynamic> json) {
    return ConfiguracionTipo(
      cdModulo: json['cd_modulo']?.toString() ?? '',
      deArgumento: json['de_argumento']?.toString() ?? '',
    );
  }

  String get label => '$cdModulo — $deArgumento';
}
