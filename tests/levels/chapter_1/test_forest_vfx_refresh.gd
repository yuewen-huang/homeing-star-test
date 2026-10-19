extends SceneTree
## Actual development specimen, a paused action clock, and the production wind shader.
var room
var deer: DeerBoss
var output := ""
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick(count := 1) -> void:
	for i in count:
		deer._physics_process(1.0 / 60.0)
		deer.vfx._process(1.0 / 60.0)
func until(predicate: Callable, limit := 600) -> void:
	for i in limit:
		if predicate.call(): return
		tick()
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	check(not deer.vine_phase._shield_view.shell.visible, "Human armour is hidden before the fourth phase")
	room.select_combo(4)
	room.play_action(0)
	until(func() -> bool: return deer.vine_phase.step == DeerVinePhase.Step.HOVER)
	var phase := deer.vine_phase
	check(phase.human and is_equal_approx(deer.animated_sprite.scale.x, 1.4 * 1.30), "Human body is thirty percent larger after transformation")
	deer.position.x = 850
	deer.direction = -1
	deer._show_clip(&"human_idle_ING", 0)
	phase._shield_view.sync()
	# Match the production fourth-phase framing.
	(room.get_node("Camera2D") as Camera2D).zoom = Vector2.ONE * 0.8
	await capture("human_full_shield")
	phase.shield = 1
	phase._shield_view.sync()
	await capture("human_cracked_shield")
	check(phase._shield_view.shell.shell_material.get_shader_parameter("intact") == 1.0, "Visible shell tracks the remaining armour sector")
	# A cast pose and a left-facing arrival must each use their own painted centre.
	deer._show_clip(&"human_cast_ING", 1)
	var from := phase.navel(deer.position)
	phase._begin_blink({"blink": &"ground", "fast": true})
	check(phase.leaves.back().position.is_equal_approx(from), "Departure uses the current casting body's centre")
	await capture("blink_departure")
	tick(4)
	check(phase.leaves.back().first_frame == 4 and phase.leaves.back().position.is_equal_approx(phase.navel(deer.position)), "Arrival light uses the destination idle body and facing")
	check(phase.leaves.back().offset.is_equal_approx(-DeerVinePhase.DeerLeafTeleport.frame_center(phase.leaves.back().frame)), "Arrival's visible glow, including its transparent margin, stays on the body")
	await capture("blink_arrival")
	until(func() -> bool: return phase.step == DeerVinePhase.Step.HOVER)
	phase.wind_shield.player = room.player
	room.player.position = Vector2(550, 555)
	phase.wind_shield.arm()
	await capture("player_wind_shield")
	check(phase.wind_shield.shell.material.shader == CombatFacetedShield.SHADER, "Player and human armour share the faceted glass renderer")
	phase.wind_shield.cancel()
	phase.shield = 3
	phase.start_sequence(&"wind_push")
	until(func() -> bool: return is_instance_valid(phase.wind))
	tick(45)
	await capture("boss_leaf_current")
	check(phase.wind._leaf_field.material.shader == WindLeafField.SHADER, "Boss current uses the common leaf shader")
	phase.wind.end()
	tick(30)
	var winds := Node2D.new()
	room.add_child(winds)
	for i in 4:
		var flow := TerrainPiece.new()
		flow.kind = "updraft"
		flow.wind_direction = ["up", "right", "down", "left"][i]
		flow.size = Vector2(200, 280)
		flow.position = Vector2(120 + i * 250, 180)
		winds.add_child(flow)
		check(flow.material.shader == WindLeafField.SHADER, "Map wind %s uses the common leaves" % flow.wind_direction)
	await create_timer(0.35).timeout
	await capture("map_four_directions")
	winds.free()
	# Real strike warning / active / recovery, with the larger body and shield.
	phase.start_sequence(&"curtain")
	await capture("curtain_warning")
	until(func() -> bool: return not phase.strikes.is_empty() and phase.strikes[0].is_active())
	await capture("curtain_active")
	until(func() -> bool: return phase.step == DeerVinePhase.Step.HOVER and phase.strikes.is_empty())
	await capture("curtain_recovery")
	check(phase.step == DeerVinePhase.Step.HOVER, "Larger body completes its real spell and recovers")
	room.free()
	await process_frame
	check(saved == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "Visual checks preserve player progress")
	print("FOREST VFX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
