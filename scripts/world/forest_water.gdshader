// © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
// Agua del bosque (ForestKit): la máscara es una rampa continua (0,5 = orilla) con filtro lineal, así la orilla es
// curva y nítida (nada de escalera). Hondura según la rampa (más oscura adentro), bajío claro junto a la orilla,
// línea de espuma fina que late, reflejo oscuro y ondulado de la orilla norte (los árboles de arriba se reflejan),
// ondas leves y destellos contados. Con lluvia, anillos.
shader_type canvas_item;

uniform sampler2D fill_tex : repeat_enable, filter_nearest;
uniform vec2 world_px = vec2(512.0, 512.0);   // px de mundo que cubre el sprite
uniform float tex_px = 180.0;
uniform vec2 flow = vec2(0.02, 0.006);
uniform float wave = 0.6;
uniform float sparkle = 0.6;
uniform float rain = 0.0;
uniform vec3 deep = vec3(0.07, 0.2, 0.22);
uniform vec3 shallow = vec3(0.3, 0.46, 0.4);
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform float refl_px = 40.0;     // alto (px de mundo) de la franja que refleja la orilla norte
uniform float depth_k = 3.0;      // qué tan rápido se hace hondo (rampa -> hondura)
uniform float edge_light = 0.45;

varying vec2 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float m = texture(TEXTURE, UV).r;
	// COLOR de entrada = modulate x textura (la máscara): se recupera el modulate (tinte nocturno) dividiendo
	vec4 mod = vec4(COLOR.rgb / max(vec3(m), vec3(0.002)), COLOR.a);
	float a = smoothstep(0.492, 0.512, m);
	vec2 wp = UV * world_px;
	float depth = clamp((m - 0.5) * depth_k, 0.0, 1.0);
	vec2 wob = vec2(sin(wp.y * 0.09 + TIME * 1.3), cos(wp.x * 0.07 + TIME * 1.1)) * 0.012 * wave;
	vec3 t1 = texture(fill_tex, wp / tex_px + flow * TIME + wob).rgb;
	vec3 t2 = texture(fill_tex, wp / tex_px * 1.7 + vec2(0.37, 0.11) - flow * TIME * 0.6 + wob.yx).rgb;
	vec3 tx = mix(t1, t2, 0.45);
	float lum = dot(tx, vec3(0.3, 0.5, 0.2));
	vec3 base = mix(shallow, deep, smoothstep(0.0, 0.85, depth));
	vec3 c = base * (0.7 + 0.75 * lum);
	// reflejo de la orilla norte: a refl_px más arriba ya hay tierra -> franja oscura verdosa que ondula
	float rx = sin(wp.y * 0.21 + TIME * 1.6) * 3.0 * wave;
	float up = texture(TEXTURE, UV + vec2(rx / world_px.x, -refl_px / world_px.y)).r;
	float refl = 1.0 - smoothstep(0.44, 0.56, up);
	c = mix(c, c * vec3(0.42, 0.58, 0.46), refl * 0.7);
	// bajío y espuma en la orilla
	float edge = 1.0 - smoothstep(0.5, 0.57, m);
	float foam = edge * (0.5 + 0.5 * sin(TIME * 2.1 + wpos.x * 0.08 + wpos.y * 0.12));
	c = mix(c, vec3(0.72, 0.82, 0.76), foam * edge_light);
	// destellos: pocos, titilan a ritmos distintos
	vec2 g = (wp + vec2(TIME * 5.0, 0.0)) / 7.0;
	vec2 cell = floor(g);
	float h = hash12(cell);
	float tw = pow(max(0.0, sin(TIME * 2.4 + h * 6.2831)), 16.0) * step(0.955, h) * (1.0 - refl);
	c += tw * sparkle * 0.55 * (1.0 - smoothstep(0.1, 0.38, length(fract(g) - 0.5)));
	if (rain > 0.0) {
		for (int k = 0; k < 2; k++) {
			vec2 rc = floor((wpos + float(k) * 13.0) / 30.0);
			float rh = hash12(rc + 11.0 + float(k));
			float ph = fract(TIME * 1.1 + rh * 7.0);
			vec2 center = (rc + 0.5 + (vec2(hash12(rc + 3.0), hash12(rc + 5.0)) - 0.5) * 0.7) * 30.0 - float(k) * 13.0;
			float r = length((wpos - center) * vec2(1.0, 1.6));
			float ring = smoothstep(1.6, 0.0, abs(r - ph * 13.0)) * (1.0 - ph) * step(rh, rain * 0.85);
			c += ring * 0.4;
		}
	}
	COLOR = vec4(c * tint * mod.rgb, a * mod.a);
}
