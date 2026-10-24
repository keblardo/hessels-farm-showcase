// © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
// Oscuridad del laberinto de Blu (Labyrinth.gd): UNA sola capa a pantalla completa que MULTIPLICA la imagen ya
// dibujada. Todo queda negro salvo el círculo de luz cálida del jugador (borde suave) y unas pocas luces locales
// (faroles, la luz del día que baja por las escaleras, el refugio) que Labyrinth solo enciende cuando el jugador
// está cerca. Va por encima de la gradación de color (capa 7) y por debajo de la interfaz (capa 10): el negro no
// se levanta de noche y el HUD y los controles táctiles quedan siempre visibles. Sin luces 2D: un solo pase.
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform vec4 player_light = vec4(480.0, 270.0, 60.0, 170.0);   // xy centro (px lógicos de pantalla), z radio pleno, w radio negro
uniform vec3 player_color = vec3(1.0, 0.86, 0.66);             // tinte del borde de la luz (el centro queda neutro)
uniform vec4 lights[8];          // xy centro, z radio, w intensidad 0..1
uniform vec4 light_colors[8];    // rgb de cada luz
uniform int light_count = 0;

varying vec2 px;

void vertex() {
	px = VERTEX;   // coordenadas locales del rectángulo = píxeles lógicos de la pantalla
}

// ruido mínimo: evita escalones en el degradé sobre negro (pantallas de 8 bits)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float d = distance(px, player_light.xy);
	float k = 1.0 - smoothstep(player_light.z, player_light.w, d);
	k = k * k * (3.0 - 2.0 * k);   // doble suavizado: el borde se funde sin anillo marcado
	// centro casi neutro (se ve el color real del suelo, apenas tibio, como un farol de mano); hacia el borde la
	// luz se vuelve cálida y se apaga
	vec3 acc = mix(player_color * k, vec3(1.0, 0.97, 0.92) * k, smoothstep(0.55, 1.0, k));
	for (int i = 0; i < 8; i++) {
		if (i >= light_count) { break; }
		vec4 L = lights[i];
		float kl = 1.0 - smoothstep(L.z * 0.2, L.z, distance(px, L.xy));
		acc += light_colors[i].rgb * (kl * kl * L.w);
	}
	acc += (hash(px) - 0.5) * 0.012 * step(0.004, max(acc.r, max(acc.g, acc.b)));
	COLOR = vec4(clamp(acc, vec3(0.0), vec3(1.0)), 1.0);
}
