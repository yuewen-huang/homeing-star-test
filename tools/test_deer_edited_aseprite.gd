extends SceneTree
## Native pixel cells must change resolution without changing gameplay geometry.

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	room.player.set_physics_process(false)
	var authored := 0
	for name: String in DeerActionLibrary.clips():
		var id := StringName(name)
		var entry := DeerActionLibrary.clip(id)
		if name.begins_with("human_"): continue
		authored += 1
		var cell := DeerActionLibrary.frame_size(id)
		var density := DeerActionLibrary.texture_to_logical_scale(id)
		check((cell * density).is_equal_approx(Vector2(256, 256)), name + " native density restores original logical canvas")
		var good := true
		for facing in [1, -1]:
			deer.direction = facing
			for frame in int(entry.count):
				deer._show_clip(id, frame)
				var atlas := deer.animated_sprite.sprite_frames.get_frame_texture(id, frame) as AtlasTexture
				good = good and atlas.region == Rect2(Vector2(frame * cell.x, 0), cell)
				var old_scale := 1.4 * DeerActionLibrary.draw_scale(id, frame)
				good = good and deer.animated_sprite.scale.is_equal_approx(Vector2.ONE * old_scale * density)
				var pivot := DeerActionLibrary.pivot(id)
				var expected_base := Vector2((128-pivot.x)*facing,128-pivot.y)*old_scale
				var expected_core: Vector2 = (DeerActionLibrary.anchor(id,frame,&"core")-pivot)*old_scale
				expected_core.x *= facing
				# No active authored-effect body offset in this pure pose inspection.
				good = good and deer.animated_sprite.position.is_equal_approx(expected_base)
				good = good and deer._anchor_offset(id, frame, &"core").is_equal_approx(expected_core)
		check(good, name + " all frames/mirrors preserve pivot, scale and chest world anchor")
	check(authored == 45, "All 45 user-edited clips are active")
	check(DeerActionLibrary.frame_size(&"flick_START") == Vector2(200,200) and int(DeerActionLibrary.clip(&"flick_START").count) == 10, "Updated flick startup uses ten native 200px frames")
	check(DeerActionLibrary.frame_size(&"heavy_END") == Vector2(200,200), "Updated heavy recovery uses native 200px frames")
	check(DeerActionLibrary.frame_size(&"getup_START") == Vector2(200,200), "Updated getup entry uses native 200px frame")
	check(DeerActionLibrary.texture_to_logical_scale(&"human_idle_ING") == 1.0, "Human form retains original density")
	deer.direction = 1
	deer._show_clip(&"idle_ING", 0)
	deer.vfx._sync_body_material()
	var material := deer.animated_sprite.material as ShaderMaterial
	check(is_equal_approx(float(material.get_shader_parameter("texture_to_logical_scale")),1.28), "Chest shader uses original logical radius")
	room.free()
	print("EDITED ASEPRITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
