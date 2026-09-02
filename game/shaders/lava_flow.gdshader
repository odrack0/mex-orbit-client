// Lava que VIAJA por las grietas (calidad alta, bichos 3D con `lava` en su JSON).
//
// El pulso del material sube y baja la emision ENTERA a la vez: se lee como
// respirar, no como fluir. Este pase aniade encima un brillo modulado por ruido
// que se DESPLAZA con el tiempo, asi que la claridad recorre la grieta — la
// ilusion de magma bajo la costra sin simular nada fisico.
//
// Va como `next_pass` ADITIVO sobre la copia BaseMaterial3D de la entidad: el
// mecanismo del pulso (emission_energy_multiplier) no se toca, y este pase
// recibe la MISMA intensidad por su uniform para latir en fase con el.
//
// El ruido se evalua sobre la POSICION LOCAL de la malla, no sobre el UV: los
// islotes de UV de Meshy parten el espacio de textura y el flujo saltaria en
// cada costura. En espacio local es continuo, y gira con el bicho — la lava
// pertenece a la roca, lo que viaja es la claridad.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// La emisiva del propio material (albedo x mascara del canal): el flujo solo
// enciende lo que ya emite — grietas y nucleo — y nunca la roca.
uniform sampler2D emisiva : source_color, filter_linear_mipmap;
// La escribe entity_node en cada fotograma con el MISMO valor del pulso.
uniform float intensidad = 1.0;
uniform float cantidad = 1.5;    // cuanto aniade el flujo sobre el pulso
uniform float escala = 4.0;      // tamanio de las lenguas, en unidades del modelo
uniform float velocidad = 0.25;  // que tan rapido viaja la claridad

varying vec3 pos_m;

float trocear(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Ruido de valor 3D: hash en las 8 esquinas de la celda y mezcla suave.
float ruido(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(trocear(i), trocear(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(trocear(i + vec3(0.0, 1.0, 0.0)), trocear(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(trocear(i + vec3(0.0, 0.0, 1.0)), trocear(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(trocear(i + vec3(0.0, 1.0, 1.0)), trocear(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	pos_m = VERTEX;
}

void fragment() {
	vec3 em = texture(emisiva, UV).rgb;
	float t = TIME * velocidad;
	// Dos octavas viajando en direcciones DISTINTAS: una sola se lee como que
	// la textura entera se desliza; dos que se cruzan se leen como corriente.
	float a = ruido(pos_m * escala + vec3(t, t * 0.7, -t * 0.5));
	float b = ruido(pos_m * escala * 2.3 - vec3(t * 1.3, -t, t * 0.6));
	float flujo = a * 0.65 + b * 0.35;
	// Al cuadrado: valles anchos y crestas estrechas — lenguas de claridad que
	// recorren la grieta, no un parpadeo uniforme.
	flujo = flujo * flujo;
	ALBEDO = em * intensidad * cantidad * flujo;
}
