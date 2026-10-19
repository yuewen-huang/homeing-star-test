extends "../../support/harness.gd"


func _initialize() -> void:
	call_deferred("run_test")


func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func run_test() -> void:
	use_memory_progress()
	seed(22)
	var player = (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate()
	player.world_min_x = -900.0
	player.world_max_x = 900.0
	root.add_child(player)
	await process_frame

	var mana_before: float = player.combat_stats.mana
	# 主角在 _ready 里自己认领渲染层（SideviewLayers.PLAYER，压过 NPC 那一层）。
	var z_before_ultimate: int = player.z_index
	if not require(z_before_ultimate == SideviewLayers.PLAYER, "Lan did not claim his own render layer"):
		return
	player.arm_ultimate()
	if not require(player.ultimate_armed and player.animated_sprite.animation == &"ultimate_cast", "First O press did not start the ultimate cast"):
		return
	if not require(is_equal_approx(player.ultimate_window_remaining, 5.0), "Ultimate activation window is not five seconds"):
		return
	if not require(player.ULTIMATE_SLASH_COUNT == 24, "Ultimate no longer performs twenty-four cuts"):
		return
	player.start_ultimate_combo()
	if not require(player.ultimate_active and player.is_invulnerable(), "Ultimate combo did not grant full-duration invulnerability"):
		return
	if not require(player.z_index == player.ULTIMATE_PLAYER_Z_INDEX, "Ultimate did not keep Lan above slash effects"):
		return
	if not require(is_equal_approx(player.combat_stats.mana, mana_before), "Development ultimate unexpectedly consumed mana"):
		return
	if not require(player.ultimate_points.size() == 16 and player.animated_sprite.frame == 0, "Ultimate did not build sixteen traversal landings"):
		return
	if not require(player.collision_layer == 0 and player.collision_mask == 0 and not player.hurtbox.monitorable, "Ultimate traversal still has physical body collision"):
		return
	if not require(
		not player.ultimate_hit_context.grants_mana
		and not player.ultimate_hit_context.grants_rage
		and not player.ultimate_hit_context.builds_combat_mechanic,
		"Ultimate skill settlement incorrectly grants a normal-attack resource or mechanic",
	):
		return
	var has_rising_cut := false
	var has_falling_cut := false
	var previous_point: Vector2 = player.ultimate_origin
	for point: Vector2 in player.ultimate_points:
		var direction := point - previous_point
		has_rising_cut = has_rising_cut or direction.y < -40.0
		has_falling_cut = has_falling_cut or direction.y > 40.0
		previous_point = point
	if not require(has_rising_cut and has_falling_cut, "Ultimate choreography collapsed into horizontal ping-pong cuts"):
		return
	var previous_interval: float = player.get_ultimate_slash_interval(0)
	for index in range(1, 15):
		var interval: float = player.get_ultimate_slash_interval(index)
		if not require(interval < previous_interval, "Ultimate cut intervals do not continuously accelerate"):
			return
		previous_interval = interval

	var saw_left_facing: bool = player.facing_direction < 0.0
	var saw_right_facing: bool = player.facing_direction > 0.0
	for _index in range(1, 16):
		player.update_ultimate_combo(1.0)
		saw_left_facing = saw_left_facing or player.facing_direction < 0.0
		saw_right_facing = saw_right_facing or player.facing_direction > 0.0
	if not require(player.ultimate_slash_segments.size() == 16, "Ultimate did not record all sixteen weapon-point segments"):
		return
	for index in range(1, player.ultimate_slash_segments.size()):
		var previous_segment: PackedVector2Array = player.ultimate_slash_segments[index - 1]
		var current_segment: PackedVector2Array = player.ultimate_slash_segments[index]
		if not require(current_segment[0].distance_to(previous_segment[1]) < 0.01, "Consecutive cuts do not share the same paused weapon point"):
			return
	for index in player.ultimate_slash_segments.size():
		var segment: PackedVector2Array = player.ultimate_slash_segments[index]
		if not require(player.distance_to_segment(player.ultimate_focus, segment[0], segment[1]) < 76.0, "A traversal slash missed the target hurtbox region"):
			return
	if not require(saw_left_facing and saw_right_facing, "Lan did not turn with alternating traversal directions"):
		return
	if not require(player.animated_sprite.frame == 7, "Final traversal did not use the first finishing frame"):
		return
	player.update_ultimate_combo(player.ULTIMATE_TERMINAL_FRAME_DURATION + 0.001)
	var finish_position: Vector2 = player.ultimate_origin
	if not require(player.animated_sprite.frame == 8 and player.global_position.is_equal_approx(finish_position), "Character did not reappear at the cast origin for finishing frame 9"):
		return
	if not require(player.ultimate_replay_index >= 1, "High-speed finishing slashes did not start on finishing frame 9"):
		return
	player.update_ultimate_combo(player.ULTIMATE_FINISH_FRAME_DURATION + 0.001)
	if not require(player.animated_sprite.frame == 9 and player.global_position.is_equal_approx(finish_position), "Character moved between finishing frames 9 and 10"):
		return
	player.update_ultimate_combo(player.ULTIMATE_FINISH_FRAME_DURATION + 0.001)
	if not require(player.ultimate_replay_index == 8, "Finisher did not replay all eight high-speed cuts"):
		return
	if not require(player.z_index == z_before_ultimate, "Ultimate did not restore Lan's normal render layer"):
		return
	if not require(player.collision_layer != 0 and player.collision_mask != 0 and player.hurtbox.monitorable, "Ultimate did not restore Lan's physical body"):
		return

	var effect_script = player.ULTIMATE_SLASH_EFFECT_SCRIPT
	for frame_index in 8:
		var effect = effect_script.new()
		root.add_child(effect)
		var target_tail := Vector2(120.0, 180.0)
		var target_tip := Vector2(410.0, 95.0)
		effect.setup(player.ULTIMATE_SLASH_TEXTURE, frame_index, target_tail, target_tip, false)
		var source_tail_local: Vector2 = effect.BLADE_TAIL_POINTS[frame_index] + Vector2(0.5, 0.5) - effect.FRAME_CENTER
		var source_tip_local: Vector2 = effect.BLADE_TIP_POINTS[frame_index] + Vector2(0.5, 0.5) - effect.FRAME_CENTER
		if not require(effect.to_global(source_tail_local).distance_to(target_tail) < 0.01, "FX blade tail anchor missed its weapon point"):
			return
		if not require(effect.to_global(source_tip_local).distance_to(target_tip) < 0.01, "FX blade tip anchor missed its weapon point"):
			return
		effect.queue_free()

	var battle_room = (load("res://scenes/levels/tutorial/tutorial_battle_room.tscn") as PackedScene).instantiate()
	battle_room.get_node("MasterBoss").manual_control = true
	root.add_child(battle_room)
	await process_frame
	battle_room.process_mode = Node.PROCESS_MODE_DISABLED
	var battle_player = battle_room.get_node("Lan")
	var battle_boss = battle_room.get_node("MasterBoss")
	# Keep this as a geometry-only check. Headless tests have no active gameplay
	# scene for CombatFeedback, so do not dispatch damage while tracing slashes.
	for room_hurtbox in get_nodes_in_group(&"hurtbox"):
		if room_hurtbox is Node and battle_room.is_ancestor_of(room_hurtbox):
			room_hurtbox.remove_from_group(&"hurtbox")
	battle_player.start_ultimate_combo()
	for _index in range(1, 16):
		battle_player.update_ultimate_combo(1.0)
	var boss_hurtbox := battle_boss.get_node("Hurtbox") as Area2D
	var angle_bins: Dictionary = {}
	for segment: PackedVector2Array in battle_player.ultimate_slash_segments:
		var slash_vector := segment[1] - segment[0]
		if not require(slash_vector.length() >= 400.0, "Ultimate traversal was too short to read as a cinematic cut"):
			return
		var undirected_angle := fposmod(slash_vector.angle(), PI)
		angle_bins[int(floor(undirected_angle / (PI / 12.0)))] = true
		if not require(
			battle_player.ultimate_slash_intersects_hurtbox(boss_hurtbox, segment[0], segment[1]),
			"A visible ultimate slash missed the tutorial boss's real hurtbox",
		):
			return
	for landing: Vector2 in battle_player.ultimate_points:
		if not require(
			landing.y >= battle_player.ultimate_origin.y - 170.0 and landing.y <= battle_player.ultimate_origin.y,
			"Ultimate traversal paused outside the boss-height landing band",
		):
			return
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for segment: PackedVector2Array in battle_player.ultimate_slash_segments:
			var line := Line2D.new()
			line.points = segment
			line.width = 1.5
			line.default_color = Color(0.3, 0.9, 1.0, 0.5)
			line.z_index = 25
			battle_room.add_child(line)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join("ultimate_target_geometry.png"))
	check(angle_bins.size() >= 4, "Ultimate keeps at least four 15-degree angle classes (actual: %d)" % angle_bins.size())

	print("Lan ultimate geometry and finish checks completed")
	expect_save_untouched()
	finish("LAN ULTIMATE")
