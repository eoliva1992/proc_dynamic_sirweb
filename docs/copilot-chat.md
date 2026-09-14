# Chat con GitHub Copilot en el editor

Panel lateral que conversa con Copilot usando la **CLI oficial** (`@github/copilot`)
como backend. La aplicación nunca gestiona credenciales de GitHub: delega en la
sesión que la CLI guarda en el almacén de credenciales del sistema.

## Arquitectura

```
_AiChatDockedPanel  (UI, part de code_editor_panel.dart)
        │  eventos tipados
        ▼
CopilotCliService   (proceso, sesión, prompt, errores)
        │  JSONL por stdout
        ▼
node npm-loader.js  →  GitHub Copilot CLI
```

| Capa | Archivo | Responsabilidad |
|---|---|---|
| Modelo de eventos | `lib/models/copilot_event.dart` | Normaliza el JSONL de la CLI |
| Modelo de mensaje | `lib/models/chat_message.dart` | Mensajes + parser markdown |
| Plan | `lib/models/chat_plan.dart` | Extrae los pasos del modo Plan |
| Selección | `lib/models/editor_selection.dart` | Rango activo en Monaco (`PROC:112-140`) |
| Resaltado | `lib/models/code_highlight.dart` | Tokenizador PL/SQL + paleta Dark+/Light+ |
| Conversaciones | `lib/models/chat_conversation.dart` | Hilos persistentes + `ChatStore` |
| Servicio | `lib/services/copilot_cli_service.dart` | Proceso, auth, sesión, prompt |
| UI | `lib/widgets/_editor_ai_chat_panel.dart` | Panel, markdown, composer |

## Protocolo de la CLI

Se invoca con `--output-format json`, que emite **JSONL** (un objeto por línea):

| Evento | Uso en la UI |
|---|---|
| `session.mcp_server_status_changed` | Indicador «Conectando …» |
| `session.tools_updated` | Modelo efectivo del turno |
| `assistant.turn_start` | «Generando respuesta» |
| `assistant.message_delta` | **Streaming token a token** (`deltaContent`) |
| `assistant.message` | Contenido final (sustituye a los deltas) |
| `result` | `sessionId`, `exitCode` y consumo (`premiumRequests`) |

Las líneas que no son JSON se descartan sin romper el stream.

## Sesiones reanudables

Cada conversación tiene un UUID:

- **Primer turno** → `--session-id <uuid>`
- **Turnos siguientes** → `--resume=<uuid>`

La CLI conserva el contexto en su propio almacén, así que **no se reenvía el
historial**. Esto reduce mucho el prompt y evita el error *«La línea de comandos
es demasiado larga»*. `sessionStarted` solo se marca al recibir el evento
`result`: reanudar un identificador que la CLI nunca registró haría fallar la
invocación.

## Cancelar una respuesta

Detener el turno tiene un orden **contraintuitivo pero obligatorio**:

1. Refrescar la UI
2. **Matar el proceso**
3. Cancelar la suscripción **sin esperarla**

`askEvents` es un generador `async*` que pasa la vida parado en `await for`
esperando líneas de stdout. Cancelar su suscripción **no devuelve el control
hasta que el generador llega a un `yield`**, cosa que no ocurre mientras el
modelo piensa en silencio. Esperar ese `cancel()` antes de matar el proceso
dejaba el botón colgado para siempre: era el motivo real de que «detener» no
funcionase.

En Windows no basta con `kill`: se lanza **node**, y la CLI crea procesos hijos
que sobreviven al padre y siguen consumiendo la petición, así que se usa
`taskkill /F /T`. Además el servicio marca la cancelación antes de matar, para
que el código de salida distinto de cero **no se muestre como un error**:
cancelar no es fallar.

## Endurecimiento

El agente queda reducido a conversar. Las reglas `--deny-tool` tienen precedencia
sobre `--allow-all-tools`:

```
--allow-all-tools          (obligatorio en modo no interactivo)
--deny-tool=shell --deny-tool=write --deny-tool=url
--disable-builtin-mcps --disallow-temp-dir
--no-custom-instructions
--no-remote --no-remote-export      (no exporta la sesión a GitHub web/móvil)
```

Además se desactivan los servidores MCP del usuario leídos de
`~/.copilot/mcp-config.json`. **Medido:** 14,5 s con ellos frente a 10,0 s sin
ellos, y ninguno aporta nada a un chat de PL/SQL.

## Límite de la línea de comandos

El prompt viaja como argumento. `copilot.cmd` es solo un envoltorio de
`node npm-loader.js`, así que se invoca **Node directamente** y se evita
`cmd.exe`:

| Vía | Límite | Presupuesto usado |
|---|---|---|
| Node (`CreateProcess`) | 32 767 | 20 000 |
| Fallback `copilot.cmd` | 8 191 | 6 000 |

Medido: 45 855 caracteres falla, 20 355 funciona. Pasar el prompt por stdin
(`-p -`) **no** sirve: la CLI lo ignora.

Cuando aun así no cabe, la salida es **seleccionar en el editor el fragmento
relevante**: con selección se envía solo esa parte. El mensaje de error lo dice
explícitamente.

## Autenticación

| Estado | Pantalla |
|---|---|
| CLI ausente | Botón para copiar `npm install -g @github/copilot` |
| Sin sesión | «Iniciar sesión con GitHub» (navegador) o código de dispositivo |
| Bloqueado por la org | Explicación; hay que hablar con el administrador |

El login abre una consola con `copilot login --web-flow`. En Windows se genera un
`.bat` temporal en vez de anidar comillas en `cmd /c start`, porque Dart escapa
las comillas internas como `\"` y `cmd` responde *«… no se reconoce como un
comando»*.

El estado es **optimista**: el token está cifrado en el Credential Manager, así
que no se puede verificar sin gastar una petición. Solo se cae a la pantalla de
acceso cuando una llamada real devuelve 401/403. El bloque **Diagnóstico** muestra
las pistas locales (CLI, configuración, credenciales, cuenta de `oauth.json`).

## Variables de entorno

Se propagan al subproceso si están definidas:

`COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, `COPILOT_GH_HOST`, `GH_HOST`,
`COPILOT_HOME`, `COPILOT_MODEL`, `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`,
`NODE_EXTRA_CA_CERTS`.

## Uso

- **Enter** envía · **Shift+Enter** salta línea · **Esc** detiene
- **Ctrl+L** nueva conversación · **Ctrl+H** abre/cierra el historial
- **↑/↓** navegan el historial de preguntas (caja vacía) o el popup de comandos
- **Tab** acepta el comando resaltado
- `/explicar`, `/corregir`, `/optimizar`, `/documentar`, `/revisar`, `/tests`
- **Selecciona líneas en Monaco** para acotar lo que se envía
- Botón de historial: conversaciones anteriores (se guardan las 25 más recientes)

## La caja de entrada

Reproduce la anatomía del compositor de Copilot Chat en VS Code:

```
  Continuar desde el plan
  [ Implementar ⌄ ] [ Aplicar al documento ] [ Descartar ]
┌──────────────────────────────────────────────┐
│ ›  ○  Optimizar el cursor          (1/4)     │  ← paso del plan
├──────────────────────────────────────────────┤
│ 📄 DR_MI_REGLA:112-140 📌   ⚠ errores ×      │  ← adjuntos
│                                              │
│ Describe qué necesitas                       │  ← entrada
│                                              │
│ ＋ ⚡  Pregunta  ✳ auto  Auto·estándar  ⚙  ↑ │  ← barra
└──────────────────────────────────────────────┘
  🖥 Desa   🛡 Solo lectura             Enter envía
```

- **Adjuntos**: solo lo que viaja de verdad en el prompt.
- **Barra**: `+` contexto · `⚡` comandos · modo · modelo · razonamiento y
  ventana · ajustes · enviar. Controles planos, sin relleno ni bordes.
- **Envío**: con la caja vacía es una flecha apagada; solo se rellena de color
  cuando hay algo que enviar. Mientras se responde pasa a *detener*.
- **Pie fuera de la caja**: equivale al `Local · Default permissions` de
  VS Code. Dice sobre qué ambiente se responde y recuerda que el agente corre
  con `shell`, `write` y `url` denegados.

### Contexto adjunto

| Chip | Contenido | Se puede quitar |
|---|---|---|
| Procedimiento 📌 | La selección de Monaco o, si no hay, el documento completo | **No** |
| `errores` | Resumen de errores de sintaxis y compilación (solo si los hay) | Sí (`copilot_chat_include_errors`) |
| `hilo activo` | La sesión de la CLI se reanudará con `--resume` | — |

**El documento abierto va siempre y no se puede desadjuntar.** Sin él, Copilot
responde sobre PL/SQL genérico en lugar de sobre la regla que se está
editando, que es justo lo que hace útil este panel; un interruptor para
apagarlo solo servía para obtener respuestas peores sin darse cuenta. El chip
lo indica con una chincheta y no tiene ×.

Los errores sí son opcionales, y por eso están separados: preguntar «qué hace
esto» con cuarenta errores de compilación colgando desvía la respuesta.

### Selección: `PROCEDIMIENTO:112-140`

Si hay selección en Monaco, el chip muestra el rango con el formato
`archivo:línea` de VS Code y **solo se envía ese fragmento**. Es más preciso y
gasta mucho menos presupuesto de línea de comandos.

Monaco no notifica los cambios de selección a Dart, así que el chip se refresca
**al entrar el puntero en el compositor y al enfocar la caja**, que es cuando
el usuario lo mira. Sondear con un temporizador costaría un salto al webview
varias veces por segundo para nada.

## Modo Plan: del plan a la implementación

Cuando el último turno es un plan terminado, sobre la caja aparece la barra
**«Continuar desde el plan»**, equivalente al *Proceed from Plan* de VS Code:

| Acción | Qué hace |
|---|---|
| **Implementar** | Pide a Copilot el código final del plan. El desplegable permite acotar a **solo el paso actual** |
| **Aplicar al documento** | Vuelca el último bloque de código de la respuesta sobre el editor |
| **Descartar** | Oculta la barra para seguir conversando |

Dentro de la caja, una franja muestra el **paso actual y el total**
(`Optimizar el cursor (1/4)`); el chevrón despliega la lista completa y se
puede saltar a cualquier paso pulsándolo.

Los pasos **no se inventan**: `parsePlan` los lee de la numeración markdown de
la respuesta, que es justo lo que el modo Plan pide al modelo. Con menos de dos
pasos no se considera un plan y la barra no aparece: un único punto numerado
casi siempre es una enumeración dentro de una explicación, y ofrecer
«Implementar» ahí sería ruido.

Al pulsar **Implementar** el modo cambia a **Agente**. En Plan la CLI vuelve a
redactar pasos en vez de producir el resultado, así que quedarse en Plan habría
devuelto otro plan. La instrucción exige un **único bloque de código** sin
explicaciones, porque la respuesta se va a aplicar sobre el documento: si el
modelo intercala prosa entre fragmentos, no hay forma de saber cuál es el
procedimiento resultante.

### Aplicar sobre el documento abierto

`_applyCodeToDocument` reemplaza **la selección** si la hay y, si no, el
documento entero previa confirmación: reemplazar todo es destructivo, mientras
que acotar una selección ya es una decisión explícita del usuario.

La edición usa `executeEdits` y **no** reescribe el modelo con `setValue`. Es
la diferencia entre poder deshacer y no poder: `setValue` vacía la pila de undo,
mientras que `executeEdits` deja **Ctrl+Z** operativo, que es la red de
seguridad imprescindible cuando quien escribe es un modelo.

### Resaltado de los cambios

Las líneas que escribe Copilot se marcan con `copilot-change-line` (el verde de
«línea añadida» de VS Code, con barra a la izquierda para no confundirlo con el
resaltado de la línea activa), y también en la **regla lateral** y el
**minimapa** para localizarlas sin hacer scroll. Sin esto, un reemplazo largo es
indistinguible del código que ya estaba.

El resaltado **se retira solo a los 20 s**: es un aviso, no un estado. Dejar el
editor pintado de verde el resto de la sesión sería peor que no marcarlo.

## Detalles de interacción

La referencia es Copilot Chat en VS Code; cada decisión tiene un porqué:

| Comportamiento | Motivo |
|---|---|
| **Panel redimensionable** arrastrando su borde izquierdo (320–760 px, doble clic restablece a 400) | 400 px se quedan cortos para leer PL/SQL; el ancho se guarda en `copilot_chat_panel_width` |
| **Auto-scroll solo si la vista está al final** (margen de 40 px) | Si el usuario sube a releer, el streaming no debe arrastrarle abajo |
| Píldora **«Ir al final»** cuando se ha subido | Recupera la posición sin buscar la barra de scroll |
| **Cursor parpadeante** al final de la respuesta en streaming | Distingue «sigue escribiendo» de «se colgó» |
| **Contador de segundos** junto a «Pensando…» | Una espera con cifra se tolera mejor y delata al modelo colgado |
| Acciones del mensaje (**copiar**, **editar y reenviar**, **reintentar**) visibles **al pasar el puntero** | La conversación se lee sin ruido; el hueco se reserva para que el texto no salte |
| **Buscador** en el historial y **confirmación** al eliminar | Evita borrados accidentales y recorrer 25 hilos a mano |
| **Sugerencias** de arranque en la pantalla inicial | Baja la barrera de entrada frente a una caja vacía |
| **Detener** también desde el propio indicador de «Pensando…» | No obliga a recordar `Esc` ni a bajar al compositor |
| Menú **«…»**: copiar el hilo en markdown, vaciarlo, restablecer el ancho | Acciones poco frecuentes que no merecen un icono fijo |

El popup de `/comandos` imita el *suggest widget* del editor: icono, el prefijo
ya tecleado resaltado, la descripción atenuada a la derecha y la pista `Tab` en
la fila seleccionada. Las herramientas que invoca el modo Agente se muestran
como filas «Ejecutando / Ejecutó `herramienta`», igual que los bloques *Ran…*
de VS Code.

## Resaltado de sintaxis

`lib/models/code_highlight.dart` colorea los bloques de código con la paleta de
los temas **Dark+** y **Light+** de VS Code, para que el mismo código se lea
igual en el chat y en el editor.

Es un tokenizador **léxico** —sin gramática ni AST—: solo tiene que colorear un
fragmento de respuesta, no compilarlo. Se implementa a mano en vez de añadir una
dependencia porque el subconjunto necesario es pequeño y así se prueba sin
levantar un widget (`test/code_highlight_test.dart`).

- Un bloque **sin lenguaje se trata como PL/SQL**: en este editor es lo que
  devuelve Copilot casi siempre, y acertar por defecto vale más que ser neutral.
- Distingue palabras clave, tipos, funciones, literales, números, comentarios y
  **bind variables** (`:p_cd_dato`), omnipresentes en las reglas dinámicas.
- Lo que va seguido de `(` se pinta como llamada aunque no esté en ninguna
  lista, así los paquetes del propio esquema también se distinguen.
- Tolera lo que el **streaming** corta a la mitad: un literal o un comentario de
  bloque sin cerrar no se comen el resto del fragmento.

La barra del bloque muestra el lenguaje y, al pasar el puntero, **ajustar
líneas**, **copiar** e **insertar en el cursor**.

## Diagnóstico

```powershell
dart run tool/copilot_login_probe.dart
```

Informa de CLI detectada, vía de lanzamiento, presupuesto de prompt, cuenta y
variables corporativas, sin gastar créditos.

En debug, `CodeEditorPanel.registerDebugEvalExtension()` registra
`ext.sirweb.evalJs` en el VM service para evaluar JavaScript dentro del WebView2
de Monaco, que es la única forma práctica de depurar el puente Flutter↔Monaco
sin recompilar. **Solo en debug**: en release sería un agujero para ejecutar
código arbitrario en el editor.

## Modos, modelos y ajustes

### Modos

| Modo | Flags de la CLI | Instrucción añadida al prompt |
| --- | --- | --- |
| **Pregunta** (por defecto) | `--disable-builtin-mcps` + `--disable-mcp-server` por cada servidor del usuario | ninguna |
| **Plan** | lo anterior + `--plan` | pide un plan numerado antes de tocar nada |
| **Agente** | deja vivos los MCP (por ejemplo el de Sirweb) | autoriza investigar con herramientas antes de responder |

En los tres modos siguen denegados `shell`, `write` y `url`: el agente puede
conversar y consultar, nunca escribir en disco ni salir a internet.

Apagar los MCP en *Pregunta* y *Plan* no es cosmético: arrancarlos cuesta unos
segundos en cada invocación y no aportan nada a una respuesta conversacional.

### Modelos

La lista **no está codificada en la app**. `CopilotCliService.listModels()`
ejecuta `copilot help config` —una ayuda local, no gasta peticiones— y parsea
los identificadores enumerados bajo la clave `model`, que es la misma fuente
que alimenta el comando `/model` de la CLI. El resultado se cachea en memoria
y se puede refrescar con *Actualizar lista* en el menú del selector.

Si la CLI no está instalada o cambia el formato de la ayuda se recurre a
`CopilotCliService.fallbackModels`. Un modelo guardado en preferencias que ya
no exista se degrada a `auto`, para evitar el error
*«Model … is not available»* en el primer envío. *Otro modelo…* sigue
permitiendo escribir a mano cualquier identificador que la cuenta tenga
habilitado.

### Razonamiento y ventana de contexto

El control compacto de la barra (`Auto · estándar`) agrupa:

- **Razonamiento** → `--effort` (`none`…`max`); `automático` no pasa la opción
  y deja decidir a la CLI.
- **Ventana de contexto** → `--context` (`default` / `long_context`), para los
  modelos con precio por tramos.

El icono de reguladores contiguo recuerda que **el documento abierto va
siempre** y deja un único interruptor: **enviar los errores actuales**.

Todo se persiste en `SharedPreferences`: `copilot_chat_mode`,
`copilot_chat_model`, `copilot_chat_effort`, `copilot_chat_context_tier`,
`copilot_chat_include_errors`, `copilot_chat_panel_width`,
`copilot_chat_tip_seen`.

