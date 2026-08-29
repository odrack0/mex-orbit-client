// El CIELO del mundo (F3, G§10.3): estrellas procedurales con el TWINKLE del
// original — el brillo de cada estrella es el producto de DOS mascaras de ruido
// que se desplazan a velocidades distintas ((2,1) y (-1.5,1) sobre t/120), asi
// que el titileo nunca se repite. Mas una nebulosa tenue de baja frecuencia
// tenida con el tinte del mapa. Vive en el Sky del Environment: infinito de
// verdad, recentrado gratis.
shader_type sky;

uniform vec3 tinte: source_color = vec3(0.45, 0.75, 1.0);
uniform float densidad = 900.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void sky() {
	// proyeccion estable de la direccion de vista a un plano de cielo
	vec3 d = EYEDIR;
	vec2 uv = d.xz / (abs(d.y) + 0.35);

	// fondo: azul muy oscuro con nebulosa tenue del color del mapa
	float neb = ruido(uv * 1.3) * ruido(uv * 0.6 + 7.0);
	vec3 base = vec3(0.012, 0.016, 0.035) + tinte * neb * 0.05;

	// estrellas: una por celda que pase el umbral, con nucleo subpixel suave
	vec2 cel = uv * densidad;
	float h = hash(floor(cel));
	float estrella = step(0.995, h);
	vec2 fc = fract(cel) - 0.5;
	float nucleo = max(0.0, 1.0 - dot(fc, fc) * 8.0);

	// el twinkle del original: dos mascaras moviles multiplicadas (G§10.3)
	float t = TIME / 120.0;
	float m1 = 0.5 + 0.5 * ruido(uv * 40.0 + vec2(2.0, 1.0) * t * 60.0);
	float m2 = 0.5 + 0.5 * ruido(uv * 40.0 + vec2(-1.5, 1.0) * t * 60.0);
	float brillo = (0.4 + 1.4 * hash(floor(cel) + 3.7)) * m1 * m2;

	COLOR = base + vec3(1.0) * estrella * nucleo * brillo;
}
