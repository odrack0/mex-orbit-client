# Banco de pruebas 3D

Exploración: **¿cuántos bichos vivos aguanta el cliente?** No es el juego, es la
pregunta que decide si el pipeline de modelo único entra o no.

```bash
# escritorio (Forward+)
Godot --path . pruebas/banco_3d.tscn -- --n=50 --elev=70

# el mismo renderizador que usa el navegador
Godot --path . --rendering-method gl_compatibility pruebas/banco_3d.tscn -- --n=50
```

Argumentos: `--n=` bichos, `--elev=` grados de cámara, `--shot=` ruta de captura,
`--segundos=` cuánto mide antes de cerrarse (**0 = no se cierra**, el modo
«mirarlo» en vez de «medirlo»), `--calentamiento=` segundos que no cuentan al
principio.

## Por qué vive aquí y no en `mex-orbit-testing`

Es una escena de Godot, y un banco de rendimiento **solo significa algo dentro del
proyecto cuyos ajustes mide**: renderizador, import de texturas, MSAA,
`project.godot`. Montarlo en otro repo sería medir otro juego. Es el mismo motivo
por el que el autotest del loop vive en `game/world.gd` y no fuera.

## Medido (27-ago-2026)

**Sobre gráficos integrados**: Ryzen 7 5700G con Radeon Graphics, 512 MB de VRAM
asignada, sin GPU dedicada. No es una máquina que infle el resultado — es
aproximadamente el equipo con el que un jugador va a abrir el juego.

Vexor a 15 000 tris, texturas de 512, una luz direccional, sin sombras.
**150 bichos, 2,25 M de triángulos, 45 s por pasada, sin calentamiento** para no
esconder el arranque.

| | media | 1% peor | peor fotograma | tirones >33 ms |
|---|---|---|---|---|
| **Compatibility** (el de web) | **190,6** | **119,8** | 15,7 fps en t=0,1 s | 1, en el arranque |
| Forward+ (Vulkan) | 140,9 | 88,0 | 12,6 fps en t=0,1 s | 2, en el arranque |

**Compatibility gana en las dos cifras** —35% más de media y 36% más de suelo— y
no es error de medida: la escena es trivial (una luz, sin sombras) y ahí el
pipeline simple gana. Importa porque Compatibility es lo que corre en navegador.

**Y las dos son igual de regulares.** Compatibility cae un 37% de la media al 1%
peor y Vulkan un 38%: la misma dispersión. Hubo una lectura intermedia que decía
lo contrario —«más rápido pero más irregular»— y salía de comparar una pasada
larga contra una corta, que no es comparación.

**Los tirones son de arranque, no de régimen.** Las dos tienen su peor fotograma
en t=0,1 s, el primero medido, y **cero tirones pasados los primeros 10 s** en 45
segundos. Por eso el banco reporta *cuándo* fue el peor y cuántos tirones cayeron
antes y después de esa marca: sin esa separación, un parón de compilación de
shaders se lee como un problema del juego. Si algún día molesta, tiene solución
conocida (precompilar shaders); no es un límite de esta ruta.

Con 150 bichos vivos sobre gráficos integrados el suelo está en 120 fps, y eso es
cinco veces el bestiario del mapa 1-1 (15 Vex, 3 Gravon, 2 Skarnox). El
renderizador no es el cuello de botella, y sobre una gráfica dedicada el margen
solo puede ser mayor. Lo que esto no cubre sigue siendo el navegador, que añade
WASM y un solo hilo por encima del mismo renderizador — pero la pregunta ya no es
«¿aguanta el 3D?» sino «¿cuánto se lleva el navegador de un margen de 120 fps?».

## Lo que cuesta animar

Mismo Vexor con alas plegables (clave de forma, 26 fotogramas, un ciclo).

| bichos | quietos | aleteando | coste |
|---|---|---|---|
| **20** | 276 · suelo 152 | 228 · **suelo 109** | 17% |
| **30** | 272 · suelo 151 | 212 · **suelo 109** | 22% |
| 150 | 190 · suelo 121 | 114 · suelo 41 | 40% |

El mapa 1-1 tiene ~20 bichos (15 Vex, 3 Gravon, 2 Skarnox). **A esa población la
animación cuesta un 17% y el suelo se queda en 109 fps.** El desplome solo aparece
a 150, cinco veces la población real.

### Y el coste NO es reproducir la animación

Tres pasadas a 150 con el mismo GLB animado:

| | media | 1% peor |
|---|---|---|
| sin reproducir nada | 113,2 | 64,2 |
| con `AnimationPlayer` | 113,6 | 41,3 |
| escribiendo el valor desde `_process` | 58,6 | 28,0 |

**El mero hecho de que la malla tenga clave de forma cuesta el 41%**, antes de
mover nada: 190 fps con el GLB estático contra 113 con el animado en reposo. El
`AnimationPlayer` no cuesta casi nada de media, y escribir el valor a mano —que
parecía lo barato, y es lo que el cliente hace con `undulate` y el pulso— sale el
doble de caro.

Las dos hipótesis intuitivas eran falsas. Si alguna vez hacen falta 150 bichos
animados a la vez, lo que hay que cambiar es la técnica —esqueleto en vez de morph
target, unas matrices en vez de deltas por vértice— no el driver.

## Tres diales que invalidan la medida si se tocan

Cada uno costó una pasada mal leída.

- **El vsync se apaga a mano** (`window_set_vsync_mode` + `Engine.max_fps = 0`).
  Con vsync el contador se pega a la frecuencia del monitor y «60 fps» solo
  significa «no bajo de 60» — la primera pasada midió 57 y no medía nada.
- **Se mide el tiempo de fotograma, no el contador de Godot.**
  `get_frames_per_second()` es una media móvil y esconde justo lo que interesa.
- **El mínimo absoluto no es una estadística y no se compara jamás.** Es «lo peor
  que he visto», así que solo empeora cuanto más miras: la misma escena dio
  mínimo 88,8 fps en 8 segundos y 38 dejando la ventana abierta unos minutos, sin
  que el juego fuera a peor. La cifra comparable es el **1% peor**, que converge.
  El mínimo se sigue mostrando, pero con su instante al lado (`t=`) para que se
  lea como lo que es.

## Lo que este banco NO mide

- **Los fps en navegador.** El build web arranca y carga la escena 3D
  —confirmado: `OpenGL ES 3.0 (WebGL 2.0) - Compatibility`, single-threaded— pero
  medirlo pide abrir la página y mirar. Lo que sí está medido es el peso: el
  `.wasm` son 9,6 MB con gzip **y es el mismo tengas 2D o 3D**, porque la
  plantilla web de Godot incluye 3D siempre. Activar 3D cuesta cero de descarga,
  y el GLB (0,8 MB) pesa catorce veces menos que el atlas del mismo bicho
  (11,7 MB).
- **Cómo se ve.** El modelo está bien; el aspecto lo pone la luz de la escena, y
  la de aquí es de primera pasada y sale más lavada que el render de Blender. Eso
  es el coste conocido de esta ruta: el control artístico se mueve de curar
  imágenes a afinar iluminación.
- **La animación.** El Vexor está quieto: Meshy da malla estática.

## De dónde sale `vexor.glb`

Se genera, no se edita. La fuente vive en `mex-orbit-art/source/3d-models/`:

```bash
blender --background --factory-startup --python tools/normalize-model.py -- \
    source/3d-models/vexor.glb <cliente>/pruebas/vexor.glb 15000 512 r
```
