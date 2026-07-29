part of 'main_screen.dart';

class _UsuarioButton extends StatelessWidget {
  final String cdUsuario;
  final VoidCallback onTap;

  const _UsuarioButton({required this.cdUsuario, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Text(
              cdUsuario.isEmpty ? 'Usuario' : cdUsuario,
              style: TextStyle(
                color: cdUsuario.isEmpty ? Colors.white38 : Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 12, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
