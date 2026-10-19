extends SceneTree
## Verify the gold lash against the real fourth-phase 0.8 camera, in both directions.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var vine: DeerVinePhase
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick() -> void:
	boss._physics_process(1.0 / 60.0)
	boss.vfx._process(1.0 / 60.0)
func until(predicate: Callable, limit := 600) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick()
	return false
func capture(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	boss = room.deer; vine = boss.vine_phase
	room.set_process(false); room.set_physics_process(false); room.player.set_physics_process(false)
	boss.set_physics_process(false); boss.vfx.set_process(false)
	room.player.reset_after_map_fall(Vector2(1250, 555))
	boss.phase = 4; boss.reset_phase(); boss.manual_control = true
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "real room completes the fourth-phase transformation")
	room._process(0)
	var camera := room.get_node("Camera2D") as Camera2D
	camera.force_update_scroll()
	check(camera.zoom.is_equal_approx(Vector2(0.8,0.8)), "production camera uses its actual 0.8 flight view")
	for direction in [1.0, -1.0]:
		boss.position.x = room.player.position.x - direction * 400.0
		vine.start_sequence(&"ground_lash")
		var strike: DeerVineStrike = vine.strikes.back()
		var label := "right" if direction > 0.0 else "left"
		check(is_equal_approx(strike.lash_reach, 1280.0), label + " sweep targets 1024 screen pixels, 80% of 1280")
		check(strike._sprite == null and strike._lash_ribbon.bark.resource_path.ends_with("vine_lash_bark.png") and strike._lash_ribbon.thickness == 56.0 and strike.side == direction, label + " real attack loads tiled thin bark instead of the old sequence")
		check(strike.capsules().is_empty(), label + " warning has no damage")
		check(strike._ground_impacts.is_empty(), label + " warning has no soil burst")
		await capture(label + "_warning")
		check(until(func() -> bool: return strike.lash_frame() == 7), label + " reaches the upright growth frame")
		await capture(label + "_rise")
		check(until(func() -> bool: return strike.lash_frame() == 15), label + " reaches the fast downstroke")
		check(not strike._lash_trails.is_empty() and strike._lash_trails.back().sprite.origin == strike.origin and not strike._lash_trails.back().sprite.draw_root, label + " downstroke echoes share the planted curve without echoing soil")
		var age := strike._age
		var path: PackedVector2Array = strike._lash_ribbon.paths[1].duplicate()
		strike.step(0)
		check(strike._age == age and strike._lash_ribbon.paths[1] == path, label + " action pause freezes skin and collision")
		strike.step(0.25 / 60.0)
		check(is_equal_approx(strike._lash_ribbon.age - (age - strike.warn), 0.25 / 60.0), label + " quarter-speed delta advances the shared curve")
		await capture(label + "_slam")
		# The redraw preserves the action timing, but its exact widest pose is measured.
		var widest_reach := 0.0
		var sampled_age := strike._age
		for index in range(44,84):
			var frame := int(index / 4)
			strike._age = strike.warn + lerpf(DeerVineLashArt.time_at_frame(frame), DeerVineLashArt.time_at_frame(frame + 1), float(index % 4) / 4.0)
			strike._lash_ribbon.sample(strike._age - strike.warn)
			for capsule in strike.capsules():
				widest_reach = maxf(widest_reach, maxf((capsule[0].x - strike.origin.x) * direction, (capsule[1].x - strike.origin.x) * direction) + float(capsule[2]))
		strike._age = sampled_age
		strike._lash_ribbon.sample(sampled_age - strike.warn)
		check(absf(widest_reach * camera.zoom.x / 1280.0 - 0.8) < 0.003, label + " actual thin-body and bristle capsules sweep 80% of the screen")
		check(until(func() -> bool: return strike.lash_frame() == 16), label + " reaches the first vine's floor contact")
		check(not strike._ground_impacts.is_empty(), label + " actual first floor contact spawns the salvaged soil sheet")
		var burst: GroundImpactShock = strike._ground_impacts.back()
		check(burst.sprite.frame >= 2 and burst.position.y == 555.0 and burst.get_child_count() == 1 and burst.sprite.scale.abs().is_equal_approx(Vector2.ONE * 1.4), label + " burst skips white flashes, stays on the floor and has no hitbox")
		var burst_age := burst.age
		strike.step(0)
		check(is_equal_approx(burst.age, burst_age), label + " pause freezes soil animation")
		strike.step(0.25 / 60.0)
		check(is_equal_approx(burst.age - burst_age, 0.25 / 60.0), label + " soil follows quarter-speed action time")
		await capture(label + "_soil_first_contact")
		check(until(func() -> bool: return strike.lash_frame() == 18), label + " reaches the second vine's floor impact")
		var live_capsules := strike.capsules()
		check(live_capsules == strike._lash_ribbon.capsules() and live_capsules.size() > 190, label + " damage uses both rendered curves and attached bristles")
		var max_radius := 0.0
		for capsule in live_capsules: max_radius = maxf(max_radius, capsule[2])
		check(max_radius <= 28.0, label + " thin-vine damage no longer uses enlarged old-art radii")
		for strand in strike._lash_ribbon.paths.size():
			var width: float = 56.0 * (0.76 if strand == 0 else 1.0)
			check(strike._lash_ribbon.paths[strand][0].is_equal_approx(strike.origin + Vector2(0,width * 0.6)), label + " root transition remains planted")
		var center := camera.get_screen_center_position().x
		var safe_x: float = center + direction * 1600.0 * 0.46
		check(is_nan(strike.touch(Rect2(safe_x - 10.0, 481.0, 20.0, 74.0)).x), label + " outer screen margin remains outside the attack")
		check(is_nan(strike.touch(Rect2(center - 10.0, 360.0, 20.0, 20.0)).x), label + " empty area above the floor vine does not inherit the old sprite hitbox")
		await capture(label + "_impact")
		check(strike._ground_impacts.size() > 0, label + " second vine's impact has independent soil feedback")
		check(until(func() -> bool: return strike.lash_frame() == 21), label + " reaches soil dissipation")
		await capture(label + "_soil_dissipation")
		check(until(func() -> bool: return strike.lash_frame() == 23) and not strike.is_active() and strike._lash_trails.is_empty() and strike._ground_impacts.is_empty(), label + " recovery clears damage, trails and soil")
		await capture(label + "_recovery")
		check(until(func() -> bool: return vine.strikes.is_empty()), label + " full animation cleans up")
		# Resolve a fresh complete cast through the real hurtbox at its first
		# visible contact, rather than forcing a hit at an arbitrary impact pose.
		for dodging in [false, true]:
			(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
			room.player.reset_after_map_fall(Vector2(center, 555))
			room.player.combat_stats.restore_health()
			room.player.dodge_bullet_time_remaining = 0.0
			room.player.dodge_evade_triggered = false
			if dodging: room.player.ground_action_state = LanPlayer.GroundActionState.BACK_DODGE
			var contact := vine.spawn_strike(&"ground_lash", center, center - direction * 300.0, 0.0)
			for i in 150:
				contact.step(1.0 / 60.0)
				if contact.hitbox.hit_targets.has(room.player.get_instance_id()): break
			check(contact.hitbox.hit_targets.has(room.player.get_instance_id()), label + " moving thin vine reaches the real player hurtbox")
			var expected := room.player.combat_stats.max_health - (0 if dodging else 15)
			check(room.player.combat_stats.health == expected, label + (" roll evades real gold damage" if dodging else " real gold contact deals 15"))
			for i in 150: contact.step(1.0 / 60.0)
			check(room.player.combat_stats.health == expected and contact.finished, label + " two vines resolve once and end without lingering damage")
			vine.strikes.erase(contact); contact.queue_free()
		(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
		var cancelled := vine.spawn_strike(&"ground_lash", center, center - direction * 300.0, 0.0)
		for i in 80:
			cancelled.step(1.0 / 60.0)
			if not cancelled._ground_impacts.is_empty(): break
		check(not cancelled._ground_impacts.is_empty(), label + " cancellation fixture contains active soil")
		cancelled.cancel()
		check(cancelled._ground_impacts.is_empty() and cancelled.capsules().is_empty() and not cancelled.visible, label + " cancellation clears soil and attack together")
		vine.strikes.erase(cancelled); cancelled.queue_free()
		var skipped := vine.spawn_strike(&"ground_lash", center, center - direction * 300.0, 0.0)
		skipped.step(1.2)
		check(skipped._lash_landed[0] and skipped._lash_landed[1] and not skipped._ground_impacts.is_empty(), label + " a large action step still finds both actual floor contacts")
		skipped.cancel(); vine.strikes.erase(skipped); skipped.queue_free()
	print("GROUND_LASH_SCREEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
