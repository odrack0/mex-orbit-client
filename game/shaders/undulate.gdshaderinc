// Ondulación de criatura: la cola serpentea y la cabeza manda.
//
// Se hace en el FRAGMENT desplazando la UV, no en el vertex: un Sprite2D es un
// quad de cuatro vértices, así que deformar vértices daría un alabeo bilineal,
// no una onda suave a lo largo del cuerpo. Desplazando la muestra de textura
// sale la onda completa sin geometría extra.
//
// El eje del bicho es vertical (la proa mira arriba en todo el arte del juego),
// así que UV.y recorre el cuerpo de la nariz (0) a la cola (1) y el desplazamiento
// va en UV.x — vaivén lateral.

uniform float amplitude = 0.05;   // en UV: fracción del ancho de la textura
uniform float frequency = 2.0;    // ciclos de onda a lo largo del cuerpo
uniform float speed = 3.0;
uniform float from_y = 0.25;      // desde dónde empieza a doblarse (0 nariz, 1 cola)
uniform float gain = 1.0;         // 0..1, lo mueve el nodo según nade o esté quieto
uniform float phase = 0.0;        // fase por bicho: no ondulan al unísono

const float TAU_ = 6.28318530718;

// El modulate del nodo (el pulso de la capa emisiva viaja por ahí) llega como
// color de vértice. Al re-muestrear la textura por nuestra cuenta hay que
// reaplicarlo a mano, así que se guarda aquí. `MODULATE` no existe en canvas_item.
varying vec4 v_modulate;

vec2 undular(vec2 uv) {
	// peso cuadrático hacia la cola: la cabeza casi no se mueve, la punta sí
	float t = clamp((uv.y - from_y) / max(1.0 - from_y, 0.001), 0.0, 1.0);
	float w = t * t;
	float off = sin(uv.y * frequency * TAU_ + TIME * speed + phase) * amplitude * w * gain;
	return vec2(uv.x + off, uv.y);
}

uniform float ring_speed = 0.0;    // 0 = sin anillos giratorios
uniform float ring_bands = 3.0;    // en cuantas bandas de radio se parte la zona movil
uniform float ring_inner = 0.05;   // donde empiezan a girar (0 = centro)
uniform float ring_outer = 0.40;   // ...y donde dejan de girar (0.5 = borde del lienzo)
uniform float ring_falloff = 0.5;  // cuanto se frena cada banda hacia fuera

// Anillos concentricos girando a distintos ritmos, alternando el sentido.
//
// El truco es rotar la UV ALREDEDOR DEL CENTRO por bandas de radio: sobre una
// pieza concentrica, cada banda mapea anillo sobre anillo y parece girar. Por
// eso solo sirve para los bichos de metal — sobre una silueta con forma se veria
// un remolino.
//
// Y por eso la banda movil NO llega al borde: ahi viven los pernos del Gravit y
// la cabeza del Gravon, que son su identidad y su PROA. Si giraran, el bicho
// dejaria de tener frente.
vec2 girar_anillos(vec2 uv) {
	if (ring_speed <= 0.0) {
		return uv;
	}
	vec2 c = uv - vec2(0.5);
	float r = length(c);
	if (r < ring_inner || r > ring_outer) {
		return uv;
	}
	float t = (r - ring_inner) / max(ring_outer - ring_inner, 0.001);
	float banda = floor(t * ring_bands);
	float dir = (mod(banda, 2.0) < 1.0) ? 1.0 : -1.0;
	float vel = ring_speed * dir * (1.0 - ring_falloff * (banda / max(ring_bands, 1.0)));
	float a = atan(c.y, c.x) + TIME * vel;
	return vec2(cos(a), sin(a)) * r + vec2(0.5);
}

// Fuera de la textura no hay bicho: transparente, en vez de estirar el borde.
vec4 muestrear(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0) {
		return vec4(0.0);
	}
	return texture(tex, uv) * v_modulate;
}
