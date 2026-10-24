// © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
// Silueta roja de un enemigo tapado (EnemySilhouettes.gd). Se dibuja con la textura, el cuadro, el giro y la
// escala del AnimatedSprite2D del enemigo, por encima de los objetos, pero SOLO donde uno de los objetos que lo
// tapan (hasta 4) tiene píxeles opacos: fuera de ellos no pinta nada, así que la parte visible del enemigo se ve
// normal y la silueta aparece exactamente sobre el árbol / la casa / la torreta.
// Cada objeto llega como su textura y la transformación mundo -> UV (dos filas de una afín 2x3) con los límites
// de su región (AtlasTexture), calculadas en GDScript desde su global_transform.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 fill_color : source_color = vec4(0.86, 0.09, 0.07, 0.48);
uniform vec4 rim_color : source_color = vec4(1.0, 0.24, 0.18, 0.56);
uniform float rim_texels = 2.0;   // grosor del contorno en téxeles de la textura del enemigo (~1,5 px de pantalla)
uniform float fade = 1.0;
uniform int occ_count = 0;

uniform sampler2D occ_tex0 : filter_nearest;
uniform vec3 occ_u0; uniform vec3 occ_v0; uniform vec4 occ_b0;
uniform sampler2D occ_tex1 : filter_nearest;
uniform vec3 occ_u1; uniform vec3 occ_v1; uniform vec4 occ_b1;
uniform sampler2D occ_tex2 : filter_nearest;
uniform vec3 occ_u2; uniform vec3 occ_v2; uniform vec4 occ_b2;
uniform sampler2D occ_tex3 : filter_nearest;
uniform vec3 occ_u3; uniform vec3 occ_v3; uniform vec4 occ_b3;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 occ_uv(vec3 u, vec3 v) {
	vec3 w = vec3(world_pos, 1.0);
	return vec2(dot(u, w), dot(v, w));
}

float inside(vec2 uv, vec4 b) {
	return step(b.x, uv.x) * step(b.y, uv.y) * step(uv.x, b.z) * step(uv.y, b.w);
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float m = 0.0;
	if (occ_count > 0) { vec2 q = occ_uv(occ_u0, occ_v0); m = max(m, texture(occ_tex0, q).a * inside(q, occ_b0)); }
	if (occ_count > 1) { vec2 q = occ_uv(occ_u1, occ_v1); m = max(m, texture(occ_tex1, q).a * inside(q, occ_b1)); }
	if (occ_count > 2) { vec2 q = occ_uv(occ_u2, occ_v2); m = max(m, texture(occ_tex2, q).a * inside(q, occ_b2)); }
	if (occ_count > 3) { vec2 q = occ_uv(occ_u3, occ_v3); m = max(m, texture(occ_tex3, q).a * inside(q, occ_b3)); }
	vec2 px = TEXTURE_PIXEL_SIZE * rim_texels;
	float n = min(min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	vec4 c = n < 0.35 ? rim_color : fill_color;
	COLOR = vec4(c.rgb, c.a * fade * step(0.35, a) * step(0.5, m));
}
