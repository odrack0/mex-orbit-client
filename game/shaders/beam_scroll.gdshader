// El haz del cliente 3D original (G§9.4): textura PATRON en repeat que fluye a
// lo largo del beam via scroll de UV. Aditivo y sin luz — los FX luminosos
// SUMAN (la ley del 95%). `intensidad` es la rampa de aparicion/apagado.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled;

uniform sampler2D patron: repeat_enable, filter_linear;
uniform vec4 color: source_color = vec4(1.0);
uniform float repeticiones = 4.0;   // cuantas veces cabe el patron a lo largo
uniform float ciclo = 0.4;          // segundos por repeticion (0.3-0.5 en el original)
uniform float intensidad = 1.0;

void fragment() {
	vec2 uv = vec2(UV.x * repeticiones - TIME / ciclo, UV.y);
	vec4 t = texture(patron, uv);
	ALBEDO = t.rgb * color.rgb * intensidad;
	ALPHA = t.a * color.a * intensidad;
}
