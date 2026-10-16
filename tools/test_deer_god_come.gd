extends SceneTree
## Full ultimate regression plus finale contact budgets, defence and visual captures.
var room
var deer: DeerBoss
var vine: DeerVinePhase
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick(count := 1) -> void:
	for i in count:
		deer._physics_process(1.0 / 60.0)
		room._physics_process(1.0 / 60.0)
		deer.vfx._process(1.0 / 60.0)
func until(predicate: Callable, limit := 3000) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick()
	return bool(predicate.call())
func snapshot(label: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	deer = room.adapter.deer; vine = deer.vine_phase
	deer.set_physics_process(false); deer.vfx.set_process(false)
	room.select_combo(4); room.play_action(0)
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "development specimen transforms")
	# Overview framing for the authored giant: do not change its world scale.
	var camera := Camera2D.new()
	camera.position = Vector2(700, 20)
	camera.zoom = Vector2.ONE * 0.45
	room.add_child(camera); camera.make_current(); camera.force_update_scroll()
	room.deflect_toggle.button_pressed = true
	room.select_combo_library(DeerVinePhase.LIBRARY.find(&"ultimate")); room.play_action(4)
	var seen := {}
	var waves := 0
	var curtains := 0
	for i in 3000:
		for stampede in vine.stampedes:
			if not seen.has(stampede.get_instance_id()):
				seen[stampede.get_instance_id()] = true
				waves += 1
				check(stampede.plan.all(func(p: Dictionary) -> bool: return not p.king), "original ultimate wave has no king")
		for strike in vine.strikes:
			if not seen.has(strike.get_instance_id()):
				seen[strike.get_instance_id()] = true
				if strike.kind == &"curtain": curtains += 1
		if is_instance_valid(vine.god_statue): break
		tick()
	check(waves == 3 and curtains == 2, "all three stampedes and both curtains still play before the statue")
	check(vine.ultimate_active and vine._darkness.target == 1 and vine.wind.mode == &"center", "darkness and centre pull survive through the finale")
	var statue := vine.god_statue
	check(is_instance_valid(statue), "only final antler is replaced with painted god")
	if not is_instance_valid(statue): quit(1); return
	check(statue.sprite.scale.is_equal_approx(Vector2.ONE * 0.84) and statue.sprite.hframes == 1 and statue.sprite.texture.get_width() == int(statue.data.canvas[0]), "only unchanged F00 is exported at the retained 0.84 world scale")
	check(absf(statue.position.x-room.dummy.position.x) < 1, "statue locks onto the target ground point")
	check(deer.warning_kind == &"gold" and not statue.parryable(), "gold warning and no parry")
	await snapshot("01_warning")
	check(until(func() -> bool: return statue.rise_progress() >= 0.25), "statue rises gradually")
	check(statue.sprite.frame == 0 and statue.sprite.position.y > statue.pivot.y * DeerGodCome.WORLD_SCALE * 0.5, "rise translates full pose upward without changing its scale")
	check(statue.damage_rects().all(func(r: Rect2) -> bool: return r.end.y <= vine.ground_y + 0.01), "underground art never deals contact damage")
	await snapshot("02_rise_quarter")
	until(func() -> bool: return statue.rise_progress() >= 0.7)
	await snapshot("03_rise_late")
	check(until(func() -> bool: return statue.flashed), "exactly one flash begins after full emergence")
	check(statue.hitbox.attack.attack_id == &"deer_god_flash" and not statue.hitbox.attack.guardable and statue.hitbox.attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER, "flash is unguardable gold damage")
	check((root.get_node("CombatFeedback") as CombatFeedbackService).screen_fx.pulse_active(), "screen-wide blast shows the shared green-tinted bullet-time vignette pulse (2026-10-14), not a flat overlay")
	var ids: Array = room.dummy.contacts.map(func(c: Dictionary) -> StringName: return c.id)
	check(ids.count(&"deer_god_rise") == 1 and ids.count(&"deer_god_flash") == 1, "dummy takes one launch and one independent flash despite automatic parry")
	await snapshot("04_full_flash")
	check(statue.sprite.frame == 0 and is_zero_approx(float((statue.sprite.material as ShaderMaterial).get_shader_parameter("erosion"))), "complete first pose is fully visible before dissolution")
	until(func() -> bool: return statue._dust_started)
	check(statue.hitbox.attack == null and vine.ultimate_active, "dissolution has no repeated damage and keeps the caster channeling")
	check(statue.sprite.visible and statue.sprite.frame == 0 and statue.dust.size() == 1208, "dust comes directly from the first pose silhouette")
	check(statue.dust.any(func(p: Dictionary) -> bool: return p.release > 0.1), "dust has staggered release times instead of one simultaneous burst")
	var erosion_start := statue.age
	statue.step(0.0)
	check(is_equal_approx(statue.age, erosion_start), "paused action time freezes dissolution and particles")
	tick(30)
	check(statue.sprite.visible and statue.sprite.frame == 0 and float((statue.sprite.material as ShaderMaterial).get_shader_parameter("erosion")) > 0.2, "dissolution is visibly progressing within half an action second")
	await snapshot("05_erosion_early")
	until(func() -> bool: return statue.age >= statue.dust_start() + DeerGodCome.DISSOLVE_TIME * 0.5)
	check(statue.sprite.visible and statue.sprite.frame == 0 and absf(float((statue.sprite.material as ShaderMaterial).get_shader_parameter("erosion")) - 0.5) < 0.02, "brisk dissolution retains F00 and overlaps released dust at its midpoint")
	await snapshot("06_erosion_middle")
	until(func() -> bool: return statue.age >= statue.dust_start() + DeerGodCome.DISSOLVE_TIME * 0.85)
	await snapshot("06b_erosion_late")
	until(func() -> bool: return not statue.sprite.visible)
	check(absf(statue.age - erosion_start - 2.2) < 0.04, "first pose dissolves smoothly in 2.2 action seconds")
	await snapshot("07_green_dust")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "ultimate closes only after the dust finishes")
	check(statue.age <= statue.dust_start() + DeerGodCome.DISSOLVE_TIME + DeerGodCome.DUST_TIME and statue.finished, "finale closes as the last dust fades without an idle tail")
	check(vine.god_statue == null and not vine.ultimate_active and vine._darkness.target == 0 and vine.wind == null and vine.ultimate_used, "finale cleanup restores normal loop, retaining once-per-fight mark")
	# The actual Lan receiver must neither parry nor reduce the statue's damage.
	var player := load("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = deer.world_min_x
	player.world_max_x = deer.world_max_x
	room.add_child(player)
	player.set_physics_process(false)
	player.reset_after_map_fall(Vector2(room.dummy.position.x, vine.ground_y))
	deer.combat_target = player
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.player_invincible = false
	var effect := DeerGodCome.new(); deer.get_parent().add_child(effect)
	effect.setup(vine, player.position.x, 0)
	var health := player.combat_stats.health
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	effect.step(0.8)
	check(player.air_state == LanPlayer.AirState.RISING and player.velocity.y == DeerGodCome.LAUNCH_VELOCITY and player.combat_stats.health == health, "rising god launches Lan once through active parry without extra HP damage")
	player.velocity.y = -123
	effect.step(0.25)
	check(player.velocity.y == -123, "remaining inside the rise cannot launch Lan again")
	player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	effect.step(DeerGodCome.RISE_TIME)
	check(player.combat_stats.health == health - DeerGodCome.FLASH_DAMAGE, "ordinary guard cannot halve the flash damage")
	effect.cancel(); effect.queue_free()
	deer.combat_target = room.player
	player.queue_free()
	assist.player_invincible = true
	# Interrupt and reset during a visible pulse: no lingering UI overlay or damage.
	room.select_combo_library(DeerVinePhase.LIBRARY.find(&"god_finale_preview"))
	room.play_action(4)
	check(is_instance_valid(vine.god_statue) and vine.stampedes.is_empty() and vine.strikes.is_empty(), "separate development preview starts only the finale; full ultimate sequence remains intact")
	until(func() -> bool: return is_instance_valid(vine.god_statue))
	until(func() -> bool: return vine.god_statue.flashed)
	var interrupted := vine.god_statue
	room.reset_room()
	check(interrupted.finished and not (root.get_node("CombatFeedback") as CombatFeedbackService).screen_fx.pulse_active() and interrupted.hitbox.attack == null, "reset cancels the pulse, contacts and dust together")
	await process_frame
	check(not is_instance_valid(interrupted), "all statue nodes belong to the specimen and are freed on reset")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "preview preserves story progress")
	if OS.get_cmdline_user_args().has("--record"):
		deer = room.adapter.deer; vine = deer.vine_phase
		deer.set_physics_process(false); deer.vfx.set_process(false)
		room.play_action(0)
		until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER)
		camera.zoom = Vector2.ONE * 0.7
		camera.position = Vector2(700,210)
		camera.force_update_scroll()
		room.select_combo_library(DeerVinePhase.LIBRARY.find(&"god_finale_preview"))
		room.play_action(4)
		DirAccess.make_dir_recursive_absolute(output.path_join("animation"))
		for frame in 260:
			await snapshot("animation/frame_%03d" % frame)
			if vine.step == DeerVinePhase.Step.HOVER: break
			tick(3)
	print("GOD COME: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
