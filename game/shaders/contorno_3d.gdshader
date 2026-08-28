// RESPLANDOR DE CONTORNO para una malla 3D: un termino FRESNEL que enciende la
// superficie segun se aleja de mirar a la camara. En el centro de una cara la
// normal apunta al ojo y no aporta nada; en el borde, donde la superficie se
// va de canto, aporta todo. Eso dibuja el contorno de CADA tubo y cada brazo,
// no una aureola alrededor de la silueta entera.
//
// Va como `next_pass` del material que ya tiene el modelo, y esa es la parte
// barata: no es otro viewport ni otro destino de render, es una segunda pasada
// de la MISMA geometria dentro de un viewport que ya se estaba dibujando. Y el
// material original no se toca, asi que sus texturas siguen mandando.
//
// La alternativa era un contorno en 2D sobre el sprite: desenfocar el alfa del
// viewport para sacar una aureola. Se descarto por coste — la estacion se dibuja
// a mas de mil quinientos pixeles de lado, y un desenfoque de varias muestras
// sobre esa area, cada fotograma, cuesta mucho mas que redibujar la malla.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.66, 0.30, 0.95);
uniform float fuerza = 1.0;
uniform float dureza = 2.5;   // mas alto = borde mas fino

void fragment() {
	// 1 - N·V: cero mirando de frente, uno de canto.
	float borde = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = color * pow(borde, dureza) * fuerza;
	ALPHA = 1.0;
}
