# © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
class_name EnemySilhouettes
extends Node2D
## Silueta roja de los enemigos tapados por árboles, edificios, estructuras y torretas.
##
## Cuándo: un enemigo (Enemy, jefes incluidos; nunca NPC, animales, mascotas ni el Doble disfrazado) cuyo sprite
## se solapa con el rectángulo de un objeto grande que se dibuja DELANTE por el orden en Y (su base está más abajo
## que los pies del enemigo). Se evalúa cada CHECK_EVERY s con una grilla espacial de los props estáticos (no
## enemigos × props por cuadro), repartida en tandas por cuadro; las torretas, pocas, se prueban directo.
##
## Qué se ve: un Sprite2D por enemigo tapado, en una capa por encima de los props (z 5), que copia cada cuadro la
## textura, el cuadro de animación, el flip y la transformación global del AnimatedSprite2D del enemigo. El shader
## (enemy_silhouette.gdshader) lo pinta rojo semitransparente (relleno ~0,48 y contorno ~0,56) SOLO sobre los
## píxeles opacos de los objetos que lo tapan: lo que del enemigo ya se ve queda normal. Si el enemigo sale de
## detrás, la máscara lo recorta en el acto y la silueta se desvanece en ~0,15 s.
##
## Visión: nada fuera de la cámara; en las zonas oscuras del bosque solo dentro de DARK_SIGHT del jugador (lo que
## alumbra); de noche solo dentro de NIGHT_SIGHT. Un enemigo casi invisible (emboscadas, muertes) no se revela.

const CHECK_EVERY := 0.15
const REBUILD_EVERY := 1.0       # s entre comprobaciones de la firma de los props (rehace la grilla si cambió)
const REBUILD_BUDGET_US := 1500  # µs por cuadro para rehacer la grilla (miles de props en el bosque)
const CELL := 160.0              # lado de la celda de la grilla (px de lienzo)
const MIN_OCC_H := 56.0          # alto mínimo (px de lienzo) de un obstáculo: árboles, edificios, galpones, carros,
                                 # espantapájaros, arbustos altos y vallas altas; no matas, faroles ni vallas bajas
const MAX_OCC := 4               # objetos por silueta (los que más tapan)
const ENTER_FRAC := 0.12         # fracción del rect del enemigo bajo objetos delanteros para encender la silueta
const EXIT_FRAC := 0.05          # ... y para apagarla (histéresis: sin parpadeo en el borde)
const NIGHT_SIGHT := 380.0       # px de mundo: de noche no se revela más allá
const DARK_SIGHT := 180.0        # px de mundo: zonas oscuras del bosque (radio de la luz del jugador)
const FADE_IN := 0.1
const FADE_OUT := 0.15
const RIM_PX := 1.6              # grosor del contorno en px de pantalla
const SHADER := preload("res://scripts/world/enemy_silhouette.gdshader")

var main
var enabled := true
var _static: Array = []          # obstáculos fijos: {node, rect, y, z, tex, u, v, b}
var _grid := {}                  # Vector2i -> Array[int] (índices en _static)
var _rb := {}                    # reconstrucción por tandas en curso (vacío = ninguna)
var _known := {}                 # id de nodo -> obstáculo ya calculado (o {"skip"}): rehacer la grilla es barato
var _stamp := PackedInt32Array()
var _stamp_id := 0
var _sig := ""
var _cursor := -1
var _quota := 0.0
var _dyn_cache: Array = []       # torretas (se rehace cada CHECK_EVERY s)
var _dyn_t := 0.0
var _rebuild_t := 0.0
var _active := {}                # id del enemigo -> {e, spr, occ: Array, fade, out}
var _pool: Array = []
var _dark_cache := {}            # id del enemigo -> [pos, dark]: forest_dark_at es caro, se recalcula al moverse
# medición (--silhouettetest): tiempos en µs
var stat_checks := 0
var stat_check_us := 0
var stat_check_max := 0
var stat_frame_us := 0
var stat_frame_max := 0
var stat_frames := 0
var stat_candidates := 0
var stat_checked := 0
var stat_rebuilds := 0
var stat_rebuild_us := 0


func init(m) -> EnemySilhouettes:
	main = m; name = "EnemySilhouettes"
	z_index = 5; z_as_relative = false   # encima de todo lo que está de pie (z 0), bajo carteles, niebla y luces
	return self


func _ready() -> void:
	if DevTools.has("silhouettetest"): add_child(load("res://tools/silhouette_test.gd").new().init(main, self))
	if DevTools.has("bptest"): add_child(load("res://tools/blueprint_test.gd").new().init(main))


# ---------------------------------------------------------------- Bucle
func _process(delta: float) -> void:
	if main == null or main.world == null: return
	var t0 := Time.get_ticks_usec()
	var off: bool = not enabled or main.in_workshop or main.player == null
	_rebuild_t -= delta
	if _rebuild_t <= 0.0:
		_rebuild_t = REBUILD_EVERY
		_maybe_rebuild()
	if not _rb.is_empty(): _rebuild_step(REBUILD_BUDGET_US)
	if off: _hide_all()
	else: _check(delta)
	_update(delta)
	var us := Time.get_ticks_usec() - t0
	stat_frames += 1; stat_frame_us += us; stat_frame_max = maxi(stat_frame_max, us)


## ¿Cuántos enemigos tienen la silueta encendida ahora mismo?
func active_count() -> int:
	var n := 0
	for k in _active.keys():
		if not _active[k]["out"]: n += 1
	return n


func is_silhouetted(e) -> bool:
	var a = _active.get(e.get_instance_id())
	return a != null and not a["out"]


func reset_stats() -> void:
	stat_checks = 0; stat_check_us = 0; stat_check_max = 0; stat_frame_us = 0; stat_frame_max = 0; stat_frames = 0; stat_candidates = 0
	stat_checked = 0; stat_rebuilds = 0; stat_rebuild_us = 0


# ---------------------------------------------------------------- Obstáculos fijos (props del mundo)
func _decor_parents() -> Array:
	var out: Array = []
	# en el bosque solo cuentan los props del bosque (los enemigos están ahí) y en la granja los de la granja
	for n in [main.world.get("_decor_forest") if main.in_forest else main.world.get("_decor")]:
		if n != null and n.is_visible_in_tree(): out.append(n)
	return out


func _maybe_rebuild() -> void:
	if not _rb.is_empty(): return   # ya hay una reconstrucción en curso
	var sig := ""
	for p in _decor_parents(): sig += "%s:%d;" % [p.name, p.get_child_count()]
	if sig == _sig: return
	_sig = sig
	_rb = {"nodes": _decor_nodes(), "i": 0, "static": [], "grid": {}, "us": 0}


func _decor_nodes() -> Array:
	var out: Array = []
	for parent in _decor_parents(): out.append_array(parent.get_children())
	return out


## Rehace la lista de obstáculos fijos y la grilla de una vez (pruebas); en el juego se hace por tandas.
func rebuild() -> void:
	_rb = {"nodes": _decor_nodes(), "i": 0, "static": [], "grid": {}, "us": 0}
	_rebuild_step(1 << 30)


## Reconstrucción por tandas (al entrar/salir del bosque o si se agregan/quitan props): como mucho `budget_us`
## por cuadro; mientras tanto sigue valiendo la grilla anterior. El bosque tiene miles de árboles.
func _rebuild_step(budget_us: int) -> void:
	var t0 := Time.get_ticks_usec()
	var nodes: Array = _rb["nodes"]
	var st: Array = _rb["static"]
	var grid: Dictionary = _rb["grid"]
	var i: int = _rb["i"]
	while i < nodes.size():
		var c = nodes[i]
		i += 1
		if (i & 63) == 0 and Time.get_ticks_usec() - t0 > budget_us: break
		if not is_instance_valid(c) or not (c is Sprite2D or c is AnimatedSprite2D) or not c.visible: continue
		if c.z_index < 0 or c.modulate.a < 0.5: continue
		# los props son fijos: se reutiliza lo ya calculado salvo que el editor lo haya movido
		var key: int = c.get_instance_id()
		var o: Dictionary = _known.get(key, {"pos": Vector2.INF})
		if o["pos"] != c.position:
			o = _occluder(c)
			if o.is_empty() or (o["rect"] as Rect2).size.y < MIN_OCC_H: o = {"skip": true}
			o["pos"] = c.position
			_known[key] = o
		if o.has("skip"): continue
		var idx := st.size()
		st.append(o)
		var r: Rect2 = o["rect"]
		for cx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
			for cy in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
				var k := Vector2i(cx, cy)
				if not grid.has(k): grid[k] = []
				grid[k].append(idx)
	_rb["i"] = i
	_rb["us"] = int(_rb["us"]) + Time.get_ticks_usec() - t0
	if i >= nodes.size():
		_static = st; _grid = grid
		_stamp.resize(_static.size()); _stamp.fill(0)
		stat_rebuilds += 1; stat_rebuild_us += int(_rb["us"])
		_rb = {}


## Rectángulo dibujado (lienzo), orden en Y y la afín mundo -> UV de la textura de un Sprite2D / AnimatedSprite2D.
static func _occluder(c: CanvasItem) -> Dictionary:
	var tex: Texture2D
	if c is Sprite2D:
		tex = c.texture
	elif c is AnimatedSprite2D and c.sprite_frames:
		tex = c.sprite_frames.get_frame_texture(c.animation, c.frame)
	if tex == null: return {}
	var size := Vector2(tex.get_size())
	if c is Sprite2D and c.region_enabled: size = c.region_rect.size
	if size.x <= 0.0 or size.y <= 0.0: return {}
	var ofs: Vector2 = c.offset
	if c.centered: ofs -= size / 2.0
	var local := Rect2(ofs, size)
	var g: Transform2D = c.get_global_transform()
	var rect := _xform_aabb(g, local)
	var inv := g.affine_inverse()
	# UV local (0..1 sobre el rect dibujado); el flip espeja la textura dentro del mismo rect
	var u := Vector3(inv.x.x / size.x, inv.y.x / size.x, (inv.origin.x - ofs.x) / size.x)
	var v := Vector3(inv.x.y / size.y, inv.y.y / size.y, (inv.origin.y - ofs.y) / size.y)
	if c.flip_h: u = -u; u.z += 1.0
	if c.flip_v: v = -v; v.z += 1.0
	var b := Vector4(0, 0, 1, 1)
	var sample_tex := tex
	var reg := Rect2()
	if tex is AtlasTexture and (tex as AtlasTexture).atlas:
		sample_tex = (tex as AtlasTexture).atlas; reg = (tex as AtlasTexture).region
	elif c is Sprite2D and c.region_enabled:
		reg = c.region_rect
	if reg.size.x > 0.0:
		var asz := Vector2(sample_tex.get_size())
		u = u * (reg.size.x / asz.x); u.z += reg.position.x / asz.x
		v = v * (reg.size.y / asz.y); v.z += reg.position.y / asz.y
		b = Vector4(reg.position.x / asz.x, reg.position.y / asz.y, reg.end.x / asz.x, reg.end.y / asz.y)
	return {"node": c, "rect": rect, "y": c.global_position.y, "z": c.z_index, "tex": sample_tex, "u": u, "v": v, "b": b}


static func _xform_aabb(g: Transform2D, r: Rect2) -> Rect2:
	var out := Rect2(g * r.position, Vector2.ZERO)
	out = out.expand(g * Vector2(r.end.x, r.position.y))
	out = out.expand(g * Vector2(r.position.x, r.end.y))
	return out.expand(g * r.end)


## Torretas y vallas grandes (main.towers): base y, si la base cuenta como grande, también la cabeza.
## Se recalculan en cada comprobación (pocas, y la cabeza gira).
func _dynamic() -> Array:
	var out: Array = []
	for t in main.towers:
		if not is_instance_valid(t) or t.dead or not t.is_visible_in_tree(): continue
		var base = t.get("sprite")
		if base == null or not base.visible: continue
		var ob := _occluder(base)
		if ob.is_empty() or (ob["rect"] as Rect2).size.y < MIN_OCC_H: continue
		ob["y"] = t.global_position.y; ob["dyn"] = true
		out.append(ob)
		var head = t.get("head")
		if head != null and is_instance_valid(head) and head.is_visible_in_tree():
			var oh := _occluder(head)
			if not oh.is_empty():
				oh["y"] = t.global_position.y; oh["dyn"] = true   # la cabeza se ordena con su torreta
				out.append(oh)
	return out


# ---------------------------------------------------------------- Comprobación escalonada
## Cada cuadro revisa una tanda de enemigos (round-robin) de modo que todos se revisan una vez cada CHECK_EVERY s:
## el costo queda repartido parejo entre cuadros, sin picos cada 0,15 s.
func _check(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var list: Array = main.enemies
	var n := list.size()
	_dyn_t -= delta
	if _dyn_t <= 0.0:
		_dyn_t = CHECK_EVERY; _dyn_cache = _dynamic()
	if n > 0:
		_quota += n * delta / CHECK_EVERY
		var todo := mini(int(_quota), n)
		_quota -= todo
		if todo > 0:
			var view := _view_rect()
			for i in range(todo):
				_cursor = (_cursor + 1) % n
				var e = list[_cursor]
				if is_instance_valid(e): _check_one(e, view)
			stat_checked += todo
	# siluetas de enemigos que ya no están en la lista (retirados, limpiados al cambiar de zona)
	for id in _active.keys():
		var a: Dictionary = _active[id]
		if not is_instance_valid(a["e"]) or not list.has(a["e"]): a["out"] = true
	var us := Time.get_ticks_usec() - t0
	stat_checks += 1; stat_check_us += us; stat_check_max = maxi(stat_check_max, us)


func _check_one(e, view: Rect2) -> void:
	var id: int = e.get_instance_id()
	var rect := _enemy_rect(e)
	var ok := rect.size.x > 0.0 and view.intersects(rect) and _eligible(e) and _in_sight(e)
	var occ: Array = []
	var frac := 0.0
	if ok:
		var ey: float = e.global_position.y
		var area := rect.get_area()
		var hits: Array = []
		_stamp_id += 1
		for cx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
			for cy in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
				for idx in _grid.get(Vector2i(cx, cy), []):
					if _stamp[idx] == _stamp_id: continue
					_stamp[idx] = _stamp_id
					_hit(_static[idx], rect, area, ey, hits)
		for o in _dyn_cache: _hit(o, rect, area, ey, hits)
		if not hits.is_empty():
			hits.sort_custom(func(x, y): return x[0] > y[0])
			for h in hits:
				frac += float(h[0])
				if occ.size() < MAX_OCC: occ.append(h[1])
	var cur = _active.get(id)
	var on: bool = cur != null and not cur["out"]
	if ok and (frac >= ENTER_FRAC or (on and frac >= EXIT_FRAC)): _show(e, occ)
	elif cur != null: cur["out"] = true


func _hit(o: Dictionary, rect: Rect2, area: float, ey: float, hits: Array) -> void:
	stat_candidates += 1
	if int(o["z"]) <= 0 and float(o["y"]) <= ey: return   # detrás del enemigo por orden en Y
	var r: Rect2 = o["rect"]
	if not r.intersects(rect): return
	var ov := r.intersection(rect).get_area() / area
	if ov > 0.0: hits.append([ov, o])


func _eligible(e) -> bool:
	if e.dead or e.get("disguised") or not e.is_visible_in_tree(): return false
	var s: AnimatedSprite2D = e.sprite
	if s == null or not s.visible: return false
	return e.modulate.a * s.modulate.a * s.self_modulate.a >= 0.35


func _in_sight(e) -> bool:
	var d: float = e.position.distance_to(main.player.position)
	if main.in_forest:
		var id: int = e.get_instance_id()
		var c = _dark_cache.get(id)
		if c == null or (c[0] as Vector2).distance_to(e.position) > 40.0:
			c = [e.position, World.forest_dark_at(e.position)]
			_dark_cache[id] = c
		if c[1] and d > DARK_SIGHT: return false
	if Game.is_night and d > NIGHT_SIGHT: return false
	return true


func _view_rect() -> Rect2:
	var cam: Camera2D = main.player.get("camera")
	if cam == null or not cam.is_inside_tree(): return Rect2(-1e6, -1e6, 2e6, 2e6)
	var sz := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - sz / 2.0, sz)


## Rect dibujado del cuadro actual del enemigo, en lienzo.
func _enemy_rect(e) -> Rect2:
	var s: AnimatedSprite2D = e.get("sprite")
	if s == null or s.sprite_frames == null: return Rect2()
	var tex := s.sprite_frames.get_frame_texture(s.animation, s.frame)
	if tex == null: return Rect2()
	var size := Vector2(tex.get_size())
	var ofs := s.offset - (size / 2.0 if s.centered else Vector2.ZERO)
	return _xform_aabb(s.get_global_transform(), Rect2(ofs, size))


# ---------------------------------------------------------------- Siluetas (pool de Sprite2D)
func _show(e, occ: Array) -> void:
	var id: int = e.get_instance_id()
	var a = _active.get(id)
	if a == null:
		var spr: Sprite2D = _pool.pop_back() if not _pool.is_empty() else _new_sprite()
		spr.visible = true
		a = {"e": e, "spr": spr, "occ": [], "fade": 0.0, "out": false, "sig": ""}
		_active[id] = a
	a["out"] = false
	a["occ"] = occ
	_apply_occ(a, true)


func _new_sprite() -> Sprite2D:
	var spr := Sprite2D.new()
	var mat := ShaderMaterial.new(); mat.shader = SHADER
	spr.material = mat
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
	return spr


## Pasa al shader los obstáculos vigentes (los que siguen delante por Y). `force`: reescribir aunque no cambien.
func _apply_occ(a: Dictionary, force := false) -> int:
	var e = a["e"]
	var ey: float = e.global_position.y
	var mat: ShaderMaterial = (a["spr"] as Sprite2D).material
	var live: Array = []
	for o in a["occ"]:
		if not is_instance_valid(o["node"]): continue
		if int(o["z"]) <= 0 and float(o["y"]) <= ey: continue   # el enemigo pasó delante: ya no lo tapa
		if o.get("dyn", false):
			var fresh := _occluder(o["node"])   # la cabeza de la torreta gira: su afín cambia
			if fresh.is_empty(): continue
			fresh["y"] = o["y"]; fresh["dyn"] = true; o.merge(fresh, true)
		live.append(o)
	var sig := ""
	for o in live: sig += str(o["node"].get_instance_id()) + ","
	var dyn := live.any(func(o): return o.get("dyn", false))
	if not force and sig == a["sig"] and not dyn: return live.size()
	a["sig"] = sig
	mat.set_shader_parameter("occ_count", live.size())
	for i in range(live.size()):
		var o: Dictionary = live[i]
		mat.set_shader_parameter("occ_tex%d" % i, o["tex"])
		mat.set_shader_parameter("occ_u%d" % i, o["u"])
		mat.set_shader_parameter("occ_v%d" % i, o["v"])
		mat.set_shader_parameter("occ_b%d" % i, o["b"])
	return live.size()


func _update(delta: float) -> void:
	if _active.is_empty(): return
	var zoom := 1.0
	var cam: Camera2D = main.player.get("camera") if main.player else null
	if cam: zoom = cam.zoom.x
	for id in _active.keys():
		var a: Dictionary = _active[id]
		var e = a["e"]
		var spr: Sprite2D = a["spr"]
		var valid: bool = is_instance_valid(e) and not e.dead and e.sprite != null
		if not valid: a["out"] = true
		var live := _apply_occ(a) if valid else 0
		if live == 0: a["out"] = true
		a["fade"] = clampf(float(a["fade"]) + (-delta / FADE_OUT if a["out"] else delta / FADE_IN), 0.0, 1.0)
		if a["out"] and (a["fade"] <= 0.0 or not valid):
			spr.visible = false; _pool.append(spr); _active.erase(id); _dark_cache.erase(id)
			continue
		var s: AnimatedSprite2D = e.sprite
		spr.texture = s.sprite_frames.get_frame_texture(s.animation, s.frame)
		spr.centered = s.centered; spr.offset = s.offset
		spr.flip_h = s.flip_h; spr.flip_v = s.flip_v
		spr.global_transform = s.get_global_transform()
		var mat: ShaderMaterial = spr.material
		mat.set_shader_parameter("fade", a["fade"])
		var gs := absf(spr.global_transform.get_scale().x) * zoom
		mat.set_shader_parameter("rim_texels", RIM_PX / maxf(0.02, gs))


func _hide_all() -> void:
	for id in _active.keys(): _active[id]["out"] = true
