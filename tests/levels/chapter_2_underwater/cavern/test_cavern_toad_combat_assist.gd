extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const TOAD := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_bronze_toad.gd")
const ATTACK := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_toad_attack.gd")
const FIGHT_AT := TOAD.ORIGIN + Vector2(-360, 0)

var level: SunkenCavern
var toad: TOAD
var lan: LanPlayer
var assist: BattleAssistSettingsService


func run() -> void:
	use_memory_progress()
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	toad = level.bronze_toad
	lan = level.player
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	await physics_frame
	check(not toad.boss_counter_enabled(), "six seals are hidden before engagement")
	await test_first_blue_cue()
	await test_flying_hammer_cues()
	await test_six_parries_and_throw()
	await test_ground_spear_red_counter()
	level.queue_free()
	await process_frame
	expect_save_untouched()
	finish("A25 COMMON COMBAT RULES")


func start_attempt(difficulty: BattleAssistSettingsService.Difficulty) -> void:
	assist.difficulty = difficulty
	toad.reset_attempt()
	lan.reset_after_map_fall(FIGHT_AT)
	lan.combat_stats.restore_health()
	toad._engage()
	toad._wait = 20.0
	level.snap_camera()
	await physics_frame


func release_hover() -> void:
	toad._hover = true
	toad._release_ball()
	lan.reset_after_map_fall(Vector2(toad._ball_destination.x, TOAD.ORIGIN.y))
	level.snap_camera()


func test_first_blue_cue() -> void:
	await start_attempt(BattleAssistSettingsService.Difficulty.EASY)
	check(toad.boss_counter_enabled() and toad.defense_credit == 0 and lan.heal.charges == 2,
		"shared beads and two heal charges enter with the encounter")
	release_hover()
	var saw_blue := false
	var pressed := false
	var blue_after_first := false
	for i in 246:
		await physics_frame
		Input.action_release(&"parry")
		var cue := lan.parry_cue
		if not cue.should_show(): continue
		blue_after_first = blue_after_first or toad.defense_credit > 0
		if not saw_blue and cue.time_to_contact <= 0.32:
			cue._process(0.0)
			saw_blue = cue._display.is_visible_in_tree() and cue.global_position.is_equal_approx(
				lan.defense_contact_point((cue.source as Node2D).global_position))
			await capture("01_easy_first_blade")
		if not pressed and cue.time_to_contact <= 0.20:
			pressed = true
			Input.action_press(&"parry")
	check(saw_blue and pressed, "the live opening volley paints the shared blue ring on Lan's blade")
	check(toad.defense_credit == 3 and lan.combat_stats.health == 100 and not blue_after_first,
		"one real K covers the next two volleys and hides the redundant cue (credit=%d hp=%d)" % [
			toad.defense_credit, lan.combat_stats.health])
	release_hover()
	var new_blue := false
	for i in 85:
		await physics_frame
		if lan.parry_cue.should_show():
			new_blue = true
			break
	check(new_blue, "a new cast asks for a fresh manual parry")
	toad.reset_attempt()


func test_flying_hammer_cues() -> void:
	await start_attempt(BattleAssistSettingsService.Difficulty.EASY)
	lan.reset_after_map_fall(FIGHT_AT + Vector2(70, 0))
	toad._fly = true
	toad._released = true
	toad._enter_hammer(TOAD.Hammer.LIFT)
	var outbound := false
	var recall := false
	for i in 460:
		await physics_frame
		Input.action_release(&"parry")
		if recall and toad.hammer == TOAD.Hammer.REST: break
		var cue := lan.parry_cue
		if cue.source != toad._hammer_contact or not cue.should_show() or cue.time_to_contact > ParryCueVisual.PRESS_LEAD:
			continue
		if not outbound and toad.hammer in [TOAD.Hammer.LIFT, TOAD.Hammer.OUTBOUND]:
			outbound = true
			Input.action_press(&"parry")
		if not recall and toad.hammer in [TOAD.Hammer.FAR, TOAD.Hammer.RECALL]:
			recall = true
			Input.action_press(&"parry")
	check(outbound and recall and toad.defense_credit == 2 and lan.combat_stats.health == 100,
		"pressing K on both blue cues catches the outbound and return hammer (out=%s return=%s credit=%d hp=%d)" % [
			outbound, recall, toad.defense_credit, lan.combat_stats.health])
	toad.reset_attempt()


func test_six_parries_and_throw() -> void:
	await start_attempt(BattleAssistSettingsService.Difficulty.HARD)
	var pressed: Dictionary = {}
	var checked_five := false
	for _cast in 2:
		release_hover()
		for i in 246:
			await physics_frame
			Input.action_release(&"parry")
			for hazard in toad._hazards:
				if not is_instance_valid(hazard) or hazard.kind != ATTACK.Kind.BOLT: continue
				var beat := hazard.impact_beat
				if beat.spent or pressed.has(beat): continue
				var player_at := CombatHitQuery.hurtbox_rect(lan.hurtbox).get_center()
				var offset := player_at - hazard.from
				if absf(hazard.direction.cross(offset)) > ATTACK.BOLT_WIDTH * 0.5: continue
				var left := hazard.cue + (offset.dot(hazard.direction) - ATTACK.BOLT_LENGTH * 0.5) / ATTACK.BOLT_SPEED - hazard.age
				if left > 0.19: continue
				pressed[beat] = true
				Input.action_press(&"parry")
				break
			if not checked_five and toad.defense_credit == 5:
				checked_five = true
				check(not toad.counter_ready and lan.heal.charges == 2,
					"the first five parries leave E locked and heal at two charges")
				lan.combat_stats.apply_health_damage(1)
				check(toad.defense_credit == 5, "receiving damage preserves the five beads")
			if toad.counter_ready: break
	Input.action_release(&"parry")
	check(pressed.size() == 6 and toad.counter_ready and lan.heal.charges == 3,
		"six distinct real Hard K parries fill the shared meter and refill one heal (K=%d credit=%d)" % [
			pressed.size(), toad.defense_credit])
	check(not lan.parry_cue.should_show(), "Hard uses manual timing without the blue ring")
	lan.reset_after_map_fall(FIGHT_AT)
	lan.facing_direction = -1.0
	level.snap_camera()
	toad._spawn_fracture(TOAD.ORIGIN + Vector2(-252, 0))
	for i in 60:
		await physics_frame
		if toad._danger_flash.frame >= 29: break
	check(toad._danger_flash.visible and toad._danger_flash.kind == &"gold" and toad.blocks_boss_throw(),
		"the live gold tell protects its pending soil wave from E")
	await capture("02_gold_soil_wave")
	await press_interact()
	check(toad.counter_ready and not toad.is_throw_controlled(), "E preserves the stored throw during gold")
	lan.reset_after_map_fall(Vector2(TOAD.ARENA_LEFT - 60.0, TOAD.ORIGIN.y))
	lan.facing_direction = -1.0
	for i in 170:
		await physics_frame
		if not toad.blocks_boss_throw(): break
	toad._sling_spear_rain(FIGHT_AT + Vector2(42, -145))
	toad._enter_hammer(TOAD.Hammer.LIFT)
	var hp := toad.combat_stats.health
	await press_interact()
	check(toad.is_throw_controlled() and toad.defense_credit == 0 and toad.hammer == TOAD.Hammer.REST,
		"real E at range while facing away interrupts the windup and clears the beads")
	check(toad._hazards.any(func(hazard) -> bool: return is_instance_valid(hazard) and hazard.kind == ATTACK.Kind.STAKE),
		"an interrupted hammer leaves already released spears in the arena")
	for i in 145:
		await physics_frame
		if not toad.is_throw_controlled(): break
	check(toad.combat_stats.health == hp - LanPlayer.SPECIAL_ATTACK_MAX_DAMAGE,
		"the shared throw damages the toad once and releases it")
	toad.reset_attempt()
	check(toad.defense_credit == 0 and not toad.boss_counter_enabled(), "retry clears the meter and HUD")


func test_ground_spear_red_counter() -> void:
	await start_attempt(BattleAssistSettingsService.Difficulty.HARD)
	toad._fly = false
	toad._fracture_slam = false
	toad._released = true
	toad._enter_hammer(TOAD.Hammer.LIFT)
	var saw_red := false
	var pressed := false
	var hp := toad.combat_stats.health
	for i in 122:
		await physics_frame
		Input.action_release(&"parry")
		if toad._danger_flash.visible and toad._danger_flash.kind == &"red" and toad._danger_flash.frame >= 29 and not saw_red:
			saw_red = toad._danger_flash.global_position.is_equal_approx(toad._rig.head_at())
			await capture("03_red_ground_spear")
		for hazard in toad._hazards:
			if is_instance_valid(hazard) and hazard.kind == ATTACK.Kind.SPIKE and not pressed and hazard.age >= 0.04:
				pressed = true
				Input.action_press(&"parry")
				break
		if lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS: break
	check(saw_red and lan.red_parry_source == toad and toad.red_parry_hold and toad.defense_credit == 1,
		"the red spear counters the actual boss and credits exactly one bead")
	for i in 115: await physics_frame
	check(toad.combat_stats.health < hp and not toad.red_parry_hold \
		and lan.global_position.x < TOAD.ORIGIN.x + TOAD.BODY_SOLID.position.x,
		"the counter lands on the body and Lan remains on the near side of the passage")


func press_interact() -> void:
	Input.action_press(&"interact")
	for i in 3: await physics_frame
	Input.action_release(&"interact")


func capture(name: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
