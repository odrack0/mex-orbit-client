// Generado a partir de undulate.gdshaderinc: misma onda, distinto blend.
// El cuerpo va en mezcla normal y la capa emisiva en aditivo, pero AMBOS
// deben ondular igual o las visceras se quedarian rectas sobre un cuerpo
// que serpentea.
shader_type canvas_item;
render_mode blend_mix;

#include "res://game/shaders/undulate.gdshaderinc"

void vertex() {
	v_modulate = COLOR;   // en vertex(), COLOR ES el modulate del nodo
}

void fragment() {
	COLOR = muestrear(TEXTURE, girar_anillos(undular(UV)));
}
