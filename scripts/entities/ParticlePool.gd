# © 2026 Cristian Luis Celie. All rights reserved. Portfolio excerpt from Hessel's Farm: shared for review only, not licensed for use, copying or redistribution.
extends Node2D
## Small debris shares two bounded batches. Animated art stays in Ent.Fx.
const CAPACITY := 384
var _groups := {}


func _ready() -> void:
	set_process(false)


func add(kind: String, at: Vector2, count: int) -> bool:
	if Ent.Fx.FLASH_DEFS.has(kind) or Ent.Fx.WAVES.has(kind): return false
	var color: Color = Ent.Fx.COLORS.get(kind,Color.WHITE)
	var frames := SpriteLib.frames("fx/"+kind,["anim"],color,Vector2i(1,1))
	if frames.get_frame_count("anim") > 1: return false
	var luminous := kind in ["spark","electric","fire"]
	if not _groups.has(luminous):
		var mesh := QuadMesh.new(); mesh.size = Vector2.ONE
		var batch := MultiMesh.new(); batch.transform_format = MultiMesh.TRANSFORM_2D
		batch.use_colors = true; batch.mesh = mesh; batch.instance_count = CAPACITY
		batch.visible_instance_count = 0
		var display := MultiMeshInstance2D.new(); display.multimesh = batch
		if luminous: display.material = SpriteLib.fx_material()
		add_child(display)
		_groups[luminous] = {"batch":batch,"display":display,"items":[]}
	var items: Array = _groups[luminous]["items"]
	for i in range(count):
		if items.size() >= CAPACITY: items.pop_front()
		items.append({"p":at,"v":Vector2(randf_range(-70,70),randf_range(-90,40)),"c":color,"s":5.0 if kind=="explosion" else 3.0,"life":.7})
	set_process(true)
	return true


func _process(delta: float) -> void:
	var active := false
	for group in _groups.values():
		var kept: Array = []
		var batch: MultiMesh = group["batch"]
		for particle in group["items"]:
			particle["life"] -= delta
			if particle["life"] <= 0.0: continue
			particle["p"] += particle["v"]*delta; particle["v"] *= .9
			var size: float = particle["s"]
			var color: Color = particle["c"]; color.a *= clampf(particle["life"]/.7,0.0,1.0)
			batch.set_instance_transform_2d(kept.size(),Transform2D(0.0,Vector2(size,size),0.0,particle["p"]+Vector2(size,size)*.5))
			batch.set_instance_color(kept.size(),color)
			kept.append(particle)
		group["items"] = kept; batch.visible_instance_count = kept.size()
		group["display"].visible = not kept.is_empty()
		active = active or not kept.is_empty()
	set_process(active)
