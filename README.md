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

**E2/I4 en marcha**: login con la secuencia real, vuelo por el 1-1 con predicción + reconciliación, mecánica de vuelo portada fiel del prototipo (click sostenido persigue al cursor) y HUD mínimo del sistema N. Correr: `godot --path .` (requiere api en 5100 y game server en 5200; `dev_login.cfg` local precarga credenciales). Autotest: `godot --path . -- --screenshot=ruta.png`.

## Correr el cliente

```powershell
.\tools\dev-run.ps1                 # levanta lo que falte y abre el cliente
.\tools\dev-run.ps1 -SoloServicios  # deja MySQL/api/game server listos, sin cliente
.\tools\dev-run.ps1 -Autotest       # autotest headless del loop completo, con captura
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
| `data/props/<code>.json` | props del mundo (estación): textura, emisiva, tamaño en unidades de mundo, pulso |
| `data/ammo/<code>.json` | **el aspecto de cada arma**: color, largo, grosor y duración del haz, con su variante `beam_skilled` (el disparo potenciado del perfil de piloto: más grueso y brillante) |

Agregar una nave nueva = soltar su PNG + escribir su JSON. Cero código.
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

Diferencia deliberada contra el prototipo: **v1 clampea el destino a los límites del mapa** (igual que el server); el prototipo navegaba "mapa infinito" con la radiación como freno.
