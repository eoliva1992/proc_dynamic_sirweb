import 'package:flutter/material.dart';

/// Editor de lista de artefactos con Chips interactivos, soporte para:
/// - Agregar elementos presionando Enter o botón "+"
/// - Pegar texto separado por comas (división automática y eliminación de duplicados)
/// - Eliminar ítems individuales con botón (x)
/// - Botón para limpiar todos los elementos
/// - Contador visual con badge temático
class ArtifactListEditor extends StatefulWidget {
  final String title;
  final String hintText;
  final IconData icon;
  final Color color;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String? emptyMessage;
  final ValueChanged<String>? onItemTap;
  final Widget? trailingHeaderAction;

  const ArtifactListEditor({
    super.key,
    required this.title,
    required this.hintText,
    required this.icon,
    required this.color,
    required this.items,
    required this.onChanged,
    this.emptyMessage,
    this.onItemTap,
    this.trailingHeaderAction,
  });

  @override
  State<ArtifactListEditor> createState() => _ArtifactListEditorState();
}

class _ArtifactListEditorState extends State<ArtifactListEditor> {
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addItemFromInput() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final updated = List<String>.from(widget.items);
    // Soporte para texto con comas pegado o tipeado
    final parts = text.split(',');
    for (final raw in parts) {
      final clean = raw.trim();
      if (clean.isNotEmpty && !updated.contains(clean)) {
        updated.add(clean);
      }
    }

    _inputCtrl.clear();
    widget.onChanged(updated);
    _focusNode.requestFocus();
  }

  void _removeItem(int index) {
    if (index < 0 || index >= widget.items.length) return;
    final updated = List<String>.from(widget.items)..removeAt(index);
    widget.onChanged(updated);
  }

  void _clearAll() {
    widget.onChanged(const []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF22242B) : const Color(0xFFFAFAFC);
    final borderColor = isDark ? const Color(0xFF33353F) : Colors.grey.shade300;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de título con contador y botón de limpiar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(widget.icon, size: 16, color: widget.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${widget.items.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: widget.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailingHeaderAction != null) ...[
                widget.trailingHeaderAction!,
                const SizedBox(width: 4),
              ],
              if (widget.items.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: const Size(50, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.clear_all_rounded, size: 14),
                  label: const Text('Limpiar', style: TextStyle(fontSize: 11)),
                  onPressed: _clearAll,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Campo para agregar elementos
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _focusNode,
                    onSubmitted: (_) => _addItemFromInput(),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade500,
                      ),
                      prefixIcon: const Icon(Icons.add_rounded, size: 17),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E1F25)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: widget.color, width: 1.2),
                      ),
                      suffixIcon: _inputCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () =>
                                  setState(() => _inputCtrl.clear()),
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  minimumSize: const Size(60, 36),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar', style: TextStyle(fontSize: 12)),
                onPressed: _inputCtrl.text.trim().isNotEmpty
                    ? _addItemFromInput
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Contenedor de Chips o estado vacío
          if (widget.items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                  style: BorderStyle.solid,
                ),
              ),
              child: Text(
                widget.emptyMessage ??
                    'No hay elementos agregados. Escribe o pega texto arriba y presiona Enter.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(widget.items.length, (idx) {
                final item = widget.items[idx];
                return Container(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 3,
                    top: 2,
                    bottom: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: widget.onItemTap != null
                            ? () => widget.onItemTap!(item)
                            : null,
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            decoration: widget.onItemTap != null
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationStyle: TextDecorationStyle.dotted,
                            color: isDark ? Colors.white : Colors.grey.shade900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _removeItem(idx),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}
