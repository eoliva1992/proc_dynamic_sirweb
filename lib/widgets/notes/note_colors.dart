import 'package:flutter/material.dart';

/// Sticky-note style accent palette inspired by Windows 11 Sticky Notes,
/// tuned for both Light and Dark modes with optimal contrast and readability.
class NoteColor {
  final String name;
  final Color lightBg;
  final Color darkBg;
  final Color lightHeader;
  final Color darkHeader;
  final Color lightFg;
  final Color darkFg;

  const NoteColor({
    required this.name,
    required this.lightBg,
    required this.darkBg,
    required this.lightHeader,
    required this.darkHeader,
    required this.lightFg,
    required this.darkFg,
  });

  Color bg(bool isDark) => isDark ? darkBg : lightBg;
  Color header(bool isDark) => isDark ? darkHeader : lightHeader;
  Color fg(bool isDark) => isDark ? darkFg : lightFg;
  Color subFg(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.65) : Colors.black54;
  Color border(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.08);
}

const List<NoteColor> kNoteColors = [
  // Amarillo clásico Sticky Notes (Calibrado Fluent)
  NoteColor(
    name: 'Amarillo',
    lightBg: Color(0xFFFFF9DB),
    darkBg: Color(0xFF322C1A),
    lightHeader: Color(0xFFFDECA8),
    darkHeader: Color(0xFF262112),
    lightFg: Color(0xFF272418),
    darkFg: Color(0xFFFBF4D8),
  ),
  // Mandarina / Naranja
  NoteColor(
    name: 'Naranja',
    lightBg: Color(0xFFFFEEDD),
    darkBg: Color(0xFF35251B),
    lightHeader: Color(0xFFFBDCB9),
    darkHeader: Color(0xFF281C13),
    lightFg: Color(0xFF2E2218),
    darkFg: Color(0xFFFAF0E5),
  ),
  // Fresa / Rosa pastel
  NoteColor(
    name: 'Rosa',
    lightBg: Color(0xFFFFE4EF),
    darkBg: Color(0xFF341E2A),
    lightHeader: Color(0xFFFACAE0),
    darkHeader: Color(0xFF27151F),
    lightFg: Color(0xFF331C27),
    darkFg: Color(0xFFFDEAF3),
  ),
  // Lavanda / Violeta
  NoteColor(
    name: 'Lavanda',
    lightBg: Color(0xFFEFE8FF),
    darkBg: Color(0xFF272038),
    lightHeader: Color(0xFFE2D5FF),
    darkHeader: Color(0xFF1D172A),
    lightFg: Color(0xFF251C33),
    darkFg: Color(0xFFF5EFFF),
  ),
  // Cielo / Celeste
  NoteColor(
    name: 'Celeste',
    lightBg: Color(0xFFE5F5FF),
    darkBg: Color(0xFF192735),
    lightHeader: Color(0xFFCEEBFE),
    darkHeader: Color(0xFF131D28),
    lightFg: Color(0xFF172430),
    darkFg: Color(0xFFEEF7FD),
  ),
  // Pistacho / Menta
  NoteColor(
    name: 'Menta',
    lightBg: Color(0xFFE6FAF0),
    darkBg: Color(0xFF1C3122),
    lightHeader: Color(0xFFCFF4DE),
    darkHeader: Color(0xFF142419),
    lightFg: Color(0xFF18291D),
    darkFg: Color(0xFFEDFAF2),
  ),
  // Carbón / Pizarra neutro
  NoteColor(
    name: 'Gris',
    lightBg: Color(0xFFF2F2F2),
    darkBg: Color(0xFF242424),
    lightHeader: Color(0xFFE4E4E4),
    darkHeader: Color(0xFF1B1B1B),
    lightFg: Color(0xFF1E1E1E),
    darkFg: Color(0xFFECECEC),
  ),
];

/// Deterministic color index for a note, derived from a stable seed (its
/// server id when persisted, or title as fallback for brand-new notes).
int noteColorIndexFor(String seed) {
  if (seed.isEmpty) return 0;
  var hash = 0;
  for (final codeUnit in seed.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash % kNoteColors.length;
}

NoteColor noteColorEntryFor(String seed) {
  return kNoteColors[noteColorIndexFor(seed)];
}

Color noteColorFor(String seed, {required bool isDark}) {
  return noteColorEntryFor(seed).bg(isDark);
}
