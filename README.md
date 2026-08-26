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
.\tools\dev-run.ps1 -Autotest       # autotest del loop completo (+ chat y reconexión), con captura
.\tools\dev-run.ps1 -Detener        # apaga cliente, api y game server
```

Es idempotente: comprueba cada puerto (**3307** MySQL de dev, **5100** api, **5200** game server) y solo
arranca lo caído. En una sesión de Claude Code está también como `/godot [autotest|servicios|detener]`.

Credenciales de dev en `dev_login.cfg` (fuera del repo). **Una sesión por cuenta**: la ventana entra con
`odrack` y el autotest usa `testbot` — no corras el autotest mientras juegas con esa cuenta.

## Definiciones en JSON (`data/`)

**Ninguna particularidad de un asset vive en el código.** Cada nave, alien y mapa tiene su JSON, herederos
directos del `maps-config.xml` y la tabla de anclajes de llamas del cliente original:

| Archivo | Define |
|---|---|
| `data/ships/<code>.json` | textura, tamaño en pantalla, radio de click, **anclajes de toberas** y estilo de la estela (color, largo, ancho, vida) |
| `data/npcs/<code>.json` | textura, capa emisiva y su pulso (rango de alfa y velocidad), radio de click |
| `data/maps/<code>.json` | el stack de capas: fondo principal, mosaicos con su `p_factor`/escala/alfa, planetas con posición y profundidad, sol con su giro, tinte del polvo estelar |
| `data/props/<code>.json` | props del mundo (**estación**, **portal**, **caja de carga**): textura, emisiva, tamaño en unidades de mundo, pulso, radio de click y color en el minimapa |
| `data/ammo/<code>.json` | **el aspecto de cada arma**: color, largo, grosor y duración del haz, con su variante `beam_skilled` (el disparo potenciado del perfil de piloto: más grueso y brillante) |

Agregar una nave nueva = soltar su PNG + escribir su JSON. Cero código.
Un JSON que apunta a una textura que todavía no existe **no tira el cliente**: cae al respaldo
y avisa por consola — el arte y el dato pueden ir a distinto ritmo.
Los anclajes se miden con `mex-orbit-art/tools/find-anchors.py <export.png>` en vez de estimarlos a ojo.

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
| `TURN_FLIGHT_DEG_PER_SEC` | `game/entity_node.gd` | 420 °/s | Giro **al emprender vuelo**: brioso en todos, para que la proa vaya delante |

## Mobiliario del mapa: portal y caja de carga

**Nada de esto tiene la posición en el cliente.** El portal es dato de BD
(`map_portal`) y llega **completo en `EnterMap`** — la spec del protocolo manda
que portales, estaciones y POIs se envíen enteros al entrar, no por relevancia.
La caja de carga la coloca el server al morir un alien (`BoxSpawn`). El cliente
solo pone el arte, y ese arte sale de `data/props/`.

- **`PortalNode`** (`game/portal_node.gd`): el **aro queda quieto** y es la capa
  emisiva —el vórtice— la que gira y late; rotar el sprite entero delataría los
  pernos del aro. Debajo va la etiqueta del sector destino, en `--violet` (el
  token que el sistema de diseño reserva para portales). Un portal con
  `is_working = 0` se pinta apagado y apenas alumbra. Clic = rumbo al portal;
  **el salto de sector es de E3**.
- **Caja de carga**: su pulso es de **alfa**, no de intensidad — es una luz de
  baliza que llama al jugador, no un reactor como el núcleo de un alien.
- **Minimapa**: estación y portales se dibujan como **rombos** (cian y violeta),
  forma distinta de los círculos de naves y cajas, para que el mobiliario fijo no
  se confunda con lo que se mueve.

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
