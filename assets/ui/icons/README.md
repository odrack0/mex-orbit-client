# Iconos del sistema N

Reglas del §10 de `03-sistema-diseno-ui.md`, y no son negociables:

- `viewBox="0 0 24 24"`, `fill:none`, `stroke-width` 1.6–1.7, `stroke-linecap/linejoin: round`.
- Un glifo = una idea. Sin relleno ni detalle interno.
- **El trazo va en blanco (`#FFFFFF`)**, nunca en el color final. En el prototipo
  HTML el color lo pone `currentColor`; en Godot lo pone `modulate` sobre la
  textura, y para que eso funcione el icono tiene que ser blanco puro. Un icono
  ya coloreado no se puede teñir de ámbar al abrir su ventana.
- `width`/`height` a 64 aunque el `viewBox` sea de 24: es el tamaño al que Godot
  lo rasteriza. Se dibuja a 16 px, así que 64 deja margen de sobra para pantallas
  a mayor escala sin que se vea blando.

Los glifos son los mismos `<symbol>` de `prototipo-ui-n.html`; copiar el `d` de
ahí en vez de redibujarlo mantiene las dos referencias iguales.
