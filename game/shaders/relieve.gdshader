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
uniform float contraste = 0.90;       // cuanto separa la cara clara de la oscura
uniform float especular = 0.30;       // el brillo que barre; es lo que se nota al virar
uniform float dureza = 24.0;          // mas alto = reflejo mas concentrado
uniform float emisivo_min = 0.55;     // a partir de aqui un pixel se considera luz propia
uniform float emisivo_max = 0.85;     // y aqui, luz propia del todo

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

	// La luz va CENTRADA EN UNO, no sumando ambiente y difusa. La primera version
	// hacia `ambiente + difusa * lam`, y con un lambert medio de 0,47 eso deja el
	// asset mas oscuro de lo que venia, siempre. En un bicho de metal apenas se
	// notaba; en una caja con tubos de neon y en un portal de plasma, se veia.
	// Asi, lam = 0,5 no cambia nada y los dos lados se reparten alrededor: da
	// forma sin poder apagar la pieza en conjunto.
	vec3 rgb = base.rgb * (1.0 + contraste * (lam - 0.5)) + vec3(especular * brillo);

	// Y lo que tiene LUZ PROPIA no se ilumina. Un tubo de neon o el plasma de un
	// portal no se apagan porque la luz venga del otro lado; ahi el sombreado no
	// es forma, es un error. Se detecta por el canal mas alto, que es lo que
	// separa un emisivo saturado de un metal claro.
	float e = smoothstep(emisivo_min, emisivo_max, max(base.r, max(base.g, base.b)));
	COLOR = vec4(mix(rgb, base.rgb, e), base.a);
}
