# © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
class_name ImpactPool
extends Node2D
## Impactos de bala de las torretas sobre los enemigos, pensados para el móvil: UN solo nodo dibuja todos los impactos
## vivos en un _draw (una llamada de dibujo, sin nodos ni partículas por impacto) y hay un tope fijo (MAX): si se llena,
## se recicla el más viejo. Cada impacto: un destello chico en el punto de contacto (dura 3-4 cuadros) y 2-3 chispas
## cortas que rebotan contra el sentido de la bala. Radio ≤ 4 px y vida ≤ 0,2 s: se ve el golpe sin tapar al blanco ni
## llenar la pantalla aunque disparen varias Gatling a la vez.
## Lo crea Main.spawn_impact (en la capa de efectos); las posiciones llegan en coordenadas del mundo (achatado).

const MAX := 24
const FLASH_T := 0.07
const LIFE := 0.2

var _items: Array = []   # {"p": pos en pantalla-local, "t": edad, "r": radio, "c": color, "sp": [[pos, vel], ...]}
var _circles: MultiMesh
var _sparks: MultiMesh
static var _disk: Texture2D

func _batch(capacity: int, texture: Texture2D = null) -> MultiMesh:
	var mesh := QuadMesh.new(); mesh.size = Vector2.ONE
	var batch := MultiMesh.new(); batch.transform_format = MultiMesh.TRANSFORM_2D
	batch.use_colors = true; batch.mesh = mesh; batch.instance_count = capacity; batch.visible_instance_count = 0
	var display := MultiMeshInstance2D.new(); display.multimesh = batch; display.texture = texture
	add_child(display)
	return batch


func _ready() -> void:
	name = "ImpactPool"
	z_index = 26
	scale = Vector2(1.0, 1.0 / Data.VIEW_Y)   # dibuja sin achatar: el destello es redondo en pantalla
	material = SpriteLib.fx_material(true)
	if _disk == null:
		var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
		for y in range(32):
			for x in range(32):
				var a := clampf(16.0-Vector2(x+.5-16,y+.5-16).length(),0,1)
				image.set_pixel(x,y,Color(1,1,1,a))
		_disk = ImageTexture.create_from_image(image)
	_circles = _batch(MAX*3,_disk); _sparks = _batch(MAX*3)
	set_process(false)


## Impacto en `p` (coordenadas del mundo, las del padre achatado) de una bala que viajaba en `dir` (mundo).
## `strength` 0..1 escala el destello (la Gatling pega poco por bala: destello mínimo).
func add(p: Vector2, dir: Vector2, strength := 1.0, col := Color(1.0, 0.86, 0.55)) -> void:
	if _items.size() >= MAX: _items.pop_front()   # tope fijo: se recicla el más viejo
	var sp := Vector2(p.x, p.y * Data.VIEW_Y)
	var d := Vector2(dir.x, dir.y * Data.VIEW_Y).normalized()
	if d == Vector2.ZERO: d = Vector2.RIGHT
	var sparks: Array = []
	for i in range(2 + (1 if strength > 0.6 else 0)):
		# rebotan hacia atrás y a los lados del golpe, un poco hacia arriba
		var v := (-d).rotated(randf_range(-1.1, 1.1)) * randf_range(55.0, 110.0) + Vector2(0, -25.0)
		sparks.append([sp, v])
	_items.append({"p": sp, "t": 0.0, "r": lerpf(2.2, 4.0, clampf(strength, 0.0, 1.0)), "c": col, "sp": sparks})
	set_process(true)


func _process(delta: float) -> void:
	var keep: Array = []
	for it in _items:
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) >= LIFE: continue
		for s in it["sp"]:
			s[0] = (s[0] as Vector2) + (s[1] as Vector2) * delta
			s[1] = (s[1] as Vector2) * 0.86 + Vector2(0, 140.0 * delta)   # caen un poco
		keep.append(it)
	_items = keep
	_update_batches()
	if _items.is_empty(): set_process(false)


func _update_batches() -> void:
	var circles := 0; var sparks := 0
	for it in _items:
		var t: float = it["t"]
		var c: Color = it["c"]
		if t < FLASH_T:
			var k := 1.0 - t / FLASH_T
			var r: float = it["r"] * (0.7 + 0.5 * (1.0 - k))
			var sizes := [r*1.8,r,r*.45]
			var colors := [Color(c.r,c.g*.8,c.b*.5,.22*k),Color(c.r,c.g,c.b,.85*k),Color(1,1,.95,k)]
			for i in range(3):
				_circles.set_instance_transform_2d(circles,Transform2D(0.0,Vector2.ONE*sizes[i]*2.0,0.0,it["p"]))
				_circles.set_instance_color(circles,colors[i]); circles += 1
		var a := 1.0 - t / LIFE
		for s in it["sp"]:
			var v: Vector2 = s[1]
			var tail: Vector2 = (s[0] as Vector2) - v.normalized() * 3.0
			_sparks.set_instance_transform_2d(sparks,Transform2D(v.angle(),Vector2(3,1),0.0,(tail+s[0])*.5))
			_sparks.set_instance_color(sparks,Color(1,.75,.35,.9*a)); sparks += 1
	_circles.visible_instance_count = circles; _sparks.visible_instance_count = sparks
