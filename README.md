# mex-orbit-client

El cliente del juego, en **Godot**: la cara de MexOrbit ante el jugador.

> **MexOrbit** es nombre temporal del proyecto. Documentación en español; **código en inglés (GDScript incluido), comentarios en español**.

## Qué es

- El cliente definitivo, construido sobre **el aprendizaje del prototipo** (`MexOrbit.GodotClient`): su arquitectura de escenas, su capa de red aislada y sus 15+ ventanas funcionales demostraron el camino — el código se trae **selectivamente y traducido a las nuevas bases**, jamás arrastrando lo jubilado.
- **UI propia**: design system nuevo (pilar 04/05) — no la réplica del cliente Flash.
- **Arte vectorial** (pipeline desde `mex-orbit-art`) — cero assets de BigPoint.
- Red contra el **protocolo nuevo** (contrato compartido con `mex-orbit-game-server`) y consumo de `mex-orbit-api` para todo lo fuera de sesión (login, Mercado, perfil).

## Qué se jubila del prototipo

- La UI calcada del Flash y los sprites `do_img` extraídos.
- El protocolo legado (pipe-strings y command-IDs del emulador) y su capa `net/`.
- Cualquier compatibilidad con el flujo del cliente Flash.

## Stack

- Godot 4.x, GDScript.

## Relación con otros repos

| Repo | Relación |
|---|---|
| `mex-orbit-game-server` | El mundo en tiempo real, vía protocolo nuevo |
| `mex-orbit-api` | Cuentas, Mercado, perfil, misiones |
| `mex-orbit-art` | Fuente de todos los assets (pipeline de exportación) |
| `mex-orbit-docs` | Guidelines (economía/sistemas) y pilar de UI |

## Estado

**E2/I7 cerrada**: login con la secuencia real, vuelo por el 1-1 con predicción + reconciliación, combate y loot, base y economía, chat y reconexión con ventana de gracia. El autotest recorre el loop entero de punta a punta (Vex → caja → base → refinado → venta → chat → caída de red → regreso). Correr: `godot --path .` (requiere api en 5100 y game server en 5200; `dev_login.cfg` local precarga credenciales). Autotest: `godot --path . -- --screenshot=ruta.png`.

## Correr el cliente

```powershell
.\tools\dev-run.ps1                 # levanta lo que falte y abre el cliente
.\tools\dev-run.ps1 -SoloServicios  # deja MySQL/api/game server listos, sin cliente
.\tools\dev-run.ps1 -Autotest       # pasada e2e completa del loop (~3 min): la que cierra el gate
.\tools\dev-run.ps1 -Bestiario      # solo los retratos de los NPC (~20 s): la de trabajo de arte
.\tools\dev-run.ps1 -Bestiario -Calidad baja   # los mismos, forzando un nivel de calidad
.\tools\dev-run.ps1 -Detener        # apaga cliente, api y game server
```

Es idempotente: comprueba cada puerto (**3307** MySQL de dev, **5100** api, **5200** game server) y solo
arranca lo caído. En una sesión de Claude Code está también como `/godot [autotest|servicios|detener]`.

Credenciales de dev en `dev_login.cfg` (fuera del repo). **Una sesión por cuenta**: la ventana entra con
`odrack` y las pruebas usan `testbot` — no las corras mientras juegas con esa cuenta.

### Dos pruebas, no una

`-Autotest` recorre el loop entero y es la que responde *"¿sigue funcionando el juego?"*. Tarda unos
tres minutos, y para calibrar un shader eso es un peaje: se paga una y otra vez por mirar un bicho.

`-Bestiario` solo pone la cámara sobre cada especie y sale — **veinte segundos**. Comparten el mismo
código de retrato (`_autotest_bestiario`), así que no hay dos versiones que mantener.

**La caza tiene límite de 20 s.** La nave vuela a 320 y un Vex vagabundea a 270: si el bicho elige un
destino que se aleja, la persecución cierra a **50 unidades por segundo** y puede durar eternamente.
De ahí salió un timeout intermitente del gate — el peor tipo de fallo, porque parece un bug del
juego. Pasados 20 s el bot abandona esa presa y busca otra.

**Una prueba no puede heredar estado de la corrida anterior.** La del cambio de calidad en caliente
aplicaba `baja` y no lo deshacía, y como la calidad **se persiste por cuenta**, todas las corridas
siguientes arrancaban degradadas sin decirlo. Costó descubrirlo porque no fallaba: el portal montaba
su camino fijo, la afirmación del atlas se saltaba sola y el gate daba **OK sin haber probado nada**.
Dos cambios lo cierran, y los dos hacen falta: sin `-Calidad` el autotest fuerza **alta** en vez de
leer lo guardado, y la prueba en caliente **devuelve** la calidad a donde estaba. De propina, ahora
falla en voz alta si en una corrida por defecto el portal no monta el atlas — un camino que se salta
solo es peor que un camino roto.

Y el modo de arte toma **dos fotogramas** de cada bicho (`-<especie>.png` y `-<especie>-b.png`,
separados ~0,9 s). Una foto fija no demuestra que un shader se **mueva**; con dos se compara. Pegarlas
lado a lado es la forma fiable de verificar una animación — medir píxeles que cambian **no sirve**,
porque el fondo en paralaje se mueve más que el bicho y ahoga la señal.

## Definiciones en JSON (`data/`)

**Ninguna particularidad de un asset vive en el código.** Cada nave, alien y mapa tiene su JSON, herederos
directos del `maps-config.xml` y la tabla de anclajes de llamas del cliente original:

| Archivo | Define |
|---|---|
| `data/ships/<code>.json` | textura, tamaño en pantalla, radio de click, **anclajes de toberas** y estilo de la estela (color, largo, ancho, vida) |
| `data/npcs/<code>.json` | textura **o** atlas animado, capa emisiva y su pulso, radio de click, giro y efectos de shader |
| `data/maps/<code>.json` | el stack de capas: fondo principal, mosaicos con su `p_factor`/escala/alfa, planetas con posición y profundidad, sol con su giro, tinte del polvo estelar |
| `data/props/<code>.json` | props del mundo (**estación**, **portal**, **caja de carga**): textura, emisiva, tamaño en unidades de mundo, pulso, radio de click y color en el minimapa |
| `data/ammo/<code>.json` | **el aspecto de cada arma**: color, largo, grosor y duración del haz, con su variante `beam_skilled` (el disparo potenciado del perfil de piloto: más grueso y brillante) |

Agregar una nave nueva = soltar su PNG + escribir su JSON. Cero código.
Un JSON que apunta a una textura que todavía no existe **no tira el cliente**: cae al respaldo
y avisa por consola — el arte y el dato pueden ir a distinto ritmo.
Los anclajes se miden con `mex-orbit-art/tools/find-anchors.py <export.png> [emisivo|geom]` en vez de
estimarlos a ojo. El modo **emisivo** busca las toberas por su brillo; el modo **geom** las busca por la
silueta y encuentra tambien los cañones laterales — hace falta cuando las toberas son metal apagado,
como en la cápsula Phoenix, que no tiene un solo píxel encendido.

## Diales

Constantes calibrables de sensación y comportamiento — moverlas es cambiar un número. **Regla del repo: todo dial nuevo se documenta aquí en el mismo commit que lo crea.**

| Dial | Dónde | Valor | Qué hace |
|---|---|---|---|
| `TURN_STEPS` | `game/entity_node.gd` | 32 | Posiciones de giro (32 = el look de 11.25° del original). 64 = giro más fino; giro continuo = quitar el redondeo en `_set_visual_angle` |
| `TURN_TIME` | `game/entity_node.gd` | 0.1 s | Duración del tween de giro por el camino corto |
| `DEAD_ZONE` | `game/entity_node.gd` | 2 px | Destino encima de la nave en vuelo no re-orienta (anti-trompos) |
| `HOLD_RESEND_SEC` | `game/world.gd` | 0.25 s | Cadencia del reenvío con click sostenido (tope real: rate limit 10/s del contrato) |
| `HOLD_MIN_DELTA` | `game/world.gd` | 60 px | El destino debe moverse al menos esto para reenviar |
| `CLICK_RADIUS` | `game/world.gd` | 34 px | Radio de click sobre entidades, escalado por el zoom |
| Umbral de snap | `entity_node.gd::reconcile` | 220 px | Deriva mayor a esto = teletransporte al eco del server; menor = lerp 0.35 |
| Zoom de cámara | `game/world.gd` | ×1.1, clamp 0.1–3 | Rueda del mouse, calcado del prototipo |
| Acelerador de estelas | `entity_node.gd::_process` | subida 3.0/s, caída 4.0/s | Qué tan rápido encienden y apagan las estelas al volar/frenar (su forma y color vienen del JSON de la nave) |
| Ventana | `project.godot` | maximizada, `canvas_items`/`expand` | Arranca a pantalla completa; el lienzo lógico sigue siendo 1280×720 |
| `COLLECT_ARRIVE` | `game/world.gd` | 200 px | Llegar a esto de la caja dispara el CollectBox (el server valida 250) |
| Disparos | `data/ammo/*.json` + `projectile_2d.gd` | duración 0.15 s | Proyectil que **viaja** con duración fija (no velocidad), como el prototipo; sale alternando por las bocas de `cannons` de la nave |
| Daño flotante | `world.gd::_numero_flotante` | sube 42 px en 1 s | Colores del original: `FF0000` el daño que haces, `DB63E2` el que recibes; golpes seguidos se **acumulan** en el número vivo |
| Topes de impacto | `entity_node.gd` | 5 casco, 9 escudo | Máximo de animaciones simultáneas por nave (los del prototipo) |
| Explosión | `world.gd` | 16 fps, escala 1.4 | Los 8 frames del pipeline al morir una entidad |
| Pasos de zoom del minimapa | `ui/minimap_window.gd` | 180, 238, 300, 380, 460 | Anchos del canvas (los del prototipo); el alto sale del ratio del mapa |
| `AUTOPILOT_ARRIVE` | `game/world.gd` | 120 px | A esta distancia el autopiloto declara destino alcanzado |
| Escala de la estación | `world.gd::_construir_estacion` | 0.6 | El render de 1024 rinde a ~614 px en el mundo |
| Anillo de zona segura | `world.gd::_construir_estacion` | cian 22%, grosor 3 | El radio que manda el server en `EnterMap` |
| `MAX_REINTENTOS` | `game/world.gd` | 8 | Intentos de reconexión antes de rendirse (espera creciente 1→5 s, dentro de la gracia de 60 s del server) |
| `MAX_LINEAS` | `ui/chat_window.gd` | 120 | Párrafos que guarda el historial de COMMS antes de recortar por arriba |
| `BARRA_ANCHO` / `BARRA_ALTO` / `BARRA_SEPARACION` | `game/entity_node.gd` | 60 / 3 / 5 px | Geometría de las barras de estado sobre la nave |
| `turn.deg_per_sec` / `turn.steps` | `data/npcs/*.json` | 32–240 °/s · steps 0 | Giro **en reposo** de cada bicho: velocidad angular propia y sin cuantizar (ver abajo) |
| `undulate.*` | `data/npcs/*.json` | Vorax 0.055 · Vexor 0.045 · Vex 0.040 · Ferox 0.030 | Ondulación del cuerpo por shader: amplitud, frecuencia, desde dónde dobla y cuánto se menea parado |
| `peristalsis.*` | `data/npcs/*.json` | Vorax: amount 1.8 | Onda de luz recorriendo el interior: cuánto brilla el bulto, cuántos hay, a qué ritmo bajan y qué tan marcados van |
| `peristalsis.radial` | `data/npcs/*.json` | true en las rocas | La onda sale del **centro** en vez de recorrer el cuerpo |
| `flicker.*` | `data/npcs/*.json` | Skarn 0.35 · Vex 0.45 · Ferox 0.40 | Ruido que hace temblar el brillo: cuánto, con qué grano y a qué ritmo |
| `rings.*` | `data/npcs/*.json` | Solo el Gravit: 0.9 | Anillos concéntricos girando: velocidad, bandas, radios inicial y final, y cuánto se frena cada banda |
| `TURN_FLIGHT_DEG_PER_SEC` | `game/entity_node.gd` | 420 °/s | Giro **al emprender vuelo**: brioso en todos, para que la proa vaya delante |

## Mobiliario del mapa: portal y caja de carga

**Nada de esto tiene la posición en el cliente.** El portal es dato de BD
(`map_portal`) y llega **completo en `EnterMap`** — la spec del protocolo manda
que portales, estaciones y POIs se envíen enteros al entrar, no por relevancia.
La caja de carga la coloca el server al morir un alien (`BoxSpawn`). El cliente
solo pone el arte, y ese arte sale de `data/props/`.

- **`PortalNode`** (`game/portal_node.gd`): en calidad **alta** el portal **reposa
  dormido** en el primer fotograma de su atlas y, al activarlo, reproduce **2,1 s
  de encendido una sola vez**. Clic estando encima = activar; clic desde lejos =
  rumbo a él. En **media y baja** cae al camino de siempre: el aro quieto con la
  capa emisiva —el vórtice— girando y latiendo (rotar el sprite entero delataría
  los pernos). Debajo va la etiqueta del sector destino, en `--violet`. Un portal
  con `is_working = 0` se pinta apagado y no se puede activar.
- **Caja de carga**: su pulso es de **alfa**, no de intensidad — es una luz de
  baliza que llama al jugador, no un reactor como el núcleo de un alien.
- **Minimapa**: estación y portales se dibujan como **rombos** (cian y violeta),
  forma distinta de los círculos de naves y cajas, para que el mobiliario fijo no
  se confunda con lo que se mueve.

## Chrome de ventana y sysbar (sistema N)

Dos piezas nuevas, y las dos son **reutilizables a propósito**: el chat, el minimapa y la ventana
Nave traen hoy tres cabeceras distintas hechas a mano, y esa es justo la forma de que un sistema de
diseño se disperse — cada ventana copia a la anterior y el spec se queda solo en el documento.

**`NWindow`** (`ui/n_window.gd`) es el `.fp` del prototipo llevado a Godot medida por medida:
esquinas en L de 13 px, cabecera de 26 px con franja cian de 3 px y degradado cian→violeta→nada,
chip de icono, botones `–` y `×` de 17 px, arrastre por la cabecera con clamp al viewport y grip
diagonal. Una ventana se construye diciendo qué icono y qué título lleva; el spec está en un sitio.

**`Taskbar`** (`ui/taskbar.gd`) es el `#taskbar` del §5: cap vertical "MENÚ", botones de 44×44 con
icono de 21 y separadores por grupos. Es **la otra mitad del §1** — "todo es ventana" solo es cierto
si hay de dónde reabrirlas, y hasta ahora cerrar una ventana la perdía para siempre. Por eso el
autotest prueba el ciclo entero (cerrar → icono a neutro → reabrir) y no solo que el botón exista:
una ventana que se cierra y no vuelve es peor que una que no se cierra.

**`SysBar`** (`ui/sysbar.gd`) es el `#sysbar` del §1.9: arriba a la derecha y **fuera** del menú de
ventanas, botones de 36×36 con hueco de 5 y margen de 8. Hoy lleva **un solo botón** porque es el
único que tiene algo detrás; ayuda, pantalla completa y salir se cuelgan con `agregar()` el día que
existan. Un botón que no hace nada es peor que un botón que falta: el que falta se nota, el muerto se
aprende y se deja de mirar.

**El código de color del §1.3 es contrato, no decoración**, así que el autotest lo afirma: abre los
Ajustes *por el engranaje* —no llamando a `alternar()`, que se saltaría justo el cableado que puede
romperse—, comprueba que la ventana aparece **y** que el icono se puso ámbar, y luego que el segundo
clic cierra.

**La ventana Nave estrena las barras segmentadas del §7.** Era un panel suelto con cinco etiquetas de
texto (`HP 4.000 / 4.000`); ahora las stats van en barras de 96×11 a rayas verticales de 4 px. Un
número dice cuánto queda; una barra dice cuánto queda **de lo que había**, y eso se lee sin leer. Van
**dos y solo dos** para la integridad —casco y escudo, v1 no tiene nano-casco—; la tercera es la
bodega, que no es integridad sino espacio, y por eso va en ámbar y no en un color de stat.

**El chat gana algo al migrar**: sus pestañas de canal estaban en la cabecera, junto al título, y en
el prototipo van en el **cuerpo** (`.fb`). La cabecera es del chrome; el canal es contenido. El
minimapa al revés: sus pasos de zoom suben a la cabecera como `.zbtn`, que es donde el §8 los quiere
— no son contenido, son control de la ventana.

Cuatro cosas que costaron un intento cada una y no son obvias:

- **El `letter-spacing` del §3 existe en Godot, pero no en `Label`.** El primer intento lo falseó
  metiendo espacios entre las letras del título. Eso aguanta un título corto y fijo y se cae con el
  del minimapa, que es vivo: `S e c t o r   1 - 1   ·   ( 2 3 3 0 ,   2 0 6 0 )`. Lo correcto es
  `FontVariation.spacing_glyph`, que es tracking de verdad. Imitar el spec y cumplirlo no son lo
  mismo.


- **`set_anchors_preset` recalcula los offsets que no toques** para conservar el rect anterior. La
  sysbar arrancaba midiendo 0×0 en el origen, así que el preset le dejó `offset_left` en menos el
  ancho de la pantalla: la barra ocupaba todo el ancho con el botón pegado a la **izquierda**. Se
  ponen los cuatro anclajes y los cuatro offsets a mano, y el crecimiento (`grow_horizontal =
  BEGIN`) hace que la barra se reajuste sola al agregar un botón.
- **`PRESET_MODE_MINSIZE` no sirve en el mismo fotograma** en que se agrega un hijo: un contenedor
  todavía no ha calculado su mínimo ahí, y salen offsets de ancho cero. Anclar en vez de medir evita
  la carrera entera.
- **Anclas y offsets se ponen juntos, siempre.** El punto ámbar de "abierta" llevaba anclas
  centradas y una `position` a mano; se salió del botón y acabó pintado **encima de la ventana
  Nave**, que estaba en otra capa. Es el mismo fallo que dejó la sysbar invisible, en pequeño.
- **El degradado va con `draw_polygon` y un color por vértice**, que interpola solo. La primera
  versión usó un `GradientTexture2D` y salió una **banda blanca opaca** que tapaba el título y los
  botones — el degradado no llegaba a la textura y quedaba el negro→blanco por defecto. Dos
  triángulos con color por vértice no tienen ese intermediario que puede fallar en silencio.

**El cristal no lleva desenfoque.** El `--glass` del §2 va con `backdrop-filter: blur(12px)` en el
prototipo, y Godot no lo da gratis: haría falta un `BackBufferCopy` con shader por ventana. Sin él,
el color es el correcto pero el fondo se transparenta **nítido**, así que sobre una nave o un planeta
la ventana se lee más ruidosa que en el prototipo. Es la única desviación conocida del §4.

**Iconos**: SVG del §10 en `assets/ui/icons/`, con el trazo en **blanco puro** — el color lo pone
`modulate`, y un icono ya coloreado no se podría teñir de ámbar al abrir su ventana.

## Dos barras de estado, no tres

**v1 no tiene nano-casco.** El original apilaba tres barras sobre la nave (vida,
escudo y la amarilla del nano-casco); aquí son **dos y solo dos**: `NTheme.SHIELD`
arriba y el casco abajo (`NTheme.HP` en los tuyos, `NTheme.HOSTILE` en los NPCs),
con el nombre debajo. El token `--nano` quedó retirado del sistema de diseño.

Cada stat se lee **contra su propio máximo** (`set_estado_abs`): sumar casco y
escudo en una sola barra —como se hacía antes— esconde cuál de los dos se está
gastando. Los máximos llegan de `HeroStats` para tu nave y de `TargetInfo` para el
objetivo; sin máximo conocido la barra conserva el porcentaje que trajo su
`EntitySpawn`, porque convertir absolutos sin denominador la haría mentir.

## Chat y reconexión (I7)

**COMMS** (`ui/chat_window.gd`) es una ventana del sistema N — cristal, esquinas en L,
pestañas `GLOBAL`/`FACCIÓN`, arrastrable por su barra de título. **Enter** enfoca la
entrada cuando no la tiene; mientras la tiene, el teclado es suyo y `_unhandled_input`
del mundo no ve nada (nada de disparar mientras escribes). El chat no tiene socket
propio: viaja tipado por el mismo enlace del juego.

**Reconexión automática.** El `Welcome` trae un `reconnect_token`; `GameConnection` lo
guarda y su handshake manda `Resume` en vez de `Hello` cuando `reconnect()` reabre el
socket. Al caerse el enlace, `world.gd` reintenta con espera creciente y avisa en COMMS.
`ResumeOk` limpia el mundo local (entidades, cajas, selección) porque detrás viene la
re-sincronización completa del server; por eso `_construir_fondo`, `_construir_estacion`,
`_construir_minimapa`, `_construir_base` y `_construir_chat` **son idempotentes**: un
`EnterMap` repetido no duplica capas.

**La línea de estado vive abajo al centro**, no en la esquina: las esquinas inferiores
son del chat (izquierda) y del minimapa (derecha).

> `godot` solo registra un `class_name` nuevo tras escanear el proyecto. `dev-run.ps1`
> corre `godot --headless --path . --import` antes de lanzar el cliente; sin ese paso un
> script recién creado revienta con *"Could not find type"*.

Diferencia deliberada contra el prototipo: **v1 clampea el destino a los límites del mapa** (igual que el server); el prototipo navegaba "mapa infinito" con la radiación como freno.

## Calidad gráfica: niveles por subsistema

`Quality` (autoload, `game/quality.gd`) es un puerto del prototipo, que a su vez replicaba el
`QualitySettings` del cliente original. La idea que importa **no es el interruptor alta/media/baja**,
sino que cada sistema pregunte por lo suyo al dibujar: `Quality.nivel("engine") > 0`. Los tres
preajustes solo mueven ese diccionario, así que añadir un modo "personalizado" es abrir la ventana,
no rehacer nada.

| clave | 0 (Baja) | 1 (Media) | 2 (Alta) |
|---|---|---|---|
| `npc` | PNG fijo | PNG fijo | **atlas animado** |
| `shader` | — | ondulación · peristalsis · anillos | ídem |
| `emissive` | — | capa emisiva pulsando | ídem |
| `engine` | sin llamas | llamas | llamas + chispas |
| `collectable` | caja congelada en su fotograma 0 | ídem | caja animada |
| `background` | solo polvo estelar | fondo y planetas | + mosaicos de paralaje |
| `explosion` | no se dibuja | se dibuja | ídem |

**El corte caro está entre Media y Alta**: ahí los atlas dejan de cargarse y se liberan **106 MB**
de VRAM (ocho bichos, la caja y el portal). Media conserva los shaders a propósito — cuestan casi nada (una operación de fragment sobre un
sprite que ya se dibuja) y son lo único que da vida a los bichos que nunca tendrán vídeo.

**El repliegue no costó ni un asset nuevo.** Al convertir un bicho a atlas nunca se borró su render
fijo ni su capa emisiva; por eso los JSON de los animados declaran **los dos caminos** y el nivel
elige cuál se monta. La excepción es la caja: su diseño cambió con el vídeo, así que su respaldo es
el **fotograma 0 del propio atlas** (`cargo-box-still.png`) y no el PNG viejo, que mostraría una caja
distinta al bajar la calidad.

**Se persiste por cuenta, en `user://quality.cfg`.** Dos personas que comparten un PC guardan
ajustes distintos, y a la vez el valor **no viaja con la cuenta** a otra máquina — la calidad es una
capacidad del equipo, no una preferencia de la partida.

**El cambio se aplica al instante.** `Quality.cambiada` lleva las claves que se movieron;
`EntityNode.reconstruir()` rehace solo la parte visual (el nombre, las barras, los cañones y el rumbo
no dependen del nivel), las cajas se recrean en su sitio y el fondo se reconstruye. La nave, su rumbo
y el estado del mundo no se tocan.

**Los Ajustes se abren por el engranaje de la sysbar** (arriba a la derecha), y **Escape** los cierra.
Estuvieron en **F1**, y esa tecla no era suya: el §6 del sistema de diseño reserva **F1–F10** para la
barra de acción II, así que el atajo se habría comido un slot en cuanto existan las barras. Escape es
la única tecla que el documento no reparte. El autotest en modo bestiario **baja la calidad con el mundo ya poblado** y retrata el
resultado: si reconstruir rompiera algo, revienta ahí.

## Dos tipos de asset para los bichos

**PNG + shaders** es el caso normal: una textura, su capa emisiva y los efectos declarados en el
JSON (`undulate`, `peristalsis`, `rings`). Barato, y en el 1-1 hay quince Vex.

**Atlas animado** es el segundo tipo, para los de arriba de la escalera. Una rejilla de fotogramas
sacada de un vídeo en bucle con `mex-orbit-art/tools/video-atlas.py`; el JSON declara `frames` en
lugar de `texture` y `EntityNode` monta un `Sprite2D` con `hframes`/`vframes` que avanza solo.

```json
"frames": { "atlas": "res://assets/npcs/gravon-anim.png",
            "hframes": 7, "vframes": 7, "count": 49, "fps": 12 }
```

### Qué cuesta un atlas, contado bien

Durante tres bichos este README dijo que el coste se controlaba con la jerarquía del bestiario
—"hay tres Gravon frente a quince Vex"—, y **esa cuenta estaba mal**. Una textura se sube a la GPU
**una vez** y la comparten todas las instancias: quince Vex no gastan quince PNG. El número de
bichos no multiplica nada.

Lo que de verdad se paga es **por especie**, y en dos monedas:

| | de qué depende | cómo se controla |
|---|---|---|
| VRAM | del tamaño del atlas | eligiendo la celda por el `screen_size` del bicho |
| presupuesto total | de **cuántas especies** llevan atlas | no dándoselo a todas |

De ahí sale la regla de la celda, que es la lección del Gravit: **la celda se elige por lo que el
bicho mide en pantalla, no copiando la del anterior**. El Gravon usa 384 porque ocupa 214 px; el
Gravit ocupa 124, así que con 384 estaríamos pagando triple muestreo que nadie ve. Con 256 cuesta
12,2 MB en vez de 27,6 — la mitad del presupuesto de la ronda, ahorrada por mirar un número que ya
estaba en el JSON.

| bicho | en pantalla | celda | fotogramas | VRAM |
|---|---|---|---|---|
| Gravon | 214 px | 384 | 49 | 27,6 MB |
| Skarnox | 208 px | 384 | 42 | 27,6 MB |
| Ferox | 190 px | 320 | 46 | 19,1 MB |
| Mordax | 186 px | 320 | 48 | 19,1 MB |
| Vex | 141 px | 256 | 48 | 12,2 MB |
| Vexor | 178 px | 320 | 26 | 11,7 MB |
| Gravit | 124 px | 256 | 45 | 12,2 MB |
| Vorax | 232 px | 128×512 | 49 | 12,2 MB |
| caja | 96 px | 192 | 49 | 6,9 MB |
| portal | 380 u | 384 | 25 | 14,1 MB |

El Vorax es el recordatorio de que la celda **no tiene por qué ser cuadrada**: es un gusano de
125×638, y cuadrarlo tiraría el 80% de cada celda.

Tres cosas que conviene no olvidar:

- **La luz va cocida** en los fotogramas, así que estos bichos **no llevan capa emisiva ni shaders**
  — su vida ya está en el asset. El `pulse` no les aplica. Esto estaba escrito aquí desde el Gravon
  pero el código solo lo cumplía a medias: se saltaba la capa emisiva y **no** el shader del cuerpo.
  Nunca se notó porque ningún animado traía efectos de cuerpo… hasta el Gravit, cuyos aros se abren
  en el vídeo **y** los giraba `rings` por encima. Ahora `_montar_ondulacion` sale en cuanto hay
  atlas: **la animación manda sobre el truco**. En media y baja, donde no hay atlas, el shader vuelve
  — y los pernos del Gravit siguen orbitando sobre su PNG.
- Lo que evita que tres Gravon animen al unísono es un **desfase del índice de fotograma** por
  entidad, no la fase del pulso. Es el mismo problema de los gusanos ondulando en fase, resuelto en
  otro sitio.
- Con atlas, el tamaño en pantalla se calcula sobre el alto del **fotograma**, no el de la textura
  entera. Olvidarlo hace al bicho siete veces más pequeño.

Es lo que hacía el cliente original con sus aliens (`loopPlay`), con una diferencia que importa: los
suyos **por eso no rotaban**. Los nuestros sí — en Godot el bucle es contenido y el rumbo lo pone el
nodo, así que el Gravon gira hacia donde vuela mientras sus engranajes se destapan.

**Los props también entienden los dos tipos.** La caja de carga es la primera: su JSON declara
`frames` y `_on_box_spawn` monta el atlas igual que `EntityNode`, con desfase por caja para que un
campo de ellas no parpadee al unísono. Su bucle es el mejor del catálogo — la costura mide **0,9
veces** un paso normal entre fotogramas, es decir que salta menos que avanzar un fotograma. No es
suerte: su luz **da la vuelta completa** al contorno de la tapa, así que el ciclo cierra por
construcción. Es la forma de pedir una animación que loopee sin depender de que el modelo acierte.

**La costura se mide contra el paso normal entre fotogramas, no en absoluto.** Un vídeo con mucho
movimiento salta mucho en cualquier transición; lo que delata un bucle roto es que la última salte
**más** que las demás. Con seis medidas ya se ve el patrón:

| asset | costura | qué pasó |
|---|---|---|
| Ferox | **0,5×** | salta **menos** que avanzar un fotograma: no hay nada que arreglar |
| caja | 0,9× | cierra por construcción: la luz da la vuelta entera |
| Gravit | 1,1× | se pasaba de ciclo (4,12 contra 1,18); recortar 3 fotogramas lo arregló |
| Mordax | 1,4× | entero: el mejor recorte apenas mejoraba y costaba 7 fotogramas |
| Vexor | 1,2× | su ciclo **se repite dos veces**: media película basta |
| Skarnox | 2,0× | 13× de crudo; recortar 6 fotogramas lo salvó |
| Gravon | 3,0× | el vídeo **era** un ciclo entero que no cerraba: recortar solo quita movimiento |
| Vex | 3,9× | no es un ciclo, es una **rampa** — se arregla con vaivén, no recortando |

El Gravit y el Skarnox son el caso que el recorte arregla —sobra material—; el Gravon es el que no
—falta cierre—. Por eso el script solo recorta si la mejora es grande, y si no, avisa y deja el
vídeo entero: la discrepancia se arregla **al generar**, no componiendo en 2D.

### Vaivén: cuando el vídeo no es un ciclo sino una rampa

El vídeo del Vex **no vuelve al principio**: el bicho se enciende progresivamente y despliega las alas
durante los 4 s, y ahí se queda. La costura mide **3,9 veces** el paso normal, la peor del catálogo, y
ningún recorte la mejora — no sobra material, es que no hay ciclo.

Con `"pingpong": true` se reproduce **de ida y vuelta**. El cierre es perfecto **por construcción**
—dos fotogramas seguidos son siempre vecinos, así que no hay costura que medir— y **no cuesta un
fotograma más**: el atlas es el mismo, solo cambia cómo se recorre. El ciclo pasa a durar 8 s y lo que
se ve es un ala que se abre y se cierra. La rampa deja de ser un defecto y pasa a ser el movimiento.

**Se había descartado, y estaba bien descartado.** El comentario de `video-atlas.py` lo dice desde el
Gravon: sus aros tienen rotación **neta**, y al revés se mecerían en vez de girar. Pero un ala que se
abre no tiene ese problema — **cerrarse ES su vuelta**. La técnica no era mala, era el bicho
equivocado; lo que importa es si el movimiento tiene una dirección privilegiada.

Un detalle que se escapa fácil: con vaivén el periodo es casi el **doble**, así que el desfase por
entidad tiene que repartirse sobre `2n−2` y no sobre `count`. Repartiendo sobre `count`, los quince
Vex caen todos en la misma mitad de la onda y abren el ala a la vez — justo lo que el desfase existe
para evitar.

### Mirar si el vídeo se repite antes de exportarlo entero

El Vexor pliega y despliega las alas **dos veces** en sus 4 s. Exportar el tramo `0:25` —2,2 s, 26
fotogramas— cierra a **1,2×**, igual de bien que los 48, con **la mitad de la VRAM**. La comprobación
es barata: medir el salto del fotograma `k` contra el `0` para todo `k`, y buscar el primer valle.

**Pero un valle no basta: tiene que cerrar IGUAL DE BIEN que el vídeo entero.** El Ferox tiene un
valle en `0:29` que ahorraría 7 MB, y no se usa — porque cierra a 1,49× cuando el entero cierra a
0,5×. Un sub-bucle que cierra *peor* no es un ciclo que se repite, es un **parecido**, y recortar ahí
quita movimiento real. Es la lección del Gravon vista desde el otro lado: el Vexor podía recortarse
porque su valle empataba con el total (0,95 contra 0,99); el Ferox no.

Por eso `RANGO` y `SECUENCIA` son dos cosas distintas en la herramienta, aunque nacieran juntas con el
portal: **recortar y no-cerrar son decisiones independientes.** El portal quiere las dos; el Vexor
quiere recortar y sigue siendo un bucle.

### Secuencia, no bucle: el tercer patrón

Un bicho animado repite su ciclo para siempre. El portal **no**: reposa en su primer fotograma y
reproduce el encendido entero **una vez**. Ahí no hay costura que cerrar —nadie vuelve al principio—
así que el atlas se exporta con `RANGO=0:24` y el análisis de bucle se salta completo. Es más: el
recorte al mejor cierre le comería justo el final, que es **el fotograma en el que el portal se
queda**.

**Y los 2,1 s no son un número estético: son el hueco donde cabe la latencia.** La animación corre
mientras el server resuelve el salto de sector, así que el viaje de ida y vuelta se paga en pantalla
en vez de en una espera. `activar()` devuelve si arrancó y `encendido_terminado` avisa al llegar al
final; en E3, el mapa se muestra cuando hayan terminado **los dos** — la animación y la respuesta.
Que `activar()` devuelva `false` (portal apagado, o calidad sin atlas) no es un error: significa que
el salto ocurre sin ceremonia y quien llama debe seguir adelante igual.

Aquí el repliegue **no es el mismo portal**, y conviene saberlo: con atlas se ve dormido hasta que lo
activas; sin atlas se ve encendido desde el principio y el salto pasa sin ceremonia. Es lo correcto
—en calidad baja no se pagan dos segundos de espectáculo— pero no es una degradación transparente
como en los bichos.

**El color del portal está mal a sabiendas.** Lo emisivo del vídeo es 83% azul-cyan, matiz 188, a
**2 grados** del `--cyan` `#00E5FF` que en la dirección N identifica al **jugador**; el violeta
`#A78BFA` es el de los portales, y ahí siguen su etiqueta y su punto del minimapa. Se aceptó así a
propósito para no frenar la integración. Si algún día se corrige, es rotar el matiz ~67° en la capa
emisiva del atlas.

## Dos modelos de giro, y la diferencia importa

**Naves** (`turn_deg_per_sec = 0`): duración **fija** de `TURN_TIME` por el camino corto, cuantizada a 32 pasos.
Es el giro del prototipo, calibrado y validado: dé igual que el ángulo sea de 11° o de 180°, siempre tarda lo
mismo. En una nave que persigue al cursor eso se siente responsivo, y el salto entre pasos es el *look* heredado
del sheet de 32 frames del original.

**Bichos** (`turn.deg_per_sec > 0` en su JSON): velocidad **angular** constante y giro **continuo**.

Aplicarles el modelo de la nave fue un error: un alien se daba media vuelta en 0,1 s y parecía un trompo. En el
original eso no pasaba porque **sus aliens eran animaciones en bucle y no rotaban nunca** (`rotatable=false`) —
la rotación de 32 frames era cosa de las naves de jugador. Los nuestros son renders con proa, así que sí giran,
pero cada uno a su peso: el Ferox encara en un instante (240 °/s, acorde a sus 420 de velocidad) y al Skarnox
media vuelta le lleva casi 6 segundos.

La cuantización también se apaga en ellos (`steps: 0`): girando despacio, 32 pasos se ven a tirones porque cada
paso dura una eternidad.

### La proa va delante

Dar peso al giro trajo un efecto secundario feo: el bicho arrancaba **a toda velocidad mientras
todavía estaba girando**, así que se desplazaba de lado como un cangrejo — un Skarnox llegaba a
deslizarse 1.000 unidades de costado durante sus 5,6 s de giro. Dos correcciones:

- **El giro de vuelo es brioso en todos** (`TURN_FLIGHT_DEG_PER_SEC`). El ritmo pesado de cada
  especie es para el giro perezoso **en reposo**, que es donde cuenta su carácter; para encarar
  un destino, todos son rápidos.
- **La velocidad depende de la alineación**: se avanza por el coseno del error de proa, así que
  mientras la nariz no mire al rumbo apenas se mueve, y acelera según se alinea. Pivota y luego
  arranca, en vez de derrapar.

## Ondulación: que la cola se menee

`game/shaders/undulate.gdshader` deforma el cuerpo con una onda seno que crece hacia la cola.
Solo la llevan los bichos que declaran un bloque `undulate` en su JSON — una roca no se menea,
un gusano sí, y calibrarlo es cambiar un número.

Tres decisiones que conviene no deshacer:

- **Va en el fragment, no en el vertex.** Un `Sprite2D` es un quad de cuatro vértices: deformar
  vértices daría un alabeo bilineal, no una onda. Desplazando la muestra de textura
  (`UV.x += sin(UV.y …)`) sale la onda completa **sin geometría extra**.
- **El sprite y su capa emisiva llevan el MISMO shader**, uno en mezcla normal y otro en aditivo.
  Si solo ondulara el cuerpo, las vísceras del Vorax se quedarían rectas sobre una carne que
  serpentea.
- **El modulate se reaplica a mano.** Al re-muestrear la textura por nuestra cuenta se pierde el
  color de vértice — que es por donde viaja el pulso de la capa emisiva. Se captura en
  `vertex()` en un varying. `MODULATE` **no existe** en `canvas_item`.

La onda sube al desplazarse y baja al pararse, pero nunca a cero: un bicho vivo respira aunque no
avance. Y cada entidad lleva su fase, o un banco de gusanos ondulando al unísono canta a bucle.

**`from` se mide, no se estima.** En el Vexor solo debe doblarse el abdomen: la quitina del tórax
es armadura. El corte está en `0.68` porque el perfil de anchura del render cae ahí de 241 a 134 px,
que es justo donde acaban las placas. Sacar ese perfil es una vuelta por las filas del PNG contando
píxeles opacos — mejor que ajustar el número a ojo hasta que parezca bien. En el Vex el corte cae en
`0.74`, y no es el mismo número por casualidad: su silueta ensancha hasta `0.72` y el aguijón asoma
por debajo, así que se desploma de 352 a 49 px.

**El tamaño también es temperamento.** Vex y Vexor son la misma especie, pero el pequeño agita el
aguijón más rápido (4,8 frente a 4,2) y más inquieto en reposo (0,55 frente a 0,50), mientras que
en pantalla se desplaza menos. El chico tiembla, el grande pesa — el mismo criterio que ya rige sus
velocidades de giro y sus latidos.

### Peristalsis: que se le vea digerir

El mismo truco aplicado a la capa emisiva. `peristalsis` multiplica el brillo por una onda que
**recorre** el cuerpo en vez de latir a la vez, así que se ve un bulto de luz bajando por el tracto
del Vorax.

El detalle que lo vende es el **signo menos delante de `TIME`**: con más, la onda subiría de la cola
a la boca, que es exactamente al revés de como se traga. Y nunca baja del brillo base — es un bulto
que pasa, no un parpadeo del cuerpo entero (de eso ya se encarga el `pulse`, que multiplica global).

**Los dos efectos se piden por separado.** Un bicho puede tener peristalsis sin ondular: un Skarnox
con magma corriendo por sus grietas y la roca quieta, por ejemplo. Por eso, sin bloque `undulate`,
la amplitud se fuerza a **cero** en vez de dejar el defecto del shader — pedir luz no puede poner a
bailar al bicho de propina.

### Fuego: que el magma no lata como un reactor

Dos efectos para las rocas, y los dos van **solo sobre la capa emisiva**. La regla se sostiene: una
piedra no se menea, así que el Skarn no lleva `undulate` — su vida entera está en el magma.

- **`peristalsis` en modo `radial`**: la misma onda del Vorax, pero medida sobre el **radio** en vez
  de a lo largo del cuerpo. El calor sale del núcleo hacia fuera por las grietas, que es como irradia
  algo fundido. Un carácter en el shader —`length(uv - 0.5)` en lugar de `uv.y`— separa a un gusano
  de una brasa.
- **`flicker`**: ruido de valor que hace temblar el brillo. Sin él, el `pulse` late demasiado limpio y
  la roca parece tener un reactor dentro en vez de lava. El ruido es un hash barato con interpolación
  suave; no hace falta Perlin para que una grieta tiemble.

**El grano (`scale`) va al revés de lo que parece**, y costó un intento averiguarlo: depende de cuánta
superficie ocupe la emisiva, no del tamaño del bicho.

| Emisiva | `scale` | Por qué |
|---|---|---|
| Grande (grietas del Skarn) | 6–7 | Celdas pequeñas dan variación **local**: unas grietas arden y otras no |
| Delgada (vetas del Vex, costuras del Ferox) | 3–3,5 | Celdas grandes hacen que la veta **entera** suba y baje |

Sobre una línea de un píxel, un grano fino produce ruido **por píxel** — se lee como suciedad, no como
fuego. El Vex y el Ferox arrancaron con `scale` 9 y 12 y apenas se notaba; a 3,5 y 3 el núcleo y las
costuras laten enteros.

**El Skarnox los lleva para su camino FIJO**, no para el animado: en calidad alta manda su atlas, que
ya trae su propio fuego. Pero en media y baja cae al PNG, y sin esto el hermano mayor se vería **más
muerto que el pequeño**. Cada vez que un bicho gana atlas, conviene preguntarse cómo queda su
repliegue.

### Anillos: metal que gira sobre sí mismo

`rings` rota la UV **alrededor del centro** por bandas de radio, alternando el sentido. Sobre una
pieza concéntrica cada banda mapea anillo sobre anillo y parece girar — por eso solo sirve para los
bichos de metal; sobre una silueta con forma sería un remolino.

**Dónde girar no se elige a ojo: se mide** con `mex-orbit-art/tools/ring-bands.py`, que da el perfil
de asimetría angular por radio. La razón es contundente: **rotar un anillo perfectamente liso mapea
píxeles idénticos sobre sí mismos y no se ve nada**. El Gravon lo enseñó a la mala — su banda estaba
cortada en `r 0.24`, justo antes de donde empieza su detalle asimétrico (0.24–0.33), y el efecto era
invisible aunque el shader funcionara perfectamente.

Pero la asimetría es **necesaria y no suficiente**, y esa es la lección cara: el detalle tiene que
**pertenecer a un anillo**, no cruzar entre varios.

- El **Gravit** lleva anillos y gira entero hasta el borde. Sus cuatro pernos están **sueltos en el
  aro exterior**, así que orbitan limpiamente — y al ser simétrico de revolución **no tiene proa que
  romper**. Sus anillos interiores, demasiado lisos, no darían lectura por sí solos.
- El **Gravon NO lleva anillos**. Su detalle asimétrico son piezas de maquinaria **soldadas de un aro
  a otro**: rotar una banda no las hace girar, las **cizalla**. El perfil de asimetría decía que ahí
  se vería algo, y se veía — pero se veía mal. Su vida la da el pulso de sus tres núcleos.

Regla para el siguiente: mirar si lo asimétrico es una pieza **sobre** un anillo o una estructura
**entre** anillos. `ring-bands.py` encuentra dónde hay detalle; que ese detalle pueda girar lo dice
el ojo.

## Muerte y reaparición

`RespawnPanel` (`ui/respawn_panel.gd`) es el killscreen: velo rojo, causa de la muerte y las
opciones que **manda el server**. El cliente no inventa ninguna — llegan en `RespawnOptions` con
su `label_key`, su coste y si están disponibles. El texto sale de una tabla local por clave: el
server manda claves, no frases, para que no decida el idioma (la lección de los menús con texto
del legado).

Mientras estás muerto el mundo no acepta órdenes: ni clic de vuelo, ni láser. El spawn de la
nave reparada es lo que devuelve el control.

## El bestiario del 1-1

Cinco especies, y cada una se distingue **antes** de leer su nombre:

| Alien | Familia | Cómo se reconoce |
|---|---|---|
| Vex | quitina | La plaga: pequeño, angular, un núcleo rojo |
| Vexor | quitina | El mismo bicho **crecido**: dos núcleos y venas ramificadas |
| Gravit | metal | El más pequeño y aun así el más denso: anillos de hierro pulido y un núcleo hundido |
| Skarn | mineral | Peñasco de basalto con magma en las grietas |
| Skarnox | mineral | El Skarn crecido: corona de cristal y una **fractura abierta** con el núcleo fundido |
| Mordax | fauces | **Es una boca**: mandíbula radial de dientes pálidos en medio de un caparazón rojo-pardo |
| Ferox | óseo | El único **claro**: hueso marfil, hojas y cola de látigo |
| Gravon | metal | El Gravit crecido: tres núcleos y el anillo exterior **partido por su propio peso** |
| Vorax | carne | Una garganta con cuerpo: gusano segmentado y semitraslúcido con **las vísceras encendidas** |

Seis lecturas de material —quitina, metal, roca, hueso, caparazón dentado y carne— y ninguna se
confunde con otra a tamaño de juego. Las dos criaturas de boca se separan por silueta: el
**Mordax** es un disco que muerde, el **Vorax** una garganta alargada que traga.

El Ferox es una decisión deliberada: las otras dos familias son oscuras, así que se separa por **valor**, no
solo por silueta — a 150 px se distingue de un vistazo. Es también el más rápido del mapa (420, por encima de
la Phoenix), porque su identidad es alcanzarte, no aguantar.

Los sufijos son la regla de la taxonomía, no adorno: **-or/-ox = forma mayor**, **-it/-in = forma
menor**. Con dos parejas (Vex→Vexor, Skarn→Skarnox) el jugador aprende la primera mitad sin que
nadie se la explique; el **Gravit** le enseña la otra, y de paso le promete que existe un
**Gravon** más grande antes de haberlo visto nunca.

Tres de los nueve son agresivos, con roles distintos: el **Ferox** caza de lejos (radio 700), el
**Mordax** solo muerde lo que entra en su radio corto (350) y el **Vorax** persigue pero **huye
por debajo del 30% de casco** — es el primero cuyo nombre describe una conducta y no una forma.
Los otros seis son pasivos, que no es lo mismo que inofensivos: devuelven el fuego en cuanto los
golpeas.

Las tres parejas base→mayor (Vex→Vexor, Skarn→Skarnox, Gravit→**Gravon**) dejan la regla de
sufijos completa: **-it/-in** menor, **-on/-or/-ox** mayor.
