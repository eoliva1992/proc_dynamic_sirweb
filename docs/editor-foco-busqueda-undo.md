# Editor Monaco — foco de la búsqueda (Ctrl+F) y deshacer (Ctrl+Z)

## Síntoma

En el editor de procedimientos dinámicos:

- Al pulsar **Ctrl+F** el widget de búsqueda se abre, pero el foco se queda en el
  código: lo que se escribe va al documento en vez de al campo de búsqueda.
- **Ctrl+Z** no deshace.

## Qué lo rompió

Todo entró en el commit `a51da52` (el refactor grande del panel):

1. **`interactionEnabled: !_suppressFocusRecovery`** en `MonacoEditor`.
   Cada clic derecho ponía la interacción en `false` durante hasta 4 s para que
   el `pointerDown` interno de `flutter_monaco` no cerrara el menú contextual.
   El efecto colateral es grave, porque en `flutter_monaco 3.4.3`
   `interactionEnabled == false` implica:
   - `Focus(canRequestFocus: false)` sobre el WebView (`monaco_editor_view.dart`),
   - el `onPointerDown` de recuperación de foco hace `return` inmediato,
   - `FocusCoordinator.ensureFocus` aborta (`if (!_isInteractionEnabled()) return;`).

   En Windows `WebViewController.setInteractionEnabled` es un no-op, así que el
   daño es puramente del lado Flutter: el WebView2 se queda sin ruta de teclado.

2. **`isFindOpen()` ampliado** a `document.querySelector(".monaco-menu-container")`.
   Monaco conserva ese contenedor en el DOM, así que el guard quedaba
   permanentemente activo y bloqueaba **todo** `focus()` parcheado.

## Solución aplicada

En `lib/widgets/code_editor_panel.dart`:

- Se eliminó `_suppressFocusRecovery` / `_ctxMenuSuppressTimer` /
  `_focusChangedSub` y los toasts de diagnóstico. `interactionEnabled` queda en
  su valor por defecto (`true`).
- `isFindOpen()` vuelve a ser estrecho: `.find-widget.visible`, más una ventana
  temporal (`window.__fmFindWanted`, 1.5 s) mientras Monaco todavía no marcó el
  widget como visible.
- Se parchea **`window.flutterMonaco.forceFocus` / `.focus`**, que es lo que
  invoca realmente el bridge desde Dart, además de `window.focus`,
  `document.body.focus`, `editor.focus` y el `inputarea` / `native-edit-context`
  (defensa en profundidad).
- `window.__fmOpenFind()` abre `actions.find` y **persigue** el foco del input
  durante ~600 ms, porque Monaco lo crea de forma asíncrona.
- Acciones Monaco explícitas: `custom.undo` (Ctrl+Z), `custom.redo`
  (Ctrl+Y y Ctrl+Shift+Z) y `custom.find` (Ctrl+F). Se ejecutan contra el
  editor (`editor.trigger`), no contra `document.activeElement`.
- Se completó el menú contextual Flutter (`showMenu`), que estaba a medias:
  `_CtxMenuAction` y `_editorAreaKey` no se usaban y el JS hace
  `preventDefault()` en `contextmenu`, así que el clic derecho no abría nada.

## Efecto colateral: pegar dentro del campo de búsqueda

Las acciones `custom.clipboard.copy/cut/paste` (Ctrl+C/X/V) y `custom.undo`
están registradas **en el editor**, así que Monaco las dispara aunque el foco
esté en el campo de buscar o reemplazar. El resultado era que pegar el término
de búsqueda lo escribía dentro del código.

La solución es un desvío en JS: `window.__fmAuxInput()` devuelve el
`<input>`/`<textarea>` enfocado que **no** es el área de edición del código
(descarta `inputarea` y `native-edit-context`). Con eso:

| Acción            | Foco en el código        | Foco en buscar/reemplazar        |
| ----------------- | ------------------------ | -------------------------------- |
| Ctrl+V            | `executeEdits` en Monaco | `__fmAuxInsert` + evento `input` |
| Ctrl+C            | selección del modelo     | `__fmAuxSelection(false)`        |
| Ctrl+X            | `executeEdits` + undo stop | `__fmAuxSelection(true)`       |
| Ctrl+Z / Ctrl+Y   | `editor.trigger`         | `document.execCommand`           |

El evento `input` sintético es imprescindible: es lo que hace que Monaco
relance la búsqueda con el texto pegado.

## Cómo verificarlo en vivo

La app registra en **debug** la extensión de servicio `ext.sirweb.evalJs`
(`main.dart` → `CodeEditorPanel.registerDebugEvalExtension()`), que evalúa
JavaScript dentro del WebView2 del editor activo.

Con la app corriendo y **un procedimiento abierto**:

```
ext.sirweb.evalJs  { "js": "(()=>JSON.stringify({
  hasEditor: !!window.editor,
  apiPatched: !!(window.flutterMonaco && window.flutterMonaco.__fp),
  openFind: typeof window.__fmOpenFind,
  findVisible: !!document.querySelector('.find-widget.visible'),
  active: document.activeElement && document.activeElement.className
}))()" }
```

Valores esperados con los parches instalados:

| Campo        | Esperado                                  |
| ------------ | ----------------------------------------- |
| `hasEditor`  | `true`                                    |
| `apiPatched` | `true`                                    |
| `openFind`   | `"function"`                              |
| `active`     | input del find tras Ctrl+F, no `inputarea` |

Si `apiPatched` es `false`, los parches JS no llegaron a instalarse: revisar
`_installEditorPatches` (se lanza con `unawaited` desde `_setupEditorExtras`).


