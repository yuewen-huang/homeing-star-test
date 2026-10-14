extends SceneTree
## Screenshots of the guard / parry / red-parry contact effects against the deer (dev room)
## and the master (tutorial room), cropped around both fighters, to judge where each effect
## lands. Usage: --script tools/capture_parry_effects.gd -- <out dir>

var output := ""
var log_lines: Array[String] = []

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func shot(name: String, a: Vector2, b: Vector2) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var xf := root.get_viewport().get_canvas_transform()
	var mid := Vector2i(xf * ((a + b) * 0.5))
	var crop := Rect2i(mid - Vector2i(300, 230), Vector2i(600, 360)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.get_region(crop).save_png(output.path_join(name + ".png"))

func burst(label: String, player: LanPlayer, attacker: Node2D, count := 8) -> void:
	for i in count:
		await shot("%s_%02d" % [label, i], player.global_position, attacker.global_position)
		if player.red_counter_slash_visual.visible: log_lines.append("%s_%02d: counter slash at %s frame %d" % [label, i, player.red_counter_slash_visual.global_position, player.red_counter_slash_visual.frame])
		for effect in root.get_tree().get_nodes_in_group(CombatImpactEffect.GROUP):
			if i == 0: log_lines.append("%s: %s at %s (player %s, attacker %s)" % [label, (effect as CombatImpactEffect).animation, effect.global_position, player.global_position, attacker.global_position])
		for f in 3: await process_frame
	while Engine.time_scale < 1.0: await process_frame
	await create_timer(0.8).timeout

func run_against(prefix: String, player: LanPlayer, attacker: DamageReceiver2D) -> void:
	var hurt := player.defense_contact_point(attacker.global_position)
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	# Guard failure (early parry): the player is struck through the block.
	player.start_parry_failure(attacker.global_position)
	player.emit_received_hit_feedback(attacker.global_position, 0.65, hurt)
	await burst(prefix + "_guard_fail", player, attacker)
	player.play_idle(); player.defense_state = LanPlayer.DefenseState.NONE
	# Normal parry.
	player.start_parry_success(attacker.global_position)
	feedback.emit_parry_success(attacker, CombatAttackData.new(&"t", attacker, 20, 12, 180.0, 0.0), hurt)
	await burst(prefix + "_parry", player, attacker)
	player.play_idle(); player.defense_state = LanPlayer.DefenseState.NONE
	# Red parry: the player's own animation plus whatever the attacker adds.
	player.start_red_parry_success(attacker)
	attacker.on_attack_parried(CombatAttackData.new(&"t", attacker, 20, 12, 180.0, 0.0, CombatAttackData.DangerType.COUNTERABLE_DANGER), hurt)
	await burst(prefix + "_red_parry", player, attacker, 12)

func run() -> void:
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	for i in 3: await process_frame
	room.select_combo(2)
	var player: LanPlayer = room.player
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position.x = deer.global_position.x - 150.0
	player.facing_direction = 1.0; player.apply_facing_direction()
	await run_against("deer", player, deer)
	room.queue_free()
	await process_frame

	var tutorial = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
	root.add_child(tutorial); current_scene = tutorial
	for i in 3: await process_frame
	var lan := tutorial.get_node("Lan") as LanPlayer
	var master := tutorial.get_node("MasterBoss") as DamageReceiver2D
	master.set("manual_control", true)
	master.set_physics_process(false)
	lan.set_physics_process(false)
	lan.global_position.x = master.global_position.x - 150.0
	lan.facing_direction = 1.0; lan.apply_facing_direction()
	await run_against("master", lan, master)
	var file := FileAccess.open(output.path_join("effects.txt"), FileAccess.WRITE)
	file.store_string("\n".join(log_lines)); file.close()
	print("\n".join(log_lines))
	quit(0)
