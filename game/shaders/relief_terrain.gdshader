// Material de la TRINCHERA (game/relief3d.gd, variante "trench"): una superficie
// continua generada desde un mapa de alturas. Tres cosas la hacen leerse como
// terreno y no como rocas sueltas:
//   - textura TRIPLANAR en coordenadas de mundo: no hay UV que estirar en las
//     paredes y la roca sigue de una celda a la siguiente sin costura;
//   - se OSCURECE con la profundidad: borde encendido, fondo apagado (no hay
//     sombras en el mundo, G§7; esto es lo que da el hueco);
//   - ESTRATOS horizontales en las caras empinadas: una direccion comun.
// Lleva el mismo recorte camara -> heroe que relief_cutaway.gdshader.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tex_scale = 700.0;
uniform float roughness = 0.95;

uniform float dark_y = -420.0;
uniform float light_y = 200.0;
uniform float dark = 0.22;
uniform float strata = 0.18;
uniform float strata_period = 46.0;
// relleno cenital: la luz del mundo llega casi horizontal (tilt 100), pensada
// para naves vistas de lado; una superficie plana mirando arriba recibe ~17 % y
// la meseta salia apagada. Es luz propia del terreno, medida por la normal.
uniform float top_fill = 0.35;
uniform vec4 wall_tint : source_color = vec4(0.62, 0.48, 0.44, 1.0);

// MAR (o lava): lo que queda plano a la cota `sea_y` se pinta de `sea_color`, liso
// y, si `sea_emission` > 0, encendido. La malla ya viene aplanada a esa cota
// (Relief3D._world_height); aqui solo se viste. Apagado por defecto.
uniform float sea_y = -100000.0;
uniform vec4 sea_color : source_color = vec4(0.1, 0.3, 0.6, 1.0);
uniform float sea_emission = 0.0;
// NIEVE (o ceniza): por encima de `snow_y`, donde no es pared.
uniform float snow_y = 100000.0;
uniform vec4 snow_color : source_color = vec4(0.95, 0.96, 0.98, 1.0);

uniform vec3 hero_pos = vec3(0.0);
uniform float cut_on = 0.0;
uniform float cut_radius = 170.0;
uniform float cut_feather = 70.0;
uniform float cut_margin = 40.0;
uniform float cut_below = 25.0;

varying vec3 world_pos;
varying vec3 world_nrm;


float bayer4(vec2 px) {
	const float M[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	ivec2 i = ivec2(mod(px, 4.0));
	return (M[i.y * 4 + i.x] + 0.5) / 16.0;
}


// dos escalas de la misma textura enlosable: la fina da grano y la gruesa rompe
// la repeticion (manchas claras y oscuras de cientos de unidades)
vec3 tex_mirror(vec2 uv) {
	vec3 fine = texture(albedo_tex, uv).rgb;
	float coarse = texture(albedo_tex, uv * 0.17 + vec2(0.37, 0.11)).r;
	return fine * (0.65 + 0.9 * coarse);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	if (cut_on > 0.5) {
		vec3 axis = hero_pos - CAMERA_POSITION_WORLD;
		float len = length(axis);
		vec3 dir = axis / max(len, 0.001);
		vec3 rel = world_pos - CAMERA_POSITION_WORLD;
		float t = dot(rel, dir);
		if (t < len - cut_margin) {
			float d = length(rel - dir * t);
			float keep = smoothstep(cut_radius, cut_radius + cut_feather, d);
			// solo lo que queda POR ENCIMA de la visual tapa a la nave. Sin esto, con
			// la camara baja el cilindro mordia el SUELO bajo la visual y abria un
			// agujero al espacio delante de la nave.
			float line_y = CAMERA_POSITION_WORLD.y + dir.y * t;
			if (world_pos.y > line_y - cut_below && keep < bayer4(FRAGCOORD.xy)) {
				discard;
			}
		}
	}
	vec3 n = normalize(world_nrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos / tex_scale;
	vec3 c = tex_mirror(p.zy) * w.x + tex_mirror(p.xz) * w.y + tex_mirror(p.xy) * w.z;
	c *= tint.rgb;

	// PARED vs SUELO: con la camara a 45 grados una pared que mira al espectador
	// se ve de frente y, sin pistas, se lee como piso. Las pistas: la cara
	// empinada es mas oscura y rojiza que lo plano, y lleva estratos marcados.
	float steep = smoothstep(0.15, 0.7, 1.0 - abs(n.y));
	float wobble = sin(world_pos.x * 0.004 + world_pos.z * 0.003) * 2.0;
	float band = 0.5 + 0.5 * sin(world_pos.y / strata_period * 6.2832 + wobble);
	band = smoothstep(0.3, 0.7, band);
	c = mix(c, c * wall_tint.rgb, steep);
	c *= 1.0 - strata * steep * band;

	float depth_k = mix(dark, 1.0, smoothstep(dark_y, light_y, world_pos.y));
	c *= depth_k;
	float snow = smoothstep(snow_y, snow_y + 140.0, world_pos.y) * smoothstep(0.3, 0.7, n.y);
	c = mix(c, snow_color.rgb, snow);
	vec3 glow = c * top_fill * max(n.y, 0.0) * depth_k;
	float rough = roughness;
	if (world_pos.y <= sea_y + 1.5 && n.y > 0.97) {
		float ripple = 0.8 + 0.4 * texture(albedo_tex, world_pos.xz / (tex_scale * 1.7)).r;
		c = sea_color.rgb * ripple;
		glow = sea_color.rgb * sea_emission * ripple;
		rough = 0.25;
	}
	ALBEDO = c;
	EMISSION = glow;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
