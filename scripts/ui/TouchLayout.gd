# © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
extends Node
## Controles táctiles a gusto del jugador:
##  · Joystick FIJO (siempre en su lugar) o LIBRE (aparece donde apoyas el pulgar en la mitad izquierda).
##  · Posición y tamaño de cada control (joystick, correr, atacar, esquivar, acción y ranuras de armas), editables
##    arrastrando sobre la pantalla. Se guarda en user://controls.json (no depende de la partida).
## UI llama a apply() al final de cada reacomodo del HUD: el desplazamiento se suma sobre la posición base y el
## tamaño escala desde el centro del control (pivot en el centro), así el joystick sigue midiendo desde su centro.

const PATH := "user://controls.json"
const MIN_S := 0.6
const MAX_S := 1.8
const NAMES := {"joystick": "Joystick", "sprint": "Correr", "attack": "Atacar", "dodge": "Esquivar", "interact": "Acción", "weapons": "Armas"}

var ui
var joy_mode := "fijo"
var items := {}            # id -> {"dx": float, "dy": float, "s": float}
var editing := false
var _overlay: Control
var _sel := ""
var _drag_last := Vector2.INF
var _slider: HSlider
var _sel_lbl: Label
var _paused_before := false


func init(u) -> Node:
	ui = u; name = "TouchLayout"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	return self


func _load() -> void:
	if not FileAccess.file_exists(PATH): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (d is Dictionary): return
	joy_mode = "libre" if str(d.get("joy_mode", "fijo")) == "libre" else "fijo"
	if d.get("items") is Dictionary: items = d["items"]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"joy_mode": joy_mode, "items": items}))


func free_joystick() -> bool:
	return joy_mode == "libre"


func controls() -> Dictionary:
	return {"joystick": ui.joy_base, "sprint": ui._touch_cells.get("sprint"), "attack": ui._touch_cells.get("attack"),
		"dodge": ui._touch_cells.get("dodge"), "interact": ui._touch_cells.get("interact"), "weapons": ui._wbox}


func scale_of(id: String) -> float:
	return clampf(float((items.get(id, {}) as Dictionary).get("s", 1.0)), MIN_S, MAX_S)


## Tras el reacomodo de UI (las posiciones base ya están puestas): suma el desplazamiento y aplica el tamaño.
func apply() -> void:
	var cs := controls()
	for id in cs:
		var c: Control = cs[id]
		if c == null or not is_instance_valid(c): continue
		# las celdas del bloque de combate se ubican a mano dentro de su contenedor: se recuerda su lugar original
		if c.get_parent() == ui._touch_action_grid and not c.has_meta("base_pos"): c.set_meta("base_pos", c.position)
		var it: Dictionary = items.get(id, {})
		var d := Vector2(float(it.get("dx", 0.0)), float(it.get("dy", 0.0)))
		var s := scale_of(id)
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(s, s)
		if c.has_meta("base_pos"): c.position = (c.get_meta("base_pos") as Vector2) + d
		else: c.position += d
		c.set_meta("home", c.position)
	if _overlay: _overlay.queue_redraw()


## Rectángulo visible del control (con su escala alrededor del centro), en coordenadas de pantalla.
func visual_rect(c: Control) -> Rect2:
	# global_position ya es la esquina transformada (escala alrededor del pivote incluida)
	return Rect2(c.global_position, c.size * c.scale)


# ---------------------------------------------------------------- ventana de ajustes
func open_settings() -> void:
	var body: VBoxContainer = ui.open_modal("Controles táctiles", true, 620, 360)
	var h: Label = ui.label("JOYSTICK", "Section"); body.add_child(h)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); body.add_child(row)
	for opt in [["fijo", "Fijo", "Siempre en el mismo lugar."], ["libre", "Libre", "Aparece donde apoyas el pulgar, en la mitad izquierda."]]:
		var b := Button.new(); b.text = "%s · %s" % [opt[1], opt[2]]; b.custom_minimum_size = Vector2(0, 52)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = "TabActive" if joy_mode == opt[0] else "Tab"
		var mode: String = opt[0]
		b.pressed.connect(func(): joy_mode = mode; save(); ui._reset_touch_state(); ui.close_modal(); open_settings())
		row.add_child(b)
	body.add_child(ui.spacer(6))
	var h2: Label = ui.label("POSICIÓN Y TAMAÑO", "Section"); body.add_child(h2)
	var note: Label = ui.label("Arrastra cada botón a donde te quede cómodo y ajusta su tamaño. Se guarda para todas las partidas.", "Muted")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.add_child(note)
	var row2 := HBoxContainer.new(); row2.add_theme_constant_override("separation", 8); body.add_child(row2)
	var edit := Button.new(); edit.text = "Editar controles"; edit.theme_type_variation = "Primary"; edit.custom_minimum_size = Vector2(0, 48)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; edit.pressed.connect(func(): ui.close_modal(); start_edit()); row2.add_child(edit)
	var reset := Button.new(); reset.text = "Restablecer todo"; reset.custom_minimum_size = Vector2(0, 48)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func(): items = {}; joy_mode = "fijo"; save(); ui._apply_responsive_layout(); ui.toast("Controles restablecidos.")); row2.add_child(reset)


# ---------------------------------------------------------------- modo edición (sobre la pantalla de juego)
func start_edit() -> void:
	if editing: return
	editing = true
	_paused_before = get_tree().paused; get_tree().paused = true
	ui._reset_touch_state()
	ui.touch.visible = true
	if ui._wbox: ui._wbox.visible = true
	for id in ["sprint", "attack", "dodge", "interact"]:
		var c: Control = ui._touch_cells.get(id)
		if c: c.visible = true
	_overlay = Control.new(); _overlay.name = "TouchEdit"; _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; _overlay.process_mode = Node.PROCESS_MODE_ALWAYS; _overlay.z_index = 40
	if "theme_res" in ui: _overlay.theme = ui.theme_res
	_overlay.draw.connect(_draw_overlay)
	_overlay.gui_input.connect(_on_overlay_input)
	ui.add_child(_overlay)
	# barra superior: qué está elegido, tamaño y salir
	var bar := PanelContainer.new(); bar.set_anchors_preset(Control.PRESET_CENTER_TOP); bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.offset_top = 10.0; bar.custom_minimum_size = Vector2(560, 0)
	bar.add_theme_stylebox_override("panel", ui._btn(Color(0.06, 0.05, 0.04, 0.92), Color(ui.GOLD, 0.8), 10, 12, 8))
	_overlay.add_child(bar)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 6); bar.add_child(col)
	_sel_lbl = ui.label("Toca un control para elegirlo y arrástralo para moverlo.", "Section")
	_sel_lbl.add_theme_font_size_override("font_size", 12); _sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; col.add_child(_sel_lbl)
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 8); col.add_child(r)
	var tl: Label = ui.label("Tamaño"); tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER; r.add_child(tl)
	_slider = HSlider.new(); _slider.min_value = MIN_S; _slider.max_value = MAX_S; _slider.step = 0.05; _slider.value = 1.0
	_slider.custom_minimum_size = Vector2(200, 40); _slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _slider.editable = false
	_slider.value_changed.connect(_on_size)
	r.add_child(_slider)
	var one := Button.new(); one.text = "Restablecer"; one.custom_minimum_size = Vector2(0, 40)
	one.pressed.connect(func():
		if _sel == "": return
		items.erase(_sel); ui._apply_responsive_layout(); _select(_sel))
	r.add_child(one)
	var done := Button.new(); done.text = "Listo"; done.theme_type_variation = "Primary"; done.custom_minimum_size = Vector2(90, 40)
	done.pressed.connect(stop_edit); r.add_child(done)
	_overlay.queue_redraw()


func stop_edit() -> void:
	if not editing: return
	editing = false
	save()
	if _overlay: _overlay.queue_free(); _overlay = null
	get_tree().paused = _paused_before
	ui.touch.visible = Data.touch_controls_active()
	ui._apply_responsive_layout()
	ui._restore_gameplay_controls()
	ui._refresh_touch_action_visibility()
	ui.toast("Controles guardados.")


func _select(id: String) -> void:
	_sel = id
	_sel_lbl.text = "%s · arrástralo para moverlo" % NAMES.get(id, id) if id != "" else "Toca un control para elegirlo y arrástralo para moverlo."
	_slider.editable = id != ""
	_slider.set_value_no_signal(scale_of(id) if id != "" else 1.0)
	_overlay.queue_redraw()


func _on_size(v: float) -> void:
	if _sel == "": return
	var it: Dictionary = items.get(_sel, {}); it["s"] = v; items[_sel] = it
	ui._apply_responsive_layout()


func _hit(p: Vector2) -> String:
	var cs := controls()
	var best := ""; var best_area := INF
	for id in cs:
		var c: Control = cs[id]
		if c == null or not c.is_visible_in_tree(): continue
		var r := visual_rect(c).grow(10.0)
		# el más chico gana cuando se superponen (un botón dentro del bloque de armas, por ejemplo)
		if r.has_point(p) and r.get_area() < best_area: best = id; best_area = r.get_area()
	return best


func _on_overlay_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var id := _hit(ev.position)
			_select(id)
			_drag_last = ev.position if id != "" else Vector2.INF
		else:
			_drag_last = Vector2.INF
	elif ev is InputEventMouseMotion and _drag_last != Vector2.INF and _sel != "":
		var d: Vector2 = ev.position - _drag_last
		_drag_last = ev.position
		var it: Dictionary = items.get(_sel, {})
		it["dx"] = float(it.get("dx", 0.0)) + d.x; it["dy"] = float(it.get("dy", 0.0)) + d.y
		items[_sel] = it
		ui._apply_responsive_layout()
		_keep_on_screen(_sel)


## Que ningún control quede fuera de la pantalla al arrastrarlo.
func _keep_on_screen(id: String) -> void:
	var c: Control = controls().get(id)
	if c == null: return
	var view: Vector2 = ui.get_viewport().get_visible_rect().size
	var r := visual_rect(c)
	var fix := Vector2.ZERO
	if r.position.x < 0.0: fix.x = -r.position.x
	if r.end.x > view.x: fix.x = view.x - r.end.x
	if r.position.y < 0.0: fix.y = -r.position.y
	if r.end.y > view.y: fix.y = view.y - r.end.y
	if fix != Vector2.ZERO:
		var it: Dictionary = items.get(id, {})
		it["dx"] = float(it.get("dx", 0.0)) + fix.x; it["dy"] = float(it.get("dy", 0.0)) + fix.y
		items[id] = it
		ui._apply_responsive_layout()


func _draw_overlay() -> void:
	_overlay.draw_rect(Rect2(Vector2.ZERO, _overlay.size), Color(0, 0, 0, 0.28))
	var font: Font = _overlay.get_theme_default_font()
	var cs := controls()
	for id in cs:
		var c: Control = cs[id]
		if c == null or not c.is_visible_in_tree(): continue
		var r := visual_rect(c).grow(4.0)
		var col := Color(ui.GOLD) if id == _sel else Color(1, 1, 1, 0.75)
		_overlay.draw_rect(r, Color(col, 0.10), true)
		_overlay.draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), col, 2.0, 8.0)
		_overlay.draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, col, 2.0, 8.0)
		_overlay.draw_dashed_line(r.end, Vector2(r.position.x, r.end.y), col, 2.0, 8.0)
		_overlay.draw_dashed_line(Vector2(r.position.x, r.end.y), r.position, col, 2.0, 8.0)
		if font:
			_overlay.draw_string_outline(font, r.position + Vector2(4, -6), str(NAMES.get(id, id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
			_overlay.draw_string(font, r.position + Vector2(4, -6), str(NAMES.get(id, id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
