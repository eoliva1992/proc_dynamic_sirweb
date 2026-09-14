import 'chat_message.dart';

/// Un paso del plan que redacta Copilot en modo **Plan**.
class PlanStep {
  /// Texto del paso, ya sin numeración ni marcado.
  final String title;

  const PlanStep(this.title);

  @override
  bool operator ==(Object other) => other is PlanStep && other.title == title;

  @override
  int get hashCode => title.hashCode;

  @override
  String toString() => 'PlanStep($title)';
}

/// Plan extraído de una respuesta en modo Plan.
class ChatPlan {
  final List<PlanStep> steps;

  const ChatPlan(this.steps);

  bool get isEmpty => steps.isEmpty;
  bool get isNotEmpty => steps.isNotEmpty;
  int get length => steps.length;
}

/// Longitud máxima del título de un paso en la barra del compositor.
const _kMaxStepTitle = 90;

/// Numeración al principio de un encabezado: `1.`, `2)`, `Paso 3:`, `Step 4 -`.
final _encabezadoNumerado = RegExp(
  r'^\s*(?:(?:paso|step|fase)\s*)?\d+\s*[.)\-:]\s*',
  caseSensitive: false,
);

/// Casilla de tarea al principio de una viñeta: `[ ]`, `[x]`.
final _casilla = RegExp(r'^\s*\[[ xX]?\]\s*');

/// Extrae los pasos de una respuesta de Copilot.
///
/// El modo Plan pide «un plan numerado», pero el modelo no siempre obedece al
/// pie de la letra: unas veces numera una lista, otras usa encabezados
/// (`### 1. Revisar el cursor`) y otras casillas de tarea. Se prueban las tres
/// formas **en orden de fiabilidad** en vez de exigir una sola, porque de eso
/// depende que aparezca la barra de acciones.
///
/// Devuelve un plan vacío si no hay al menos dos pasos: un único punto casi
/// nunca es un plan, sino una enumeración dentro de una explicación.
ChatPlan parsePlan(String content) {
  final bloques = parseMarkdownBlocks(content);

  // 1) Lista numerada de primer nivel: el formato que se pide al modelo.
  final numerados = <PlanStep>[];
  for (final b in bloques) {
    if (b.kind == MdBlockKind.numbered && b.level == 0) {
      final t = _limpiar(b.text);
      if (t.isNotEmpty) numerados.add(PlanStep(t));
    }
  }
  if (numerados.length >= 2) return ChatPlan(numerados);

  // 2) Encabezados numerados: `## 1. Revisar el cursor`, `### Paso 2: …`.
  final encabezados = <PlanStep>[];
  for (final b in bloques) {
    if (b.kind != MdBlockKind.heading) continue;
    if (!_encabezadoNumerado.hasMatch(b.text)) continue;
    final t = _limpiar(b.text.replaceFirst(_encabezadoNumerado, ''));
    if (t.isNotEmpty) encabezados.add(PlanStep(t));
  }
  if (encabezados.length >= 2) return ChatPlan(encabezados);

  // 3) Casillas de tarea: `- [ ] Revisar el cursor`.
  final tareas = <PlanStep>[];
  for (final b in bloques) {
    if (b.kind != MdBlockKind.bullet || b.level != 0) continue;
    if (!_casilla.hasMatch(b.text)) continue;
    final t = _limpiar(b.text.replaceFirst(_casilla, ''));
    if (t.isNotEmpty) tareas.add(PlanStep(t));
  }
  if (tareas.length >= 2) return ChatPlan(tareas);

  // 4) Último recurso: una lista con viñetas de primer nivel. En modo Plan la
  // respuesta *es* el plan, así que una lista suelta sigue siendo accionable.
  final vinetas = <PlanStep>[];
  for (final b in bloques) {
    if (b.kind != MdBlockKind.bullet || b.level != 0) continue;
    final t = _limpiar(b.text);
    if (t.isNotEmpty) vinetas.add(PlanStep(t));
  }
  if (vinetas.length >= 2) return ChatPlan(vinetas);

  return const ChatPlan([]);
}

/// Deja el título legible en una sola línea y sin marcado.
String _limpiar(String texto) {
  var t = texto
      .replaceAll(RegExp(r'\*\*|__|`|#'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Un paso suele venir como «Título: detalle largo»; en la barra basta el
  // título, que es lo que identifica el hito.
  final dosPuntos = t.indexOf(': ');
  if (dosPuntos > 3 && dosPuntos < _kMaxStepTitle) {
    t = t.substring(0, dosPuntos);
  }
  if (t.length > _kMaxStepTitle) {
    t = '${t.substring(0, _kMaxStepTitle - 1).trimRight()}…';
  }
  return t;
}
