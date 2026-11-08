extends SceneTree
var failures := 0
var report: Array = []
var output := ""
var native := false

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func capture(name: String) -> void:
	if not native: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-room")
	DirAccess.make_dir_recursive_absolute(output)
	native = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	var room = load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	check(room.adapter.boss is SandstormFighter, "New room must select 蝎女")
	check(room.adapter.action_names().size() == 5, "Expected two combos and three skills")
	check(room.segment_picker.item_count == 17, "All source actions must be selectable")
	check(room.adapter.supports_combat_simulation(), "Skill 1 must support opt-in combat practice")
	check(root.get_node("SaveProgress") is BossDevelopmentRoom.PreviewProgress, "Save isolation")
	var health: int = room.player.combat_stats.health
	var boss: SandstormFighter = room.adapter.boss
	boss.set_process(false)
	boss.playback.set_process(false)
	var boss_height := 0.0
	for frame: int in boss.library.frame_numbers("待机"):
		boss_height += boss.library.texture("待机", frame).get_image().get_used_rect().size.y
	boss_height /= boss.library.frame_numbers("待机").size()
	boss_height *= boss.playback.body.global_transform.y.length()
	var lan_sprite: AnimatedSprite2D = room.player.get_node("AnimatedSprite2D")
	var lan_height := 0.0
	for frame in lan_sprite.sprite_frames.get_frame_count(&"idle"):
		lan_height += lan_sprite.sprite_frames.get_frame_texture(&"idle", frame).get_image().get_used_rect().size.y
	lan_height /= lan_sprite.sprite_frames.get_frame_count(&"idle")
	lan_height *= lan_sprite.global_transform.y.length()
	check(absf(boss_height / lan_height - 1.8) < 0.02, "Visible idle height must be about 1.8 times Lan")
	print("VISIBLE HEIGHT: boss=", boss_height, "; Lan=", lan_height, "; ratio=", boss_height / lan_height)
	await capture("idle")
	var bounds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../smear-combo-demo/characters/sandstorm_fighter/motion_bounds.json"))
	for index in SandstormFighter.COMBOS.size():
		room.play_action(index)
		var player = boss.playback
		player.set_process(false)
		player.current.set_process(false)
		var handoffs := 0
		var foot_error := 0.0
		var top_y := INF
		var screen_top_y := INF
		for tick in 1800:
			if player._finished: break
			player.current._process(1.0 / 120.0)
			var old_slot: int = player.slot
			var old_clip = player.current
			player._process(1.0 / 120.0)
			player.current.set_process(false)
			var clip = player.current
			var frame: int = clip._frame_at(clip.clock)
			var action: String = clip.document.action
			var bottom: float = bounds[action][frame][3]
			var top: float = bounds[action][frame][1]
			top_y = minf(top_y, clip.body.to_global(Vector2(128, top) - clip.library.actions[action].cell * 0.5).y)
			var screen_top: Vector2 = clip.body.get_global_transform_with_canvas() * (Vector2(128, top) - clip.library.actions[action].cell * 0.5)
			screen_top_y = minf(screen_top_y, screen_top.y)
			var local_bottom: Vector2 = Vector2(128, bottom) - clip.library.actions[action].cell * 0.5
			var world_bottom: float = clip.body.to_global(local_bottom).y
			if action in ["野蛮冲撞", "刺拳", "摆拳", "肘击", "膝击", "刺踢", "侧身斜上踢", "蓄力双拳", "伏虎霸王拳"] or (action == "升龙拳" and frame < 6) or (action == "肘击地面" and frame >= 7):
				foot_error = maxf(foot_error, absf(world_bottom - room.FLOOR_Y))
			if old_slot != player.slot:
				print("AUTHORED ",index," ",old_clip.document.action," hits=",old_clip.hits," misses=",old_clip.misses)
				check(not player.ghosts.is_empty(), "Missing transition ghost")
				if not player.ghosts.is_empty():
					check(player.ghosts[-1].sprite.is_visible_in_tree() and player.ghosts[-1].sprite.modulate.a > 0, "Invisible transition ghost")
					handoffs += 1
				await capture("combo_%d_transition_%d" % [index, player.slot])
		print("AUTHORED ",index," ",player.current.document.action," hits=",player.current.hits," misses=",player.current.misses)
		check(player._finished, "Combo did not finish")
		check(handoffs == player.playlist.size() - 1, "Missing handoff")
		check(foot_error < 0.1, "Support foot detached from production floor")
		check(screen_top_y > 150, "Aerial body hidden behind toolbar")
		check(player.completed_hits + player.current.hits == player.plan.expected_hits, "Original authored contact sampling changed")
		check(player.completed_misses + player.current.misses == 0, "Original authored trajectory changed")
		check(player.current.speed == 1.0 and player.current.hit_stop_duration == 0.018, "Unexpected playback speed")
		var body_duration := 0.0
		for entry: Dictionary in player.playlist:
			var end: float = player.model.compile_action(player.library, entry.action).duration
			if entry.has("handoff_frame"): end = player.model.frame_time(player.library, entry.action, int(entry.handoff_frame))
			body_duration += end - float(entry.get("start_time", 0))
		check(absf(body_duration - [2.256, 2.055][index]) < 0.001, "Production rhythm durations changed unexpectedly")
		report.append({"combo": boss.action_title, "ghost_handoffs": handoffs, "foot_error": foot_error, "body_duration": body_duration, "with_fx_tail": player.action_time(), "top_y": top_y, "screen_top_y": screen_top_y})
		await capture("combo_%d_finish" % index)
		boss._process(0.5)
		check(boss.looping_idle, "Return to idle after completion")
		boss.playback.set_process(false)
	for index in room.segment_picker.item_count:
		room.select_segment_action(index)
		room.play_segment(&"ALL")
		var clip = boss.playback
		clip.set_process(false)
		var seen := {}
		for tick in 700:
			seen[clip._frame_at(clip.clock)] = true
			if not clip.running: break
			clip._process(0.005)
		check(seen.size() == boss.library.frame_numbers(clip.document.action).size(), "Skipped raw frames: " + clip.document.action)
	check(room.player.combat_stats.health == health, "Preview damaged player")
	for skill_index in 3:
		room.play_action(SandstormFighter.COMBOS.size()+skill_index)
		var skill = [boss.descent,boss.thomas,boss.ambush][skill_index]
		check(is_instance_valid(skill), "Skill button routed to the wrong action")
	var brain := SandstormBrain.new()
	brain.rng.seed = 42
	for choice in 100:
		brain.advance(15)
		check(brain.choose(150,0.5) in ["pressure","counter","descent","thomas","ambush"], "AI selected a retired move")
	room.play_action(0)
	var old_specimen: Node2D = room.specimen
	room.reset_room()
	await process_frame
	check(not is_instance_valid(old_specimen), "Reset leaked previous actor/ghosts/effects")
	check(room.adapter.boss.looping_idle, "Reset should start idle")
	var sandstorm_index: int = room.selected_boss
	room.select_boss(0)
	await process_frame
	check(room.get_node("Camera2D").zoom == Vector2.ONE, "Switching boss must restore original camera")
	room.select_boss(sandstorm_index)
	await process_frame
	check(room.adapter.boss is SandstormFighter, "Switch back to 蝎女 failed")
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "native": native, "combos": report, "raw_actions": 17}, "\t"))
	print("SANDSTORM ROOM: ", failures, " failures; ", JSON.stringify(report))
	root.remove_child(room)
	room.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
