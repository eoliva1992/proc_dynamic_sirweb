part of 'main_screen.dart';

class _UsuarioButton extends StatelessWidget {
  final String cdUsuario;
  final VoidCallback onTap;

  const _UsuarioButton({required this.cdUsuario, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEmpty = cdUsuario.isEmpty;
    return Tooltip(
      message: isEmpty
          ? 'Sin usuario — requerido para guardar'
          : 'Usuario: $cdUsuario',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Badge(
          isLabelVisible: isEmpty,
          label: const Text(
            '!',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.orange.shade600,
          offset: const Offset(2, -2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isEmpty
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: isEmpty
                  ? Border.all(color: Colors.orange.withValues(alpha: 0.5))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEmpty ? Icons.person_off_outlined : Icons.person_outline,
                  size: 14,
                  color: isEmpty ? Colors.orange.shade300 : Colors.white70,
                ),
                const SizedBox(width: 5),
                Text(
                  isEmpty ? 'Sin usuario' : cdUsuario,
                  style: TextStyle(
                    color: isEmpty ? Colors.orange.shade300 : Colors.white70,
                    fontSize: 12,
                    fontWeight: isEmpty ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit,
                  size: 12,
                  color: isEmpty ? Colors.orange.shade400 : Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
