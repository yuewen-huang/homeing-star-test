extends SceneTree
## Capture only live production move ribbons and their ground accompaniments.
const FPS := 120.0
var output := ""
var recipes := {"fps": FPS,"clips": {}}
var room

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Engine.set_meta(&"master_vfx_baking",true)
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	room.player.position.x = 70
	for move: StringName in [&"inertia_combo",&"lunge_combo",&"air_qi_combo"]:
		for facing in [-1.0,1.0]:
			room.adapter._rebuild()
			var master: MasterBoss = room.adapter.master
			master.position.x = 640
			master.set_process(false)
			master.set_physics_process(false)
			master.attack_hitbox.set_physics_process(false)
			room.adapter.target.position.x = 640+facing*200
			master.start_clash_rhythm(move)
			var rhythm = master.clash_rhythm
			while not rhythm.finished:
				master._process(1.0/240.0)
				for wind in rhythm.winds:
					var node = wind.node
					if not is_instance_valid(node) or not node.has_meta(&"bake_clip"): continue
					var name := String(node.get_meta(&"bake_clip"))
					if recipes.clips.has(name): continue
					var viewport: SubViewport = node.get_child(0)
					var keys: Array = [0.0,float(node.duration),float(node.duration+node.tail),float(node.get_meta(&"bake_contact"))]
					for pose in node.pose_keys: keys.append(float(pose.u)*node.duration)
					# Orbit profiles have 65 interpolation keys, not 65 authored stops.
					if node.pose_keys.size() > 10: keys = [0.0,float(node.duration),float(node.duration+node.tail),float(node.get_meta(&"bake_contact"))]
					var hilt: Vector2 = node.get_meta(&"bake_hilt")
					node.reset()
					await capture(name,node,viewport,node.duration+node.tail,Vector2(viewport.size)*0.5,keys,0.0,[hilt.x,hilt.y])
	await ground_clip("air_qi_combo/takeoff_halo",0.28,0.34,[0.0,0.08,0.20,0.34])
	await ground_clip("air_qi_combo/landing_gold",2.14,0.96,[0.0,0.08,0.3264,0.96])
	await ground_clip("air_qi_combo/release_glint",0.0,0.085,[0.0,0.025,0.085],true)
	FileAccess.open(output.path_join("raw_manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(recipes,"\t"))
	room.free()
	print("MASTER RAW BAKE COMPLETE: ",recipes.clips.size()," clips")
	quit()

func ground_clip(name: String, start: float, total: float, keys: Array, glint := false) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384,128)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source = load("res://scripts/bosses/master/master_air_qi_accents.gd").new()
	viewport.add_child(source)
	source.position = Vector2(viewport.size)*0.5
	source.scale = Vector2.ONE/3.0
	if glint: source.mark_release(source.global_position,Vector2.RIGHT,0.0)
	await capture(name,source,viewport,total,Vector2(viewport.size)*0.5,keys,start,[])
	viewport.free()

func capture(name: String, source: Node2D, viewport: SubViewport, total: float, pivot: Vector2, keys: Array, start: float, hilt: Array) -> void:
	var dir := output.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var times: Array = keys.duplicate()
	for i in range(ceili(total*FPS)+1): times.append(minf(float(i)/FPS,total))
	times.sort()
	var unique: Array = []
	for t in times:
		if unique.is_empty() or float(t)-float(unique[-1]) > 0.000001: unique.append(float(t))
	for i in unique.size():
		var t: float = unique[i]
		if source is MasterTrajectoryRibbon:
			if t > source.age: source.advance(t-source.age)
		else: source.setage(start+t)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(dir.path_join("%04d.png" % i))
	recipes.clips[name] = {"times": unique,"protected": keys,"duration": total,"pivot": [pivot.x,pivot.y],"pixel_size": 3.0,"hilt": hilt}
	print("CAPTURED ",name," ",unique.size()," frames")
