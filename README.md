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

### El bot ya no ve el sector entero

Desde que el game server aplica **relevancia por rango**, el cliente solo conoce lo que tiene a
2000 unidades. Eso rompió dos supuestos del autotest, y los dos se arreglaron sin tocar la
relevancia:

- **La caza empieza patrullando.** Con 15 Vex repartidos en 20800×12800, la probabilidad de tener
  uno a la vista al entrar es ~51%: quedarse quieto esperando presa era una moneda al aire. Ahora
  la fase 0 recorre un itinerario **fijo** por el sector (`AT_PATRULLA`) hasta que aparece una.
  Fijo y no aleatorio a propósito: un fallo del gate tiene que poder repetirse, y con destinos
  sorteados cada corrida barre un mapa distinto.
- **El bestiario fabrica su ejemplar.** Retratar las nueve especies nunca iba a poder salir del
  mundo: la relevancia solo deja ver unas pocas, y el diseño del sector manda **3-4 especies por
  mapa** (a veces una). Si la especie no anda cerca, `_maniqui_de_especie` monta un `EntityNode`
  con el mismo `setup` y el mismo JSON de assets que usa el juego — lo que se retrata es
  exactamente lo que se vería volando, pero ya no depende de dónde cayó el dado.

### La caza: elegir presa por distancia era el error

La nave vuela a 320 y un Vex vagabundea a 270. Uno que **huye** cierra a 50 unidades por segundo; otro
un poco más lejos que **viene** cierra a 590 — once veces más rápido. Elegir por distancia escoge
sistemáticamente al peor de los dos, y de ahí salía el timeout intermitente del gate: el peor tipo de
fallo, porque parece un bug del juego.

Abandonar a los 20 s no lo arreglaba, solo lo repartía: cada mala elección costaba 20 s y dos seguidas
se comían el reloj igual. Y mientras el bot perseguía a uno que huía, podía pasarle otro por delante
sin enterarse, porque estaba atado a su presa.

**Ahora se elige por tiempo de intercepción**, que se puede calcular porque el nodo conoce su
`objetivo` y su `speed`: la velocidad de acercamiento es la de la nave menos la componente de la presa
en la línea que las une. Si esa componente iguala a la nave, la presa se descarta en vez de
perseguirla. Y se reevalúa cada dos segundos, así que el bot deja de correr detrás de uno y se queda
con el que se acerque.

De paso la presa deja de ser solo `vex` y pasa a ser `vex` + `vexor`: **densidad de 15 a 23** en el
1-1. Ya no hay motivo para exigir una especie, porque desde que la venta pregunta al almacén qué hay,
al bot le sirve cualquier caja.

**Y se puede comprobar que está arreglado**, que es lo que distingue esto de "parece que va mejor". El
autotest imprime el tiempo de caza junto al **mínimo teórico** —`(distancia − alcance) / velocidad`—:

| caza real | mínimo | |
|---|---|---|
| 5,9 s | 4,4 s | |
| 7,9 s | 7,8 s | |
| 14,9 s | 16,3 s | más rápido que el mínimo: la presa vino hacia la nave |
| 3,7 s | 3,6 s | |

Va al límite geométrico. Lo que queda de variación **no es un fallo, es la distancia** a la que caiga
la presa. Antes del cambio, ocho corridas dieron una cola de 40 s; el techo de 45 s sigue ahí como
red, pero ahora **falla con nombre** —"la caza no logró ponerse a tiro en 45 s"— en vez de con un
TIMEOUT genérico que no dice en qué se atascó.

**Una prueba no puede heredar el MAPA de la anterior.** Desde que hay salto, la nave se queda donde la
dejó la corrida previa —correcto para el juego, veneno para una prueba—. El loop caza Vex y el
bestiario retrata a los nueve bichos, y los NPC solo viven en el `1-1`: arrancar en el `2-2` dejaba al
bot buscando presas en un mapa vacío hasta agotar el reloj. `dev-run` devuelve a TestBot al `1-1` antes
de esas dos. `-Salto` **no** se resetea: encadenar saltos entre corridas es información, no ruido.

**Una prueba no puede depender de la suerte.** La fase de venta vendía `material_asterium` a ciegas, y
se colgaba la tarde que los bichos no soltaban ese material: esperaba para siempre una confirmación
que no iba a llegar. Ahora pregunta al almacén qué hay que el NPC compre. Es el mismo defecto que el
timeout de la caza — una prueba que a veces falla acaba haciendo que se ignoren los fallos de verdad.

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
| `data/ships/<code>.json` | textura, tamaño en pantalla, radio de click, **anclajes de toberas** y color de la llama |
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
| `TURN_TIME` | `game/entity_node.gd` | **0.2 s** | Giro de nave: ease Quad-out continuo por el camino corto — el del cliente 3D original. La cuantización de 32 pasos murió con el mundo de sprites (F1) |
| `DEAD_ZONE` | `game/entity_node.gd` | 2 px | Destino encima de la nave en vuelo no re-orienta (anti-trompos) |
| `HOLD_RESEND_SEC` | `game/world.gd` | 0.25 s | Cadencia del reenvío con click sostenido (tope real: rate limit 10/s del contrato) |
| `HOLD_MIN_DELTA` | `game/world.gd` | 60 px | El destino debe moverse al menos esto para reenviar |
| `CLICK_RADIUS` | `game/world.gd` | 34 px | Radio de click sobre entidades, CONSTANTE en pantalla (× `unidades_por_pixel` de la cámara 3D) |
| Umbral de snap | `entity_node.gd::reconcile` | 220 px | Deriva mayor a esto = teletransporte al eco del server; menor = lerp 0.35 |
| Cámara y zoom | `game/mundo3d.gd` | FOV 30 · d 1740/zoom · tilt 135 · zoom [1,3] ×1.2 · tween 0.3 s · tilt−20° con zoom | La cámara del DO 3D original completa (F1). El rango 0.621–1.157 era del mundo de sprites y murió con él; se entra en zoom 1 (el encuadre de juego) |
| Acelerador de llamas | `entity_node.gd::_process` | subida 3.0/s, caída 4.0/s | Qué tan rápido encienden y apagan las llamas al volar/frenar (su color viene del JSON de la nave) |
| Ventana | `project.godot` | maximizada, `canvas_items`/`expand` | Arranca a pantalla completa; el lienzo lógico sigue siendo 1280×720 |
| `COLLECT_ARRIVE` | `game/world.gd` | 200 px | Llegar a esto de la caja dispara el CollectBox (el server valida 250) |
| Disparos (F2) | `data/ammo/*.json` + `beam_3d.gd` | vida 0.35 s · rampa 0.10 · ciclo UV 0.4 | El HAZ del original: quad aditivo que se estira de la boca viva al blanco con el patrón fluyendo por UV-scroll, siguiendo a las dos naves. El proyectil que viajaba (modelo del prototipo 2D) murió aquí |
| Luces de efectos (F2) | `mundo3d.gd::luz_efecto` | pool de 3 · disparo 0xF7C0C0/200 · explosión 0xDEE4C8/400 | El presupuesto del original (G§7.2): pre-creadas, reciclado circular, tween de fundido. La clave `luces` de la calidad las gobierna (0/1/pool) junto con la luz del héroe |
| `world_size` estación | `data/props/station.json` | **1100** | Recalibrado F2: el 2460 era del sprite cenital; en perspectiva la torre medía ~4500 de alto y a zoom cercano era una montaña |
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
| `BANK_MAX` / `BANK_EASE` | `game/entity_node.gd` | ±20° · 0.2 s | **Banking** de crucero: el alabeo es el error angular pendiente del giro, con tope y ease exponencial (constantes del cliente 3D original) |
| `BANK_COMBATE_*` | `game/entity_node.gd` | ganancia −2 · ±10° · 0.08 s | Banking **atacando en movimiento**: invertido (se abre hacia el blanco), más contenido y más rápido |
| `HOVER_AMP` / `HOVER_CICLO` | `game/entity_node.gd` | 5 px · 2 s | Flotación idle Lissajous del dibujo (solo naves, solo paradas, fase propia, fundido 0.5 s al arrancar) |
| `LLAMA_IDLE` | `game/entity_node.gd` | 0.7 | Ralenti del motor de una nave de **jugador** parada (NPC apaga a 0); en vuelo, 1 |
| `GLOW_HP_MIN` | `game/entity_node.gd` | 0.35 | Suelo del brillo emisivo a 0% de casco: malherido se apaga, no se muere de golpe. Multiplica el pulso en 2D **y** 3D |
| HUD de entidad | `entity_node.gd::_construir_hud` | barras a −52 px · nombre a +44 px | Vive en la capa proyectada (píxeles de pantalla): tamaño constante a cualquier zoom por construcción (F1) |
| `ZOOM_TWEEN_SEC` | `game/world.gd` | 0.3 s | El zoom llega con tween Quad ease-out (el gesto del original); el rango y el paso siguen siendo los calibrados volando |
| `DOBLE_CLICK_MS` | `game/world.gd` | 500 | Doble click sobre una entidad = fijarla y atacar (el gesto canónico); el primer click solo selecciona |
| Flash + chispas de explosión | `world.gd::_explotar` | flash ⌀ 6×radio en 0.25 s · 24 chispas 100–200 u/s | Las capas extra de la explosión multi-capa del original, aditivas y procedurales (cero assets); escalan con el `click_radius` de la víctima |
| Marcador de selección | `entity_node.gd::set_selected` | 1.5× → 1× en 0.3 s | El fijado "cierra" sobre el blanco, como el original |
| Fondo (F3) | `game/fondo3d.gd` | capas −3500+550·i · jitter −500..−200 · telón −4200 · polvo 1500 en caja 4200³/rejilla 1000 · TILE_FACTOR 1.5 · huecos 25% | El fondo del original completo: cielo con twinkle (`cielo.gdshader`, dos máscaras móviles), mosaicos de nebulosa con jitter vertical POR TILE (el paralaje lo hace la cámara), planetas/sol a cota por su `p_factor`, cadena de flares proyectada, y polvo estelar anclado al mundo que se recentra a saltos de rejilla. Determinista por mapa (semilla = hash del code). `MapBackground`/`Starfield2D` murieron |
| `AQ_*` | `game/quality.gd` | ventana 20 s · baja <10 fps · sube >60 | Auto-calidad con histéresis: escalera de 4 recortes **transitorios** (mosaicos → llamas → explosiones → atlas/3D) aplicados como tope sobre el preset, sin tocar lo persistido. Sin foco no mide; en autotest no corre |
| Encuadre del minimapa | `ui/minimap_window.gd` | 12.5% de cada lado · `--txt` 45% | Las 4 esquinas del viewport llevadas al mapa (registrado en §8 del sistema de diseño) |

## FASE 1: el cliente ES 3D (29-ago-2026)

Dictamen y plan en `mex-orbit-docs/03-guidelines/plan-cliente-3d.md`. El mundo dejó de ser un
canvas de sprites con SubViewports por bicho: ahora es **una escena 3D única** (`game/mundo3d.gd`)
mirada por la **cámara del DarkOrbit 3D original**: perspectiva FOV 30°, elevación 45°
(tilt 135), distancia `1740/zoom`, zoom continuo **[1,3]** con rueda ×1.2/÷1.2 y tween 0.3 s, y el
**acoplamiento tilt↔zoom** (al acercar, la cámara baja hasta 20° hacia el horizonte — la
perspectiva de los aliens cambia con el zoom, que fue el detonante de todo).

- **Entidades**: malla GLB en alta (vex, vexor, vorax, la Phoenix, la estación); **quad tumbado**
  con su PNG/atlas para el resto — el placeholder del original. Banking y hover ahora son 3D de
  verdad; las llamas y las bocas de cañón salen de los marcadores del GLB en espacio real.
- **HUD proyectado**: nombres, barras, números de combate, marcador de selección y etiquetas de
  portal viven en una capa 2D reposicionada con `unproject` — tamaño constante en pantalla.
- **Click**: rayo→plano y=0 (`Mundo3D.a_mundo`); radios de click en píxeles constantes
  (`CLICK_RADIUS × unidades_por_pixel`). Minimapa con el **trapecio** del encuadre.
- **Murió con el canvas**: la Camera2D y el rango 0.621–1.157, el giro cuantizado de 32 pasos
  (ahora ease continuo 0.2 s, el del original 3D), el shader de relieve y su prueba (la propiedad
  se cumple por construcción), `MapBackground`/`Starfield2D` (F1 pone un telón a −3500; F3 monta
  el fondo real), el SubViewport por entidad y el reactor 2D de la estación.
- **Gates**: `-Autotest` completo, `-Salto` y bestiario alta en verde sobre la escena única.

**FASE 2 (mismo día)**: el disparo es el **haz del original** (`beam_3d.gd` + `beam_scroll.gdshader`
— estirado de la boca viva al blanco, UV-scroll, rampa y fundido; murió `projectile_2d`), el mundo
gana el **pool de 3 luces de efectos** con destellos de disparo y explosión (clave `luces` en la
calidad: 0/1/pool, que también gobierna la luz del héroe y entra en la escalera de auto-calidad), y
la estación se recalibró a huella 1100 (la torre ya no se come la pantalla a zoom cercano).

**FASE 3 (mismo día)**: el fondo es **profundidad de verdad** (`fondo3d.gd`): cielo procedural con
el twinkle del original (`cielo.gdshader` — dos máscaras de ruido móviles multiplicadas, teñido por
mapa), mosaicos de nebulosa a `−3500 + capa·550` con **jitter vertical por tile** (−500..−200: el
paralaje entre tiles lo produce la cámara, la joya del tilemap del original), planetas y sol a cota
según su `p_factor` heredado, la cadena de flares del sol proyectada al HUD (oclusión pendiente
F4), y el **polvo estelar** como partículas sueltas al mundo alrededor del foco, recentradas a
saltos de rejilla — la capa que vende el vuelo. Todo del `data/maps/<code>.json` de siempre y
determinista por mapa. **Dial del cielo**: la base del `cielo.gdshader` es espacio LINEAL — quedó
en `(0.0012, 0.0016, 0.0040) + tinte·neb·0.012`; con los valores ×10 originales el cielo entero se
lavaba a gris (~0.21 sRGB) y ahogaba las nebulosas — el DO real es casi negro con vetas tenues. Gates `-Autotest` y `-Salto` en verde. **Deuda de arte conocida**: las
nebulosas actuales no son tileables y el mosaico enseña costuras — pide arte con bordes que casen
(o atlas de variantes), no más código.

## El puerto de los guidelines 3D (ago-2026)

La sensación del cliente 3D de DarkOrbit está destilada en
`mex-orbit-docs/03-guidelines/darkorbit-3d-guidelines.md` (ingeniería inversa completa, con
constantes literales). De ahí se portó, con sus números exactos: **banking** por error angular,
**flotación idle**, **ralenti de motor**, **zoom con tween**, **HUD de entidad
constante en pantalla**, **explosión multi-capa**, **glow ligado al casco**, **doble click de
ataque**, **cierre del marcador**, **orden de profundidad del fondo** (`1000/pFactor`),
**fade-ins**, **twinkle**, **encuadre del minimapa**, **carga asíncrona del GLB con placeholder**
(el PNG de media, que el horno ya fabrica del mismo modelo) y la **auto-calidad por FPS**.

Lo que NO se portó, a sabiendas — cada uno con su porqué ya registrado:

- **El shake de cámara por daño.** Se portó primero como "sacudir al recibir cualquier golpe" y
  volando se sintió un temblor constante; jugando el DO 3D real se comprobó que **allí tampoco
  sacude con daño normal** — su `shakeScreen()` solo dispara con el tipo de daño `"I"`
  (detonaciones tipo mina/kamikaze) y con efectos que declaran `shakeScreen="true"` en su XML. El
  agente del guideline generalizó mal; la prueba en vivo mandó y el guideline quedó corregido. Se
  quitó **entero** (la espiral de 24 ms queda en el historial de git) hasta que v1 tenga minas.

- **El ease de giro de 0.2 s del 3D.** El giro de nave v1 (0.1 s fijo + 32 pasos) está calibrado y
  **validado volando**; es el look del prototipo y manda sobre el guideline.
- **El rango de zoom [1,3] y los pasos ×1.2/×0.8.** El rango v1 (0.621–1.157, ×1.1) se calibró
  volando contra este arte; del original se porta el *gesto* (el tween), no los números.
- **El snap a píxel de toda la cadena.** En DO funcionaba porque 1 unidad = 1 píxel a zoom 1; aquí
  el zoom es fraccional (0.621) y redondear a enteros de mundo no cae en píxeles de pantalla — no
  hay shimmer que arreglar por esa vía.
- **La estela ribbon (12×30 ms).** La estela sigue retirada (ver su sección); si vuelve, la receta
  del ribbon del original es el punto de partida, con su vida larga frente a la eslora.
- **El UV-scroll de beams.** El disparo v1 es un proyectil que viaja 0.15 s (modelo del prototipo,
  registrado en Diales); no hay haz sostenido al que rascarle las UV.
- **La estación** carga su GLB en síncrono a propósito: es una, y llega con el `EnterMap`.

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
chip de icono, botón `–` de 17 px, arrastre por la cabecera con clamp al viewport y grip diagonal.

**Un solo botón, y no dos.** El chrome nació con `–` y `×` porque el prototipo los tenía, pero aquí
hacen exactamente lo mismo: toda ventana vuelve desde la taskbar, así que "cerrar" y "minimizar" no
se distinguen ni en lo que hacen ni en cómo se vuelve. El `×` era herencia del escritorio. Una ventana se construye diciendo qué icono y qué título lleva; el spec está en un sitio.

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

**La Estación era el último panel hecho a mano**, y el que peor encajaba en el §1: aparecía y
desaparecía sola según la distancia a la base, sin icono ni forma de abrirla. Pasarla a ventana obligó
a resolver el choque, y la respuesta no fue quitarle la automática:

> **La cercanía condiciona las acciones, no la ventana** (§1.11). Se abre siempre desde su icono
> —para mirar el almacén desde el otro lado del mapa—, pero descargar y vender solo se habilitan
> estando en rango.

Un botón apagado enseña que ahí hay algo; una ventana que desaparece no enseña nada. Y conserva la
comodidad: al **entrar** en rango se abre sola, pero si el jugador la cierra estando atracado no se le
vuelve a abrir hasta que salga y vuelva — una ventana que se reabre sola tras cerrarla no es cómoda,
es terca.

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
- **Un contenedor no encoge solo.** El zoom del minimapa cambiaba el canvas y no la ventana: el aro
  se quedaba con el ancho anterior, el contenedor estiraba el canvas para llenarlo y el mapa se
  dibujaba con el ancho viejo y el alto nuevo — **deformado**, que es justo lo que el §8 prohíbe. Hay
  que pedirle a la ventana que se reajuste (`reset_size()`) y decirle al canvas que **no** se estire
  (`SIZE_SHRINK_CENTER`). Y como un mapa estirado sigue pareciendo un mapa en una captura, la prueba
  compara el ratio contra un número en los cinco pasos de zoom.
- **Una rejilla alinea; una fila por stat, no.** Las tres barras de la Nave estaban en `HBox`
  independientes, así que cada fila se repartía el ancho por su cuenta y la de Bodega —cuyo valor
  `0 / 300` es más corto que `4.000 / 4.000`— salía desplazada. Con un `GridContainer` de tres
  columnas, las columnas miden lo mismo en todas las filas y las barras quedan a plomo.
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

## Relieve: que la luz no gire con la nave

El arte es cenital y los sprites rotan, así que su iluminación giraba con ellos. `relieve.gdshader`
reilumina el sprite con un mapa de normales contra una luz **fija en el mundo**
(`AssetDefs.LUZ_MUNDO_GRADOS`, una sola para todo o el mundo se rompe). Al virar, el reflejo barre el
casco. No da volumen —la silueta sigue plana— pero es lo que separa un objeto de una calcomanía.

La pieza clave es el uniform `giro`. El mapa de normales vive en espacio de **textura** y el sprite
rota: si no se contrarrota la normal antes de iluminarla, la luz gira con la nave y no se ha hecho
nada. Se empuja desde `_set_visual_angle`, que corre exactamente cuando cambia el rumbo — un uniform
por giro, no uno por fotograma.

Lo llevan la nave, **los nueve bichos, la estación, el portal y la caja de carga** — el mundo entero
se ilumina desde el mismo sitio. El material lo construye `AssetDefs.material_relieve()`, en un solo
lugar: cuatro copias de la misma receta son tres que se quedan atrás el día que cambie la luz, que es
justo lo que pasó con el recorte del croma. Cada asset tiene un mapa por camino —el del
atlas cuando está animado, el del PNG cuando no— y elegirlo mal sería peor que no tener ninguno: un
mapa de normales que no casa con la silueta que ilumina inventa bultos donde no hay nada.

**La estación, el portal y la caja son un caso distinto y conviene no confundirlo.** No rotan, así que
su luz nunca giraba con ellos; lo que ganan no es eso sino consistencia. Su render viene iluminado desde arriba en el eje de
cámara —se lo pide el contrato de render, y con razón, porque es lo único que sobrevive a un sprite
que gira— y esa es la iluminación más plana que existe. Al lado de una nave con forma se leía como un
decorado pegado. Su `giro` se queda en cero para siempre, y el uniform se deja igual para que el
shader sea uno solo y no dos que se parecen.

### Dos correcciones que costaron un portal y una caja

La primera fórmula era `ambiente + difusa · lam`, y con un lambert medio de **0,47** eso deja el asset
más oscuro de lo que venía, siempre. En un bicho de metal no se notaba; en una caja con tubos de neón
y en un portal de plasma se veía a la primera. Ahora la luz va **centrada en uno**
(`1 + contraste · (lam − 0,5)`): con `lam = 0,5` no cambia nada y los dos lados se reparten alrededor,
así que da forma sin poder apagar la pieza en conjunto.

Y **lo que tiene luz propia no se ilumina.** Un tubo de neón o el plasma de un portal no se apagan
porque la luz venga del otro lado; ahí el sombreado no es forma, es un error — no hay superficie que
iluminar. Se detecta por el canal más alto, que es lo que separa un emisivo saturado de un metal
claro. En el Ferox eso valía un 2% y por eso no se escribió al principio; en la caja vale el negocio
entero.

En el portal, el relieve va sobre el **aro** y no sobre el vórtice: ese ya se dibuja en aditivo con su
propio pulso, y montarle un material encima lo apagaría.

Cede ante la **ondulación**, que ya ocupa el material del sprite. No es un límite técnico sino de
sentido: la ondulación es movimiento estructural y el relieve es acabado. Si un bicho quiere las dos,
se fusionan en un shader; no se pelean por el slot.

### La prueba, y los cinco falsos OK que dio antes de servir

Vive en el **modo bestiario** (el rápido), no al final del loop: es una prueba de arte, y una que solo
se puede correr pagando tres minutos de loop no la corre nadie.

Comprueba dos cosas, y las dos son exactas:

| mitad | qué afirma | por qué es exacta |
|---|---|---|
| fontanería | girar la nave mueve el uniform `giro` | se lee el número, no se miran píxeles |
| efecto | con la nave **quieta**, cambiar solo ese número mueve los píxeles | misma geometría y mismo sitio: si el shader lo ignorase, las dos fotos serían idénticas al bit |

Juntas cubren la cadena entera, y el umbral puede ser ridículo (0,02 contra un 0,30 medido) porque el
caso roto es **cero exacto**, no "un número pequeño".

Ya se ganó el sueldo: al desactivar la protección de emisivos para la medida se subió solo el borde
inferior del `smoothstep`, dejándolo invertido (`smoothstep(2.0, 0.85, x)`). En GLSL eso no es
"protección desactivada" sino comportamiento indefinido — devolvía textura cruda sin iluminar. La
prueba lo cazó en la corrida siguiente.

Costó cinco versiones. Las cuatro primeras **pasaban con el relieve roto a propósito**:

1. **Medir "hacia dónde cae el lado claro"** — lo mandaban las barras de vida y el nombre, que son
   brillantes y no rotan.
2. **Umbral de luminancia fijo en 0,28** — el casco ronda 0,16, así que no descartaba los píxeles
   flojos, los descartaba todos. Devolvía cero, y cero se leía como "no se movió nada".
3. **Esperar cuatro fotogramas a que la cámara volviera** — el seguimiento es un `lerp` a 8/s, o sea
   decenas de fotogramas. Medía el vacío, y el vacío es estable.
4. **Coordenadas de lienzo contra píxeles físicos** — con `stretch/mode = canvas_items` el lienzo mide
   1370×720 y la ventana 1920×1009. La caja caía 1,4× fuera de la nave, sobre campo de estrellas
   quieto: dos fotos idénticas, o sea "la luz no se movió". El falso OK perfecto.

La quinta sí distinguía —comparaba dos fotos a rumbos distintos deshaciendo el giro— pero **el margen
era de 0,03 sobre una varianza de 0,06 entre corridas**, así que habría fallado sola un día
cualquiera. El suelo venía de que el motor dibuja el sprite girado con filtrado bilineal: dos rumbos
nunca son una rotación exacta el uno del otro por mucho que la iluminación sí lo sea. La lección no
fue afinar el umbral sino **quitar la rotación de en medio**: si las dos fotos son del mismo rumbo, no
hay suelo que esquivar.

## La estela de chispas, y por qué se fue

Cada tobera soltaba además una estela de chispas **al mundo** (`local_coords = false`), para que el
rastro se quedara atrás como el humo de motor del prototipo. La idea es buena y la ejecución no
llegaba: con 0,38 s de vida la nave **adelantaba a sus propias chispas**, así que no se leían por
detrás sino como motas de colores encima del casco. Una estela que se ve como suciedad no es una
estela.

Con ella se fue el nivel 2 del dial `engine` —era lo único que había ahí— y las claves `length`,
`width`, `lifetime` y `core_color` de `engine_trail`, que solo usaban las chispas. La llama se queda:
esa sí dice algo, porque crece con el empuje.

Si algún día vuelve, el problema a resolver primero es el de siempre en una estela soltada al mundo:
**la vida de la partícula tiene que ser larga comparada con lo que tarda la nave en recorrer su
propia eslora**, o el rastro nace ya pisado.

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
| `engine` | sin llamas | llamas | llamas |
| `collectable` | caja congelada en su fotograma 0 | ídem | caja animada |
| `background` | solo polvo estelar | fondo y planetas | + mosaicos de paralaje |
| `explosion` | no se dibuja | se dibuja | ídem |

**El corte caro está entre Media y Alta**: ahí los atlas dejan de cargarse y se liberan **106 MB**
de VRAM (los **nueve** bichos, la caja y el portal). Media conserva los shaders a propósito — cuestan casi nada (una operación de fragment sobre un
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

## Filtrado de textura: mipmaps sí, pero no en los atlas

La nave se dibuja a 141 px desde una textura de 512 y el zoom de cámara entra en 0,621: ahí son unos
noventa píxeles sacados de quinientos. **Sin mipmaps la GPU muestrea la textura entera con un filtro
de 2×2 téxeles**, así que el detalle fino no se promedia — se aliasa. El síntoma es un contorno
punteado que hierve al moverse, y era la mitad técnica de «de lejos no se ve bien». La otra mitad es
cuánto detalle trae el render, y está en el README de `mex-orbit-art`.

En `EntityNode._construir_visual`, el filtro se elige por **tipo de textura**:

| textura | filtro | por qué |
|---|---|---|
| PNG suelto | `LINEAR_WITH_MIPMAPS` | se reduce mucho; los mipmaps son justo para eso |
| atlas de fotogramas | `LINEAR` | los mipmaps promedian a ciegas y en los niveles bajos **mezclan celdas vecinas**, o sea un fotograma con el siguiente |

Esa distinción ya estaba calculada unas líneas más arriba (`anim.is_empty()`), que es la razón de
ponerlo ahí y no en un ajuste global del proyecto: `default_texture_filter` no sabe distinguir un
atlas de un PNG.

Hay que activarlo **en los dos sitios**: el filtro en el nodo y `mipmaps/generate=true` en el
`.import` de la textura. Solo con el filtro no hay niveles que muestrear y Godot cae al nivel 0 sin
avisar.

Y el `.import` lo genera Godot, no nosotros: una textura nueva nace con los mipmaps **apagados**, así
que activarlos a mano en cada una es un olvido esperando. Por eso el default está invertido en
`project.godot` (`[importer_defaults]`): van activados, y los atlas los apagan uno a uno en su propio
`.import`. La razón es cuál de los dos olvidos duele más — una textura suelta sin mipmaps se aliasa de
lejos y nadie lo ata a una casilla de importación, mientras que un atlas con mipmaps se nota enseguida
porque mezcla fotogramas, y además su lista es corta y conocida (`*-anim.png`). Default seguro con
excepciones explícitas, en vez de default inseguro con excepciones que hay que acordarse de poner.

Los mipmaps cuestan un 33% más de VRAM, que es la otra razón para no ponérselos a los atlas: el de la
estación pasaría de 40 a 53 MB para generar niveles que su sprite tiene prohibido usar.

Medido sobre la captura de zoom lejano del autotest: la energía de alta frecuencia baja de 15,54 a
14,42, y a ojo los tubos de los cañones pasan de línea de puntos a tubo sólido.

**Las dos Phoenix conviven** en `data/ships/phoenix.json` (`_v1` y `_v2`) para poder compararlas en
juego. Cambiar de una a otra es copiar `texture`, `engines` y `cannons` del bloque que toque a los
campos de arriba. **Los anclajes no son intercambiables**: cada render tiene los suyos —la v1 tiene
cuatro toberas y la v2 tres con boca visible—, y mezclarlos pone la estela y los láseres donde no hay
tobera ni cañón.

**El autotest saca una captura del extremo del rango** (`autotest-zoom.png`, fase 96). Nació mirando
el zoom LEJANO, porque la prueba solo veía la nave a tamaño de crucero y ahí el arte nunca falla. Al
calibrarse el rango, el lejano pasó a ser el zoom por defecto —o sea, lo que ya retratan todas las
demás capturas— así que la fase apunta ahora al **cercano** (`ZOOM_MAX`), que es el extremo que
ninguna otra prueba mira. Va por la constante y no por un número a mano: con un valor suelto, el día
que se recalibre el rango la prueba retrataría un encuadre que ya no existe, que es peor que no
retratar nada.

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
| Skarn | 196 px | 320 | 48 | 19,1 MB |
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
| Skarn | 14,7× | la peor, y **no por mal vídeo**: la roca casi no cambia entre fotogramas (paso normal 0,28), así que cualquier salto canta. Vaivén |

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

**Una costura enorme no significa un vídeo malo.** El Skarn cierra a **14,7×**, la peor cifra del
catálogo, y su vídeo está impecable — el mejor encuadre de todos, con 0,1% de deriva. Lo que pasa es
que una roca casi no cambia entre fotogramas: su paso normal es **0,28** cuando el del Mordax es 3,16.
Contra un paso tan pequeño, cualquier salto se dispara en la proporción. Es el recordatorio de que la
métrica es una **razón**, y una razón se puede disparar por el denominador.

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

## El salto de sector

**Se salta con la tecla `J`, no con el clic.** El clic sobre un portal solo pone rumbo. Y no es una
preferencia: como ahora se aterriza **encima** del portal de vuelta, con el salto en el clic el
aterrizaje lo re-dispararía solo. La tecla y llegar encima son la misma decisión.

**El salto negocia SIEMPRE con el servidor del destino**, aunque hoy lo sirva el mismo proceso. Podría
haber un atajo —si el mapa es mío, muevo al jugador en memoria— y sería más rápido; pero entonces el
camino del handoff no se ejecutaría nunca hasta el día que se parta la carga, que es el peor momento
posible para descubrir que no funciona. Sin atajo, **partir mañana es cambiar filas de `map_server`**.

**Y no hace falta credencial nueva.** El origen persiste la nave **ya en el mapa destino** y avisa al
cliente de a dónde reconectar; el cliente vuelve con el token de reconexión que ya tenía. El estado
nunca pasa por manos del cliente —va por BD, que es por donde ya iba— y no hay canal nuevo entre
servidores que desplegar y vigilar. El diseño con ticket firmado que se barajó primero era correcto y
resultó innecesario.

Eso obligó a generalizar `Resume`, y la generalización es la parte bonita: **hay dos formas de volver
y ahora las dos entran por la misma puerta.** Se cayó el socket y la nave sigue aquí en gracia, o se
llega de otro mapa y este servidor no te ha visto nunca. Lo segundo **no es un error** — es
exactamente lo que pasa al cruzar un portal. Antes respondía `RESUME_EXPIRED`, así que el salto llegaba
al server, persistía, y dejaba al jugador fuera de todo mapa.

**Se entra donde se dejó el juego.** Era un fallo que ya existía y que no se podía ver con un solo
mapa: al entrar siempre se iba al inicial. Con dos mapas, eso teletransporta a quien cerró sesión en
otro sitio.

**Todo va en paralelo con la animación; lo único que espera es APLICAR la llegada.** Al pulsar `J`
arrancan a la vez el encendido y el `JumpRequest`; en cuanto responde el `JumpHandoff` se abre ya la
conexión con el servidor del destino, y lo que ese servidor manda se **retiene en un buzón** en vez de
aplicarse. Al terminar el encendido se suelta el buzón entero, en orden.

Eso importa por lo que viene. Con los mapas en un solo proceso da igual; en cuanto vivan en máquinas
distintas, **abrir el socket y hacer el handshake son cientos de milisegundos**, y si eso ocurriera
*después* de la animación se sumaría en vez de solaparse — justo lo que los 2,1 s existen para evitar.
Medido en local:

| | |
|---|---|
| La conexión con el mapa nuevo queda lista en | **83 ms** |
| El buzón se suelta a los | **1851 ms** (cuando acaba el encendido) |
| **Holgura** | **1768 ms** |

Ese es el margen que tendrá un servidor remoto antes de que el salto empiece a notarse lento.

**El `Ping` no se retiene.** Es del transporte, no del mundo: guardarlo dos segundos sería dejar que el
servidor nuevo nos diera por muertos justo mientras llegamos.

**Y esto costó dos intentos.**

En local el server contesta en **111 ms** y la animación dura **2100**: el mapa nuevo llegaba casi
veinte veces antes de que el portal terminara de abrirse, y montarlo hacía `queue_free()` del portal
que estaba encendiéndose. Pulsabas `J` y aparecías en otro sector de golpe, sin ver nada.

El primer arreglo aplazaba el `EnterMap` y montaba el mapa al acabar la animación. **No funcionaba**:
tras el `EnterMap` viene el resto del mundo nuevo —la nave, los NPC, las cajas— y eso seguía llegando
y entrando en el mapa **viejo**, que se desmontaba dos segundos después llevándoselo por delante.

El segundo retrasaba la **reconexión** entera. Funcionaba, pero tiraba a la basura el motivo de tener
2,1 s de animación: el paso caro —conectar con el servidor del destino— quedaba fuera del hueco.

El tercero es el de arriba: conectar ya y retener la llegada. De pulsar `J` a tener el mapa nuevo,
**1879 ms**, marcados por la animación y no por la red. En calidad media o baja no hay atlas, así que
no hay nada que esperar ni que retener y el salto es inmediato — **128 ms**, y ahí eso es lo
correcto.

Los 2,1 s no son un adorno que sobra cuando la red es rápida: **son el ritmo del salto**. Sin ellos,
cruzar un portal no se siente como cruzar nada.

**Mientras se salta, el cliente NO conduce la nave.**

Durante los ~2 s de encendido el socket **ya es el del servidor destino**, pero en pantalla sigue el
mapa viejo: la cámara, el cursor y el autopiloto hablan en coordenadas del mapa que se está dejando.
Con el ratón pulsado —lo normal al saltar huyendo— el vuelo sostenido seguía mandando **esas**
coordenadas al servidor **nuevo**, que las aceptaba como buenas. Por eso se aterrizaba encima del
portal y un instante después la nave salía disparada: llevaba un destino del mapa anterior metido por
la puerta de atrás.

Entre pulsar `J` y ver el mapa nuevo, la nave no está en ningún sitio que el jugador pueda ver bien.
Lo único correcto es no tocarla.

**Y este camino era INTESTABLE**, que es la razón de que el fallo llegara tan lejos. `_process_hold_move`
leía `Input.is_mouse_button_pressed` a pelo, y en headless no hay ratón que pulsar: la prueba salía por
el early-return sin ejecutar nada. Ahora el cursor entra por `_cursor_mundo()` y el "sigue pulsado" por
`_sigue_pulsado()`, que la prueba puede suplantar. **Un camino que solo existe con un dedo encima es un
camino que nadie prueba** — y ahí es donde se esconden los fallos que el jugador ve y el gate no.

Con eso, la prueba reproduce el fallo (**485 unidades de deriva**) y pasa con el arreglo.

**El destino del movimiento pertenece al MAPA, no al jugador.** Al hacer clic en un portal se guarda su
posición como autopiloto, y esas son coordenadas del mapa **viejo**. Sin limpiarlas al desmontar, se
aterrizaba encima del portal y un instante después la nave pegaba un salto hacia la nada — el
autopiloto reanudando hacia un punto que ya no significa lo mismo.

`_hold_move` **no** se limpia, a propósito: se recalcula del cursor en cada fotograma, así que si el
jugador sigue con el botón pulsado —que es lo normal cuando se salta huyendo— la marcha continúa sola
y hacia donde apunta, que es lo que se espera.

**Y el primer test de esto no servía.** Comprobaba que la nave se quedaba donde aterrizó, pasaba, y
seguía pasando con el arreglo desactivado. Dos motivos, los dos instructivos:

- **Volaba justo hasta el portal**, así que el autopiloto se completaba y se limpiaba solo antes de
  saltar. El fallo solo aparece saltando **en marcha**, con un destino lejos y sin alcanzar — que es
  exactamente como se salta huyendo.
- **El umbral era de 900 unidades.** La nave vuela a 320 u/s: en el segundo y medio que se observa
  recorre 480 si algo tira de ella. Un margen de 900 no distingue "quieta" de "arrastrada".

Con las dos cosas corregidas, la prueba falla con el fallo (**475 unidades de deriva**) y pasa sin él.
La regla que deja: **un test de regresión hay que verlo fallar**. Si no se ha visto en rojo, no se sabe
si prueba algo.

**El alcance del salto no es el radio de clic.** El del clic (190) es para seleccionar el portal con
el ratón y es más pequeño a propósito; el del salto (600) tiene que **casar con el del server**, que
valida otra vez. Si el del cliente fuera mayor, pulsarías `J` y recibirías un *"estás demasiado
lejos"* sin entender por qué; si fuera menor, no podrías saltar desde donde el server sí te deja.

**La petición sale cuando ARRANCA el encendido, no cuando termina.** Los 2,1 s de animación son
exactamente el hueco donde cabe el viaje al server: si contesta antes, el mapa aparece al cerrarse el
encendido; si tarda más, la animación ya terminó y solo se espera lo justo. Pedirlo al final habría
sumado los dos tiempos en vez de solaparlos.

**El éxito no tiene mensaje propio**: se anuncia con un `EnterMap` nuevo, que es exactamente lo que el
cliente necesita recibir y ya sabía procesar. Un `JumpOk` sería un mensaje que no aporta estado. El
rechazo va por `ErrorReply` — nunca silencio.

`EnterMap` llega ahora por **tres** motivos distintos: entrar, reconectar y saltar. Los dos primeros
traen el mismo mapa y todo se conserva; el tercero trae otro, y lo que sobrevive es solo lo que **no
pertenece al mapa** — las ventanas, el chat, los ajustes. El mobiliario, las entidades y el fondo son
del mapa viejo y se van con él.

**Un código de error dice de qué FAMILIA es el fallo, no de qué iba.** El manejador traducía `TOO_FAR`
a un texto fijo —*"Demasiado lejos de la caja"*— y en cuanto el salto empezó a usar ese mismo código,
ese texto pasó a mentir. Ahora manda el `detail` que envía quien lo emite, que es el único que sabe.

**`-Salto` es su propia prueba.** El portal del `1-1` está a ~19.000 unidades de la base y llegar
cuesta un minuto: meterlo en la puerta rápida la doblaría de largo. La puerta sí comprueba, gratis, que
un salto pedido **desde lejos se rechaza** — eso prueba el cableado entero (mensaje, ruta, validación y
`ErrorReply` de vuelta) sin volar a ningún sitio.

Y llegar no basta: `-Salto` comprueba que se llega **entero** — con nave, con portales, y con uno que
vuelva a casa. Un mapa sin puerta de vuelta es una trampa, no un destino.

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

## Entrar y darse de alta

La pantalla de entrada tiene **dos modos en el mismo card** —`ENLACE` y `ALTA`— con el selector
segmentado del §7. En alta aparecen dos campos más (correo y nombre de piloto), y al crear la cuenta
**entra solo**: el jugador acaba de teclear esos datos y volver a pedírselos no comprueba nada.

Una pantalla aparte habría sido un segundo logo, un segundo card y un "volver", tres piezas nuevas
para un formulario que comparte dos de sus cuatro campos con el que ya existía.

Las reglas del server (usuario y piloto de 3 a 32, contraseña de 8) están repetidas en el cliente a
propósito, para poder decir **qué** falta antes de gastar un viaje y recibir un 400 que no explica
nada. El server sigue validando: esto es cortesía, no seguridad. Y cada código de respuesta dice algo
distinto —409 se arregla cambiando el nombre, 403 no se arregla de ninguna manera—, así que se
traducen por separado en vez de a un "no se pudo" que obligaría a probar diez nombres contra una
puerta cerrada.

El gate lo comprueba **sin red**: cambia de modo, verifica que aparecen los dos campos, que la
validación rechaza un formulario vacío y que al volver a `ENLACE` desaparecen. No registra una cuenta
de verdad porque eso ensuciaría la base con una cuenta por pasada; que el server acepta el alta ya lo
prueba el despliegue. Y deja una foto en `autotest-alta.png`, porque esa pantalla no la retrata nadie
más.

## Despliegue

El cliente se publica como **exportación Web**: los testers abren
[astrion.turname.mx](https://astrion.turname.mx) y ya está, y actualizar es reexportar.

```bash
ssh root@74.208.108.67 'bash -s' < tools/deploy-web.sh
```

**Se exporta EN el servidor**, no aquí, y por una razón práctica: el paquete pesa unos 120 MB
(82 de `.pck` y 39 de `.wasm`) y subirlo desde una conexión doméstica se atasca. Allí el export
tarda un minuto y no hay subida. Godot 4.7.1 y sus plantillas ya están instalados en `/opt/godot`
—la misma versión que en desarrollo— porque el prototipo hace lo mismo.

Dos detalles del guion que parecen manías y no lo son:

- **Importa antes de exportar.** Los `.import` no están en git; sin ese paso, cada PNG sale como
  marcador de posición y el juego se publica lleno de cuadros rosas.
- **El `.pck` se copia aparte y se renombra.** `mv` en el mismo sistema de ficheros es atómico, así
  que nadie se descarga un archivo a medias mientras se publica.

### A dónde apunta el cliente

`api_base` sale de `project.godot`, sección `[mexorbit]`, usando la **anulación por *feature*** de
Godot: la clave `api_base.web` gana en una exportación Web y la de escritorio se queda con la de
arriba. Sin un `if` en el código y sin tocar nada al exportar.

```
api_base="http://127.0.0.1:5100"
api_base.web="https://astrion.turname.mx/api"
```

Apunta al **mismo origen que el juego**, no al subdominio `astrion-api`: la API no tiene CORS
configurado y el navegador bloquearía la llamada entre dominios. Un `--api=…` por línea de comandos
pisa las dos, que sirve para apuntar un cliente de escritorio a producción sin reexportar.

Antes esto era una constante escrita a mano con `127.0.0.1`, que en el navegador de un tester apunta
a **su** máquina. Es el tipo de fallo que en desarrollo es invisible por definición.

La URL del game server no se configura aquí: la manda la API en el login, y en el salto de sector la
manda el propio servidor desde `map_server`.

### Que las credenciales no viajen dentro

`dev_login.cfg` lleva credenciales reales y este paquete **se reparte**. Hay tres cierres para el
mismo riesgo: está en `.gitignore` (no llega ni al clon del servidor), el preset lo excluye, y el
guion aborta si encuentra rastro suyo dentro del `.pck`.

Tres y no uno porque el guardián ya falló una vez: comprobaba con `strings`, que no está instalado
en el servidor, y al ir dentro de un `if` el fallo del comando se leyó como «no encontrado, todo
bien» — se saltó solo y el paquete se publicó sin que nadie lo revisara. Ahora usa `grep -a` y
comprueba que existe antes de confiar en él. **Un guardián que puede desaparecer en silencio es peor
que no tener guardián, porque da confianza.**

## Brazos radiales (el Vorax)

No son la cola con otro nombre. La cola es una **cadena** —cada hueso cuelga del anterior y la onda
viaja a lo largo— y esto es un **anillo** de huesos hermanos colgados de la raíz. El desfase va por
índice de brazo, así que la onda recorre el bicho girando alrededor del centro; mover los ocho a la
vez se leería como que respira, no como que se mueve.

Los brazos se **cuentan del esqueleto**, no del JSON: el JSON dice cómo se mueven, no cuántos son. Si
el modelo se rehace con otro número de tentáculos, el cliente se entera solo.

| dial | valor | de dónde sale |
|---|---|---|
| `eje` | **2** | el único que gira el brazo *dentro* del plano del disco, o sea el que barre la silueta. Medido con `repro_eje_hueso`: 1,02 de diferencia contra 0,79 del eje 0 y 0,83 del 1 — los otros lo inclinan hacia la cámara y desde arriba casi no se ven |
| `grados` | **16** | acotado por los VECINOS, no por lo que se lea. Los brazos más juntos están a 18-20° uno de otro, así que un barrido grande los cruza. A 205 px la silueta cambia un 8,0% con 18° y un 10,6% con 45°: rendimientos decrecientes justo donde empieza el riesgo |
| `desfase` | 1/n | la onda da una vuelta entera al anillo |

### Los tentáculos no se movían, y la foto decía que sí

Los `brazo_*` **nunca llegaron al cliente**: `_mapear_huesos` recorría una lista fija de nombres
—alas, cuernos y `cola_1..3`— así que `_poner_hueso` salía por la puerta de atrás en cada fotograma.
Ahora se mapea lo que el **esqueleto** trae, que además hace que un hueso nuevo funcione sin tocar el
cliente.

Lo que hace este fallo peligroso es su síntoma: **un bicho quieto se ve exactamente igual que un
bicho bien animado con amplitud pequeña**, y en un bicho radial la pose de reposo tampoco delata
nada. La captura del bestiario salía perfecta.

Por eso el bestiario ahora **afirma el movimiento**. Ya tomaba dos fotogramas —su comentario decía
que una foto fija no demuestra que algo se mueva— pero solo los guardaba: comparar quedaba para el
ojo de quien los mirase, y nadie mira nueve pares de PNG uno por uno. Ahora mide la diferencia entre
los dos dentro de la caja del bicho (no en la pantalla entera: el campo de estrellas tiene paralaje y
se mueve solo) y reporta la lista de **quietos**.

Medido en las nueve: `vex 0,515 · ferox 0,127 · skarnox 0,110 · vorax 0,097 · gravon 0,083 ·
gravit 0,085 · mordax 0,055 · vexor 0,036 · skarn 0,034`. Se reporta y no se falla porque el umbral
bueno para las nueve aún no está medido; lo que no puede volver a pasar es que nadie se entere.

**Y `repro_eje_hueso` guardaba PNG negros diciendo «guardado».** Prefijaba `npcs/` siempre, así que
`--modelo=npcs/vorax.glb` daba `assets/npcs/npcs/vorax.glb`, el modelo no cargaba y la escena seguía
adelante. Cuatro renders vacíos que se analizan como si fueran un resultado son peor que un error.
Ahora comprueba que el recurso existe y aborta, y el encuadre se **mide** del modelo en vez de una
constante heredada de otro bicho.

## La estación como malla 3D

Tercer camino de la estación, además del atlas y el PNG fijo: si su ficha declara `modelo`, en ALTA
es una **malla en su propio viewport** cuya textura alimenta el mismo `Sprite2D` de siempre — igual
que los bichos, y por lo mismo: el 3D entra por debajo y la posición, el z-index y el anillo de zona
segura siguen siendo los de 2D.

**Aquí gana más que en un bicho.** La estación se dibuja a 820 px y su atlas tenía celda de 632, o
sea que se **ampliaba 1,3 veces** — el problema de nitidez que ya costó una ronda entera. Un modelo
no tiene resolución. Y se ahorran los **40 MB** del atlas, que era el asset más caro del juego con
diferencia.

**Cámara OBLICUA** (`EST_ELEVACION`, 30°), y es el único asset del juego que no se mira desde arriba.
Es dirección de arte, no descuido: la estación es una **torre**, y una torre vista en cenital es un
punto. El resto del juego sigue siendo cenital.

Bajar la cámara obliga a cambiar el encuadre con ella. `extension_3d` mide la **huella** (X y Z), que
a 90° es exactamente lo que se ve; en cuanto la cámara baja deja de serlo, porque la altura pasa a
proyectarse sobre la pantalla y una torre de 1,92 sobre una planta de 1,05 se sale por arriba. Por
eso la estación encuadra con `extension_vista`, que **proyecta las ocho esquinas de la caja al espacio
de la cámara** y toma el lado mayor: exacto y sin casos especiales.

El viewport es grande, pero es **uno solo**: no hay treinta estaciones en pantalla como puede haber
treinta bichos, así que el coste que en un bicho obliga a medir aquí se paga sin discusión.

### El tamaño tiene dos techos, y ninguno es el gusto

`world_size` está en **2460** (tres veces el original de 820), y lo que acota cuánto más puede crecer
no es cómo se ve:

- **Su propia zona segura.** El server manda `secure_range` 1500, o sea 3000 de diámetro. A ×3 la
  estación cabe justa dentro de su anillo; a ×4 (3280) **asomaría fuera**, y una base que se sale de
  su propia zona segura se lee como un error del juego.
- **El destino de render crece con el CUADRADO.** A ×3 son 2829 px de lado y 30,5 MB — vuelve a ser
  el asset más caro del juego, ahora en render target en vez de en atlas. A ×4 serían 54,2 MB.

El lado del viewport sale de `world_size × EST_MARGEN`, y esa cifra está bien pensada para el zoom
máximo: a `ZOOM_MAX` la estación ocupa 2846 px de pantalla, así que 2829 no sobra. Al zoom por
defecto sí sobremuestrea, que es lo que la mantiene nítida al acercarse.

### El aro cian que no era del modelo

La estación apareció con un anillo cian resplandeciente que no está en su malla. **Era
`station-emissive.png` —el reactor REDONDO de la estación vieja— montado en blend aditivo y estirado
sobre el modelo nuevo.**

Ese mismo fallo ya se había arreglado una vez, cuando la estación pasó a atlas, y el guardián que se
puso decía «solo si no hay atlas» (`_estacion_anim_total == 0`). Al añadir el **tercer** camino no se
actualizó, así que volvió idéntico. Y engaña igual que la primera vez: se lee como «el reactor brilla
demasiado» cuando no es el reactor, es otra estación encima.

La regla, escrita para que el cuarto camino no lo repita: **la capa emisiva 2D pertenece al PNG fijo**,
no «a todo lo que no sea atlas». Un guardián enunciado por exclusión caduca cada vez que aparece un
caso nuevo.

### La receta del mundo 3D vive en un solo sitio

`AssetDefs.mundo_3d()` monta el viewport, el entorno, la luz del mundo y la cámara. Está ahí porque
ya son **dos** los sitios que lo necesitan —`EntityNode` y la estación— y esa receta tiene demasiadas
trampas para tenerla escrita dos veces: el mundo 3D propio, el borrado explícito del destino, el
glow atado al nivel `emissive`, la luz compartida. Cada línea está puesta por un fallo que ya
ocurrió, y una copia que se quede atrás los repite todos.

Con ella salieron también `extension_3d()` y `materiales_3d()`. La primera **acumula la
transformación a mano** hasta la raíz: `global_transform` no vale porque esto corre antes de que el
nodo entre en el árbol, y usarlo devuelve la identidad soltando un error por consola que **no detiene
nada** — el encuadre sale mal y el juego sigue. Se cayó en esa trampa al extraerla, con el comentario
que la avisa dos líneas más arriba.

### La luz del mundo es la del legacy (puerto de ago-2026)

Los valores de iluminación salen del cliente Flash decompilado de DarkOrbit, leídos de su
`LightsManager` y su `Settings3D`. El mundo tiene **un sol direccional** y **una luz de héroe**, más el
ambiente de relleno, y todo vive en el dial único de `AssetDefs`:

| dial | valor | origen legacy |
|---|---|---|
| `LUZ_MUNDO_COLOR` | cian `#A3FFFF` | color del sol (0xA3FFFF) |
| `LUZ_MUNDO_ENERGIA` | 0.8 | diffuse del sol |
| `LUZ_MUNDO_ELEVACION` | −54° | tilt=100 (~54° bajo la horizontal) |
| `LUZ_MUNDO_GRADOS` | 315° (**sin portar**) | ver abajo |
| `LUZ_MUNDO_AMBIENTE_COLOR` | naranja cálido `#FF855C` | ambientColor del sol |
| `LUZ_MUNDO_AMBIENTE` | 0.5 | ambient del sol |
| `LUZ_HEROE_COLOR` / `_ENERGIA` | azul `#2E7DFF` / 0.6 | luz de héroe (point) |

Antes el sol era blanco a 1.0 y el ambiente azul frío a 0.65. El original hace lo contrario —**key
cian frío + relleno naranja cálido**— y se adopta su criterio: es la mitad del contraste que le da a
DarkOrbit su carácter. Se conserva el tonemap FILMIC (es de Godot, no del legacy).

**El azimut no se porta a propósito.** `LUZ_MUNDO_GRADOS` lo comparte el relieve 2D (`luz_mundo()`), y
el pan del legacy es un azimut de mundo 3D en un juego cenital, sin mapeo limpio a los grados de
pantalla del shader. Cambiarlo desincronizaría la luz de los assets 2D respecto a los bichos 3D — dos
recortes pegados con la luz viniendo de sitios distintos. La elevación (el tilt) sí porta porque es
3D pura. Si algún día se quiere rotar, se rota ahí y arrastra a los dos mundos a la vez.

**La luz de héroe no derrama.** En el original bañaba a las entidades cercanas con radio 450 unidades
de mundo. Aquí cada entidad se renderiza en su `SubViewport` aislado (`own_world_3d`), así que solo
puede iluminar la malla del propio héroe: es un **rim azul de identidad sobre tu nave**, no un foco
sobre los vecinos. El radio 450 no porta (esas unidades no existen en el viewport del modelo); se
dimensiona contra `extension_3d()`.

**El sol se centralizó en `AssetDefs.sol_mundo()`**, hermano de `ambiente_mundo()`. El ambiente ya
estaba en un sitio, pero el sol estaba copiado suelto en el juego y en cada rig de `pruebas/` con
energía 1.0 y sin color. Eso convertía el puerto en una trampa: `medir_emision` habría homologado
media contra un «alta» con sol blanco que el juego ya no renderiza. Ahora todos tiran del helper —el
`banco_3d` no, a propósito: tiene sus valores de perf (sol 2.6) y no es la referencia de aspecto.

**El precio, que va en este mismo trabajo:** cambiar el sol y el ambiente **descalibra el horneado de
media** de todos los bichos y la estación. `HORNO_SOL`/`HORNO_AMBIENTE` de cada asset se re-derivan y
media se rehornea y se re-homologa con `medir_emision` — no se deja a ojo. Hasta que eso pase, «alta»
se ve con la luz nueva y «media» con la vieja: los dos caminos **no homologan**.
