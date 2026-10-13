extends SceneTree

const REGIONS := ["wind", "vine", "mist", "root"]
const COUNTS := [3,4,4,3]
const BOSSES := ["wind_boss", "special_boss_upper_right", "special_boss_lower_left", "root_heart", "final_boss"]
var pair_observations := {}

func observe(visual: CommonPortalVisual) -> void:
	var key := String(visual.get_meta("portal_pair"))
	if not pair_observations.has(key):
		pair_observations[key] = []
	pair_observations[key].append(visual.glow_color)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var checked := 0
	var failures := 0
	for index in range(REGIONS.size()):
		var region: String = REGIONS[index]
		var room := load("res://scenes/sideview/chapter_1_%s_room.tscn" % region).instantiate() as Node2D
		root.add_child(room)
		var player := room.get("player") as LanPlayer
		player.set_physics_process(false)
		var portals: Array = room.get("_portals")
		if portals.size() != COUNTS[index]:
			push_error("Unexpected portal count: " + region)
			failures += 1
		for data: Dictionary in portals:
			var marker := data.get("marker",data.get("anchor")) as Node2D
			var prompt := data.prompt as MapPortalPrompt
			var visual := marker.get_node_or_null("CommonPortalVisual") as CommonPortalVisual
			if not visual:
				push_error("Missing common portal: " + str(marker.get_path()))
				failures += 1
				continue
			if visual.scale != Vector2.ONE or visual.get_node("Frame").texture.get_size() != Vector2(112,168):
				push_error("Portal size is not uniform: " + str(marker.get_path()))
				failures += 1
			observe(visual)
			player.position = room.to_local(marker.global_position)
			player.velocity = Vector2.ZERO
			for frame in range(10):
				await process_frame
			if not prompt.can_interact():
				push_error("Cannot interact at portal: " + str(marker.get_path()))
				failures += 1
			var destination := String(data.get("path", ""))
			if data.has("data"):
				destination = String(data.data.scene)
			if region == "root":
				if marker.name == "MistGate": destination = String(room.get("mist_scene"))
				elif marker.name == "VineGate": destination = String(room.get("vine_scene"))
				else: destination = "res://scenes/sideview/chapter_1_root_heart_room.tscn"
			var target := load(destination) as PackedScene
			if not target:
				push_error("Missing destination: " + destination)
				failures += 1
			elif not data.get("anchor",NodePath()) is Node2D:
				var anchor_path: NodePath = data.get("anchor",NodePath())
				if not anchor_path.is_empty():
					var instance := target.instantiate()
					if not instance.has_node(anchor_path):
						push_error("Missing destination anchor: " + destination + " " + String(anchor_path))
						failures += 1
					instance.free()
			# Show the doorway beside the actor instead of behind the actor.
			player.position.x += 65.0
			for frame in range(10):
				await process_frame
			if not prompt.can_interact():
				push_error("Portal cannot interact from beside its frame")
				failures += 1
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [region,marker.name]))
			print("PORTAL: ",region,"/",marker.name," position ",marker.global_position," -> ",destination)
			player.position.x += prompt.near_range+20
			if prompt.can_interact():
				push_error("Portal interaction ignores range")
				failures += 1
			checked += 1
		room.queue_free()
		await process_frame
		await process_frame
	for boss: String in BOSSES:
		var room := load("res://scenes/sideview/chapter_1_%s_room.tscn" % boss).instantiate() as Chapter1BossRoom
		root.add_child(room)
		room.player.set_physics_process(false)
		var visual := room.get_node("ReturnGate/CommonPortalVisual") as CommonPortalVisual
		observe(visual)
		if visual.scale != Vector2.ONE:
			failures += 1
		room.player.position.x = room.get_node("ReturnGate").position.x+65
		for frame in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("boss_%s.png" % boss))
		room.queue_free()
		await process_frame
		await process_frame
	# Build the actual town entrance off-tree: avoids advancing story/save state.
	var town: Node = load("res://scenes/sideview/homeward_town.tscn").instantiate()
	town.add_main_street()
	observe(town.get("_right_gate_visual") as CommonPortalVisual)
	town.free()
	for key: String in pair_observations:
		var colors: Array = pair_observations[key]
		if colors.size() != 2 or colors[0] != colors[1]:
			push_error("Portal pair differs or is incomplete: " + key)
			failures += 1
		print("PAIR: ",key," ends ",colors.size()," color ",colors[0])
	if pair_observations.size() != 10:
		push_error("Expected 10 reciprocal portal pairs")
		failures += 1
	print("REGION PORTAL CHECKS: ",checked," region portals, ",pair_observations.size()," complete pairs; ",failures," failures")
	quit(failures)
