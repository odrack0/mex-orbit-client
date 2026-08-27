# Banco de pruebas 3D

Exploración: **¿cuántos bichos vivos aguanta el cliente?** No es el juego, es la
pregunta que decide si el pipeline de modelo único entra o no.

```bash
# escritorio (Forward+)
Godot --path . pruebas/banco_3d.tscn -- --n=50 --elev=70

# el mismo renderizador que usa el navegador
Godot --path . --rendering-method gl_compatibility pruebas/banco_3d.tscn -- --n=50
```

Argumentos: `--n=` bichos, `--elev=` grados de cámara, `--shot=` ruta de captura.

## Por qué vive aquí y no en `mex-orbit-testing`

Es una escena de Godot, y un banco de rendimiento **solo significa algo dentro del
proyecto cuyos ajustes mide**: renderizador, import de texturas, MSAA,
`project.godot`. Montarlo en otro repo sería medir otro juego. Es el mismo motivo
por el que el autotest del loop vive en `game/world.gd` y no fuera.

## Medido (27-ago-2026, máquina de desarrollo)

Vexor a 15 000 tris, texturas de 512, una luz direccional, sin sombras.

| bichos | Forward+ | Compatibility (el de web) |
|---|---|---|
| 15 | 161 fps · mín 92 | **217** · mín 102 |
| 50 | 142 · mín 73 | 214 · mín 171 |
| 150 | 111 · mín 70 | **149** · mín 116 |

**Compatibility sale más rápido que Forward+**, y no es un error de medida: la
escena es trivial —una luz, sin sombras— y ahí el pipeline simple gana. Importa
porque Compatibility es lo que corre en navegador.

150 bichos vivos son 2,25 M de triángulos en pantalla. El renderizador no es el
cuello de botella. **Ojo: es una máquina de desarrollo y no dice nada del portátil
de un jugador.**

## Dos diales que invalidan la medida si se tocan

- **El vsync se apaga a mano** (`window_set_vsync_mode` + `Engine.max_fps = 0`).
  Con vsync el contador se pega a la frecuencia del monitor y «60 fps» solo
  significa «no bajo de 60» — la primera pasada midió 57 y no medía nada.
- **Se mide el tiempo de fotograma, no el contador de Godot.**
  `get_frames_per_second()` es una media móvil y esconde justo lo que interesa,
  que es el peor fotograma. Los dos primeros segundos no cuentan: shaders y
  texturas se están calentando.

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
