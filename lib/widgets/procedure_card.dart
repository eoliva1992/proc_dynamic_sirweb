import 'package:flutter/material.dart';
import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import 'config_badge.dart';

class ProcedureCard extends StatelessWidget {
  final Procedimiento procedimiento;
  final VoidCallback onTap;

  const ProcedureCard({
    super.key,
    required this.procedimiento,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF252526) : Colors.white;
    final titleColor = isDark ? const Color(0xFFD4D4D4) : Colors.black87;
    final metaColor = isDark ? const Color(0xFF808080) : Colors.black45;

    final provider = procedimientosProvider;
    final configDesc = provider.descriptionForConfig(
      procedimiento.inConfiguracion,
    );

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      procedimiento.cdProcedimiento,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        fontFamily: 'Consolas',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (procedimiento.feModificacion != null) ...[
                          Icon(Icons.access_time, size: 11, color: metaColor),
                          const SizedBox(width: 3),
                          Text(
                            procedimiento.feModificacion!,
                            style: TextStyle(color: metaColor, fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (procedimiento.cdUsuario != null) ...[
                          Icon(
                            Icons.person_outline,
                            size: 11,
                            color: metaColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            procedimiento.cdUsuario!,
                            style: TextStyle(color: metaColor, fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Descripción de la configuración
                        Text(
                          configDesc,
                          style: TextStyle(
                            color: metaColor,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConfigBadge(config: procedimiento.inConfiguracion, small: true),
              const SizedBox(width: 8),
              _VersionBadge(version: procedimiento.version),
              const SizedBox(width: 8),
              _EstadoBadge(activo: procedimiento.activo),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: isDark ? const Color(0xFF606060) : Colors.black38,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final int version;
  const _VersionBadge({required this.version});

  @override
  Widget build(BuildContext context) {
    return Text(
      'v$version',
      style: const TextStyle(
        color: Color(0xFF569CD6),
        fontSize: 11,
        fontFamily: 'Consolas',
      ),
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  final bool activo;
  const _EstadoBadge({required this.activo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: activo
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: activo ? Colors.green.shade700 : Colors.red.shade700,
          width: 0.5,
        ),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: activo ? Colors.green.shade400 : Colors.red.shade400,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
