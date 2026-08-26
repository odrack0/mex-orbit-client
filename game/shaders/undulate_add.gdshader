// Capa emisiva de la criatura. Comparte la ondulación del cuerpo y el giro de
// anillos (mismo include) y suma lo suyo, que solo tiene sentido sobre lo que
// brilla — el casco no digiere ni arde:
//
//   · PERISTALSIS: una onda de luz que recorre el interior. Longitudinal
//     (cabeza→cola, el Vorax) o RADIAL (del núcleo hacia fuera, las rocas).
//   · PARPADEO: ruido que hace temblar el brillo. El magma no late limpio como
//     un reactor; arde desigual.
shader_type canvas_item;
render_mode blend_add;

#include "res://game/shaders/undulate.gdshaderinc"

uniform float peri_amount = 0.0;    // 0 = sin peristalsis; cuánto sube el brillo en el bulto
uniform float peri_frequency = 2.0; // bultos a lo largo del recorrido
uniform float peri_speed = 2.5;
uniform float peri_sharpness = 3.0; // 1 = onda suave · 3+ = bulto marcado con valles largos
uniform float peri_radial = 0.0;    // 0 = a lo largo del cuerpo · 1 = del centro hacia fuera

uniform float flicker_amount = 0.0; // 0 = sin parpadeo
uniform float flicker_scale = 6.0;  // tamaño del grano: bajo = manchas grandes
uniform float flicker_speed = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Ruido de valor con interpolación suave. Barato y de sobra para una brasa:
// no hace falta Perlin para que una grieta tiemble.
float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Onda de luz. En modo longitudinal BAJA por el cuerpo — el signo menos delante
// de TIME la manda de la boca a la cola, que es la direccion en la que se traga.
// En modo radial SALE del centro, que es como irradia un nucleo fundido.
// Nunca baja del brillo base: es un bulto que pasa, no un parpadeo.
float peristalsis(vec2 uv) {
	if (peri_amount <= 0.0) {
		return 1.0;
	}
	float eje = peri_radial > 0.5 ? length(uv - vec2(0.5)) * 2.0 : uv.y;
	float w = 0.5 + 0.5 * sin(eje * peri_frequency * TAU_ - TIME * peri_speed + phase);
	return 1.0 + peri_amount * pow(w, peri_sharpness);
}

float parpadeo(vec2 uv) {
	if (flicker_amount <= 0.0) {
		return 1.0;
	}
	vec2 p = uv * flicker_scale + vec2(TIME * flicker_speed, TIME * flicker_speed * 0.7) + phase;
	return 1.0 + flicker_amount * (ruido(p) - 0.5) * 2.0;
}

void vertex() {
	v_modulate = COLOR;   // en vertex(), COLOR ES el modulate del nodo
}

void fragment() {
	COLOR = muestrear(TEXTURE, girar_anillos(undular(UV)));
	COLOR.rgb *= peristalsis(UV) * parpadeo(UV);
}
