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
| Llamas de motor | `entity_node.gd::_process` | subida 2.5/s, caída 3.5/s, largo 0.42 | El acelerador de las toberas y su respiración |
| `COLLECT_ARRIVE` | `game/world.gd` | 200 px | Llegar a esto de la caja dispara el CollectBox (el server valida 250) |
| Haz del láser | `game/world.gd` | ancho 3, cian | El beam héroe→objetivo mientras dispara (Ctrl lo alterna) |
| Daño flotante | `world.gd::_on_attack` | sube 46 px en 0.8 s | Los números de daño que se desvanecen |
| Explosión | `world.gd` | 16 fps, escala 1.4 | Los 8 frames del pipeline al morir una entidad |
| Pasos de zoom del minimapa | `ui/minimap_window.gd` | 180, 238, 300, 380, 460 | Anchos del canvas (los del prototipo); el alto sale del ratio del mapa |
| `AUTOPILOT_ARRIVE` | `game/world.gd` | 120 px | A esta distancia el autopiloto declara destino alcanzado |
| Escala de la estación | `world.gd::_construir_estacion` | 0.6 | El render de 1024 rinde a ~614 px en el mundo |
| Anillo de zona segura | `world.gd::_construir_estacion` | cian 22%, grosor 3 | El radio que manda el server en `EnterMap` |

Diferencia deliberada contra el prototipo: **v1 clampea el destino a los límites del mapa** (igual que el server); el prototipo navegaba "mapa infinito" con la radiación como freno.
