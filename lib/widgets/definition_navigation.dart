import 'package:flutter/material.dart';

import '../models/procedimiento.dart';
import '../providers/procedimientos_provider.dart';
import '../services/schema_navigation_helper.dart';
import '../services/sirweb_service.dart';
import 'app_toast.dart';
import 'schema_object_details_sheet.dart';
import 'source_float_window.dart';
import 'source_tab_controller.dart';

/// Resuelve y abre definiciones Oracle o procedimientos dinámicos.
///
/// Si el mismo identificador existe en ambos catálogos, permite elegir cuál
/// abrir. La búsqueda dinámica usa primero los resultados en memoria y luego
/// consulta el backend por código.
Future<void> navigateToDefinition(
  BuildContext context,
  String rawWord, {
  required String ambiente,
  void Function(String name, String objectType)? onOpenSchema,
}) async {
  final word = rawWord.trim().replaceAll('"', '');
  if (word.isEmpty) return;

  final schemaMatch = await resolveSchemaDefinition(word, ambiente: ambiente);
  if (!context.mounted) return;

  final dynamicMatch = await _findDynamicProcedure(word, ambiente);
  if (!context.mounted) return;

  if (schemaMatch != null && dynamicMatch != null) {
    final choice = await showDialog<_DefinitionChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Se encontraron dos definiciones para "$word"'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _DefinitionChoice.schema),
            child: Text('Objeto Oracle (${schemaMatch.objectType})'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _DefinitionChoice.dynamic),
            child: Text(
              'Procedimiento dinámico (${dynamicMatch.cdProcedimiento})',
            ),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == _DefinitionChoice.schema) {
      _openSchema(
        context,
        schemaMatch.name,
        schemaMatch.objectType,
        ambiente,
        onOpenSchema,
      );
    } else {
      _openDynamic(context, dynamicMatch.cdProcedimiento, ambiente);
    }
    return;
  }

  if (schemaMatch != null) {
    _openSchema(
      context,
      schemaMatch.name,
      schemaMatch.objectType,
      ambiente,
      onOpenSchema,
    );
  } else if (dynamicMatch != null) {
    _openDynamic(context, dynamicMatch.cdProcedimiento, ambiente);
  } else {
    AppToast.info('No se encontró definición para "$word"');
  }
}

Future<Procedimiento?> _findDynamicProcedure(String word, String ambiente) async {
  // Los identificadores cualificados (p. ej. PKG.PROC) pertenecen al esquema;
  // un código de procedimiento dinámico es un identificador simple.
  if (!RegExp(r'^[A-Za-z0-9_$#]+$').hasMatch(word)) return null;
  final code = word.toUpperCase();

  final current = procedimientosProvider.procedimientoActual;
  if (current?.cdProcedimiento.toUpperCase() == code) return current;
  for (final procedure in procedimientosProvider.resultados) {
    if (procedure.cdProcedimiento.toUpperCase() == code) return procedure;
  }

  try {
    return await SirwebService().obtenerProcedimiento(
      code,
      ambiente: ambiente,
    );
  } catch (error) {
    debugPrint('[GotoDef] No se encontró procedimiento dinámico "$code": $error');
    return null;
  }
}

void _openSchema(
  BuildContext context,
  String name,
  String objectType,
  String ambiente,
  void Function(String name, String objectType)? onOpenSchema,
) {
  if (objectType == 'TABLE') {
    showObjectDetails(
      context,
      name: name,
      type: objectType,
      ambiente: ambiente,
    );
    return;
  }

  if (onOpenSchema != null) {
    onOpenSchema(name, objectType);
  } else {
    openSourceWindow(
      context,
      name: name,
      objectType: objectType,
      ambiente: ambiente,
    );
  }
}

void _openDynamic(BuildContext context, String code, String ambiente) {
  final openTab = DynamicProcedureTabController.openTabOf(context);
  if (openTab == null) {
    AppToast.info('No se pudo abrir el procedimiento dinámico "$code".');
    return;
  }
  openTab(cdProcedimiento: code, ambiente: ambiente);
}

enum _DefinitionChoice { schema, dynamic }