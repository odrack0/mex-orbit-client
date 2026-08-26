// Capa emisiva de la criatura. Comparte la ondulación del cuerpo (mismo
// include) pero suma lo suyo: la PERISTALSIS, una onda de luz que recorre el
// interior. Va aquí y no en el include porque solo tiene sentido sobre lo que
// brilla — el casco no digiere nada.
shader_type canvas_item;
render_mode blend_add;

#include "res://game/shaders/undulate.gdshaderinc"

uniform float peri_amount = 0.0;    // 0 = sin peristalsis; cuánto sube el brillo en el bulto
uniform float peri_frequency = 2.0; // bultos a lo largo del cuerpo
uniform float peri_speed = 2.5;
uniform float peri_sharpness = 3.0; // 1 = onda suave · 3+ = bulto marcado con valles largos

// Onda de luz que BAJA por el cuerpo. El signo menos delante de TIME es lo que
// la manda de la boca hacia la cola: es la direccion en la que se traga.
// Nunca baja del brillo base — es un bulto que pasa, no un parpadeo.
float peristalsis(float y) {
	if (peri_amount <= 0.0) {
		return 1.0;
	}
	float w = 0.5 + 0.5 * sin(y * peri_frequency * TAU_ - TIME * peri_speed + phase);
	return 1.0 + peri_amount * pow(w, peri_sharpness);
}

void vertex() {
	v_modulate = COLOR;   // en vertex(), COLOR ES el modulate del nodo
}

void fragment() {
	COLOR = muestrear(TEXTURE, girar_anillos(undular(UV)));
	COLOR.rgb *= peristalsis(UV.y);
}
