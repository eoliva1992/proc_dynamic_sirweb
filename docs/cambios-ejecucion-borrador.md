# Ejecución de procedimientos dinámicos: borrador (editor) vs guardado (consulta)

Fecha: 2026-09-06

## Objetivo

Diferenciar **desde dónde** se dispara la ejecución de un procedimiento dinámico:

| Origen | Endpoint | Qué se envía |
|---|---|---|
| **Editor** (código abierto en Monaco) | `POST /tools/procedimiento-dinamico/ejecutar-borrador` | El **código actual del editor** (`deTexto` + `inConfiguracion`) + el contexto |
| **Consulta** (tarjeta de resultados de búsqueda) | `POST /tools/procedimiento-dinamico/{cdProcedimiento}/ejecutar` | Sólo el **nombre**; el backend lee el texto guardado en `PROCEDIMIENTODINAMICO` |

Así se puede probar lo que está escrito **sin guardarlo** cuando se trabaja en el editor,
y ejecutar la versión persistida cuando se navega la consulta.

---

## Contratos REST

### Borrador (editor)

```
POST http://localhost:5179/tools/procedimiento-dinamico/ejecutar-borrador
Content-Type: application/json

{
  "deTexto": "BEGIN ... END;",
  "inConfiguracion": "D",
  "cdEntidad": 1, "nuCotizacion": null, "nuItem": null, "cdArea": null,
  "nuPoliza": null, "nuCertificado": null, "nuEndoso": null,
  "nuSiniestro": null, "nuMovimiento": null, "nuInspeccion": null,
  "nuBienAsegurado": null,
  "inAccion": null, "vaDato": null, "stringDatos": null, "stringMatriz": null,
  "camposAdicionales": null, "tipoContexto": null,
  "ambiente": null, "timeoutSegundos": null,
  "capturarVariables": null
}
```

### Guardado (consulta)

```
POST http://localhost:5179/tools/procedimiento-dinamico/{cdProcedimiento}/ejecutar
Content-Type: application/json

{ ...mismo cuerpo, sin deTexto ni inConfiguracion }
```

La respuesta es idéntica en ambos casos: envelope `{ success, message, error, data }`
con `data` → `EjecucionResultado`:

```json
{
  "success": true, "message": null, "error": null,
  "data": {
    "ambiente": "Desa", "cdProcedimiento": "DR_TEST", "borrador": true,
    "inConfiguracion": "D", "stProcedimiento": "1", "orquestador": "…",
    "contexto": {
      "tipo": "COTIZACION", "record": "r_cotizacion",
      "camposDesdeBd": { "CD_PRODUCTO": "10" },
      "camposSobreescritos": ["CD_AREA"],
      "camposSinResolver": ["NU_ENDOSO"]
    },
    "salidas": { "VA_RESULTADO": "OK" },
    "variablesDinamicasUsadas": { "#FECHA#": "06/09/2026" },
    "traza": ["…"], "errorOracle": null, "duracionMs": 42,
    "rollback": true, "commitDetectado": false
  }
}
```

Respecto del contrato anterior cambian dos cosas:

- **`borrador`** (`bool`): nuevo, lo confirma el backend cuando ejecutó el texto enviado.
- **`variablesDinamicasUsadas`**: pasó de `["#FECHA#"]` a `{ "#FECHA#": "06/09/2026" }`
  (nombre → valor con el que se reemplazó).

---

## Cambios por archivo

### 1. `lib/models/ejecucion_procedimiento.dart`

Se agregó `toBorradorJson()` sobre `EjecucionRequest`. No se tocaron los campos existentes,
por lo que `toJson()` (18 claves, `null` explícitos) sigue igual.

```dart
/// Contrato del endpoint `POST /tools/procedimiento-dinamico/ejecutar-borrador`.
Map<String, dynamic> toBorradorJson({
  required String deTexto,
  String? inConfiguracion,
}) => {
  'deTexto': deTexto,
  'inConfiguracion': inConfiguracion ?? '',
  ...toJson(),
};
```

### 2. `lib/services/sirweb_service.dart`

- **Nuevo** `ejecutarBorrador({deTexto, inConfiguracion, request})` → `/ejecutar-borrador`.
- `ejecutarProcedimiento(cd, {request})` se mantiene con la misma firma → `/{cd}/ejecutar`.
- Se extrajo la lógica común (POST + timeout dinámico + parseo del envelope + devolver
  `EjecucionResultado` aunque `success == false` para no perder `errorOracle`/`traza`)
  al privado `_postEjecucion(uri, body, timeoutSegundos)`.

```dart
Future<EjecucionResultado> ejecutarProcedimiento(String cdProcedimiento, {required EjecucionRequest request}) async {
  final uri = Uri.parse('$_host/tools/procedimiento-dinamico/${Uri.encodeComponent(cdProcedimiento)}/ejecutar');
  return _postEjecucion(uri, request.toJson(), request.timeoutSegundos);
}

Future<EjecucionResultado> ejecutarBorrador({
  required String deTexto,
  String? inConfiguracion,
  required EjecucionRequest request,
}) async {
  final uri = Uri.parse('$_host/tools/procedimiento-dinamico/ejecutar-borrador');
  return _postEjecucion(
    uri,
    request.toBorradorJson(deTexto: deTexto, inConfiguracion: inConfiguracion),
    request.timeoutSegundos,
  );
}
```

El timeout de red sigue siendo `timeoutSegundos + 15` para cubrir el viaje de red y el
armado del contexto.

### 3. `lib/widgets/_editor_ejecutar_modal.dart`

- `_EjecutarProcedimientoModal` recibe un nuevo parámetro opcional
  `Future<String?> Function()? obtenerTexto`. **Ese callback es el que decide el endpoint.**
- `_ejecutar()` bifurca:
  - `obtenerTexto != null` → lee el código del editor y llama a `ejecutarBorrador`.
    Si el texto viene vacío corta antes de pegarle al backend con el mensaje
    *"El editor está vacío: no hay código para ejecutar."*
  - `obtenerTexto == null` → llama a `ejecutarProcedimiento(cdProcedimiento)`.
- Badge nuevo en el header para que el usuario sepa qué está por ejecutar:
  **“Código del editor”** (naranja) vs **“Código guardado”** (verde).
- Se expuso la función pública `showEjecutarProcedimientoWindow(...)`, porque los modales
  del editor son `part of 'code_editor_panel.dart'` y la consulta necesitaba abrir la
  misma ventana. `_showEjecutarProcedimientoModal(...)` quedó como alias interno.

```dart
void showEjecutarProcedimientoWindow(
  BuildContext context,
  String cdProcedimiento,
  String ambiente, {
  String? inConfiguracion,
  Future<String?> Function()? obtenerTexto,
});
```

El resto de la ventana (persistencia de parámetros en `SharedPreferences`, minimizar /
maximizar, pestañas Salidas / Traza / Contexto / Variables, copiado a JSON) no cambió.

### 4. `lib/widgets/_editor_navigation.dart`

`_ejecutarProcedimiento()` ahora pasa el texto vivo del editor:

```dart
_showEjecutarProcedimientoModal(
  context,
  cd,
  widget.ambiente,
  inConfiguracion: activeProc.inConfiguracion,
  obtenerTexto: () async =>
      await _withCtrl((ctrl) => ctrl.document.getText()) ?? activeProc.deTexto,
);
```

`_withCtrl` devuelve `null` si el controller de Monaco ya fue destruido; en ese caso se
cae al `deTexto` del procedimiento activo en vez de fallar.

Se mantiene el disparador existente: acción del menú contextual de Monaco y **Alt+R**.

### 5. `lib/widgets/procedure_card.dart` (vista de consulta)

- Import acotado: `import 'code_editor_panel.dart' show showEjecutarProcedimientoWindow;`
- Nuevo método `_ejecutarProcedimiento()` que abre la ventana **sin** `obtenerTexto`
  (⇒ endpoint por nombre), usando `procedimientosProvider.ambiente`.
- Nueva entrada **“Ejecutar”** en el menú contextual (segunda posición, después de
  “Ver fuente”) y guarda `if (!mounted) return;` al resolver el menú.
- Nuevo botón inline ▶ en la fila de acciones de la tarjeta (verde `0xFF16A34A`), con el
  mismo patrón de `AnimatedOpacity` según hover que el resto de los íconos.
- `enum _CardAction` pasó a `{ viewSource, ejecutar, openInNewTab, copyName, copyAsCall, backup }`.

### 6. `test/ejecucion_procedimiento_test.dart`

Se agregó el grupo `EjecucionRequest.toBorradorJson`:

- verifica que `deTexto` e `inConfiguracion` se sumen al contrato de contexto (20 claves);
- verifica que `inConfiguracion` viaje como `''` cuando no se conoce.

---

## Verificación

- `flutter test test/ejecucion_procedimiento_test.dart` → **7/7 OK**.
- `flutter analyze lib test` → sin diagnósticos nuevos en los archivos tocados
  (los `info` que aparecen son preexistentes del resto del proyecto).

## Cómo probarlo

1. **Editor**: abrir un procedimiento, modificar el código sin guardar, `Alt+R` → la ventana
   muestra el badge *Código del editor* y ejecuta el borrador.
2. **Consulta**: buscar el procedimiento, clic derecho → **Ejecutar** (o el botón ▶ de la
   tarjeta) → la ventana muestra *Código guardado* y ejecuta el texto persistido.

## Pendiente / notas

- El backend debe exponer `POST /tools/procedimiento-dinamico/ejecutar-borrador`; si no
  existe, la ventana mostrará el mensaje de error del envelope.
- Los parámetros de contexto se siguen persistiendo por procedimiento
  (`ejecutar_params_{cdProcedimiento}`), así que se comparten entre ambos modos.

