// El DOSkybox del original, TAL CUAL su pase AGAL decompilado:
//   t   = segundos / 120                       (timeScale 120)
//   m1  = mask(uv + (2t,    t + 1))            repeat
//   m2  = mask(uv + (-1.5t, t + 0.3))          repeat
//   col = m1 * m2 * stars(uv)                  stars con CLAMP
// sobre la malla skybox_geometry escalada x10000 que sigue a la camara.
// El titileo nace del producto de las dos mascaras moviles; las estrellas
// finas son textura, no procedurales. Sin niebla ni tinte: el cielo del DO
// es negro con este velo de estrellas.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D estrellas: source_color, filter_linear, repeat_disable;
uniform sampler2D mascara: source_color, filter_linear, repeat_enable;

void fragment() {
	float t = TIME / 120.0;
	vec3 m1 = texture(mascara, UV + vec2(2.0 * t, t + 1.0)).rgb;
	vec3 m2 = texture(mascara, UV + vec2(-1.5 * t, t + 0.3)).rgb;
	ALBEDO = m1 * m2 * texture(estrellas, UV).rgb;
	// ALPHA 1.0 explicito: fuerza el pase de transparencias, donde la
	// prioridad -10 lo pinta antes que planeta/techo/tiles
	ALPHA = 1.0;
}
