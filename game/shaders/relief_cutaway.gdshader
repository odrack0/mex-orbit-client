// Material del RELIEVE (game/relief3d.gd): roca opaca iluminada por la luz del
// mundo, con un RECORTE alrededor de la linea camara -> heroe.
//
// El terreno con volumen sube por encima del plano del juego, asi que una pared
// del lado del espectador tapa la nave. En vez de transparentar la roca entera
// (cambia el orden de pintado y se ve fantasma) se descartan solo los pixeles
// que caen dentro de un cilindro alrededor de la visual y por DELANTE del heroe.
// El borde va tramado (Bayer 4x4): sigue siendo un material opaco, sin orden de
// transparencias que cuidar. El mismo cilindro resuelve el caso de la camara
// metida dentro de una roca con el zoom al maximo: todo lo que queda pegado a la
// camara esta, por construccion, cerca de la visual.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.9;
// cuanto se oscurece la cara interior que el recorte deja a la vista
uniform float interior = 0.25;

uniform vec3 hero_pos = vec3(0.0);
uniform float cut_on = 0.0;
uniform float cut_radius = 170.0;
uniform float cut_feather = 70.0;
uniform float cut_margin = 40.0;

varying vec3 world_pos;


float bayer4(vec2 px) {
	const float M[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	ivec2 i = ivec2(mod(px, 4.0));
	return (M[i.y * 4 + i.x] + 0.5) / 16.0;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
			if (keep < bayer4(FRAGCOORD.xy)) {
				discard;
			}
		}
	}
	vec3 base = texture(albedo_tex, UV).rgb * tint.rgb;
	ALBEDO = FRONT_FACING ? base : base * interior;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
