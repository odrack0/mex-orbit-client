// RELIEVE — reiluminar un sprite plano contra una luz fija en el MUNDO.
//
// El arte del juego es cenital y los sprites rotan, asi que su iluminacion gira
// con ellos: el brillo del casco apunta siempre al mismo sitio relativo a la
// nave, nunca al mismo sitio del mundo. El ojo lee eso como recorte de papel,
// aunque no sepa decir por que.
//
// Esto arregla eso y nada mas. NO da volumen: la silueta sigue siendo plana y no
// hay escorzo. Da relieve — al virar, el reflejo BARRE el casco, que es la mitad
// de la sensacion de 3D y la unica mitad que se puede tener sin rehacer el
// catalogo entero en atlas de rotacion.
//
// La pieza clave es `giro`. El mapa de normales vive en espacio de TEXTURA, y el
// sprite gira: si no se contrarrota la normal antes de iluminarla, la luz gira
// con la nave y no hemos hecho nada. Se pasa desde `_set_visual_angle`, que ya
// corre exactamente cuando el rumbo cambia — no hace falta tocarlo por fotograma.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D normal_map : filter_linear_mipmap, repeat_disable;
uniform float giro = 0.0;             // radianes: rotacion del sprite en el mundo
uniform vec2 luz_dir = vec2(0.7071, -0.7071);
uniform float luz_z = 0.60;           // cuanto viene la luz "de frente"; 0 = rasante
uniform float ambiente = 0.55;        // lo que se ve en la cara oscura
uniform float difusa = 0.85;
uniform float especular = 0.35;       // el brillo que barre; es lo que se nota al virar
uniform float dureza = 24.0;          // mas alto = reflejo mas concentrado

// El fragment recibe COLOR ya multiplicado por el modulate solo si no lo tocamos;
// al escribirlo entero hay que traerselo desde vertex, igual que en `undulate`.
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * v_modulate;
	vec3 n = texture(normal_map, UV).rgb * 2.0 - 1.0;

	// contrarrotacion de la normal al espacio del MUNDO
	float c = cos(-giro);
	float s = sin(-giro);
	vec3 nm = normalize(vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z));

	vec3 L = normalize(vec3(luz_dir, luz_z));
	float lam = clamp(dot(nm, L), 0.0, 1.0);
	float brillo = pow(lam, dureza);

	// el especular se suma sin teñir: un reflejo de metal es blanco
	vec3 rgb = base.rgb * (ambiente + difusa * lam) + vec3(especular * brillo);
	COLOR = vec4(rgb, base.a);
}
