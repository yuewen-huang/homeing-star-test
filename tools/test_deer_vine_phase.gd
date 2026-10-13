extends SceneTree
## Fourth phase (vine · king of the forest) v0.2 batch 1, on the development dummy:
## transform, instant leaf blink with the authored frames on the navel, triple diagonal
## blink pierce from the staff gem, gold wiper lash, red 落幕 curtain, pincer, parries cracking
## the vine armour, fall, stagger, rise and pace-up, reset back to the deer.
## Design: docs/design/chapter_1_deer_vine_phase_design.md.

var room
var deer: DeerBoss
var vine: DeerVinePhase
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

## Real-time wait for CombatFeedback hit-stop (parries trigger it) before manual simulation resumes.
func wait_hit_stop() -> void:
	while Engine.time_scale < 1.0:
		await process_frame

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale / 60.0
		deer._physics_process(delta)
		room._physics_process(delta)
		deer.vfx._process(delta)

func tick_until(condition: Callable, limit: int) -> int:
	for i in limit:
		if condition.call(): return i
		tick(1)
	return limit

## Ticks with hit-stop waits until the condition holds; returns false on timeout.
func run_until(condition: Callable, limit: int, each := Callable()) -> bool:
	for i in limit:
		if condition.call(): return true
		tick(1)
		if each.is_valid(): each.call()
		await wait_hit_stop()
	return bool(condition.call())

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func strike_of(kind: StringName) -> DeerVineStrike:
	for strike in vine.strikes:
		if strike.kind == kind and not strike.finished: return strike
	return null

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	deer = room.adapter.deer; deer.set_physics_process(false); deer.vfx.set_process(false)
	vine = deer.vine_phase
	room.select_combo(4)
	check(deer.phase == 4 and room.adapter.action_names().size() == 5 and room.deflect_toggle.visible and room.library_picker.visible and room.library_picker.item_count == DeerVinePhase.LIBRARY.size(), "Vine phase exposes five actions, the combo library and the dummy deflect toggle")
	check(not room.item_button.visible, "Vine phase shows no item button beside the fifth action")
	var dummy_x: float = room.dummy.position.x

	# Transform and rise.
	room.play_action(0)
	tick(1)
	check(deer.state == DeerBoss.State.VINE and deer.animated_sprite.animation == &"human_transform_START", "Key 1 starts the transform from the deer")
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 600)
	check(vine.human and vine.step == DeerVinePhase.Step.HOVER, "Transform ends hovering in human form")
	check(is_equal_approx(deer.position.y, 555.0 - DeerVinePhase.PERCH_HEIGHT), "Caster rises to the casting point above where the deer stood")
	check(vine.aura_level() == 1.0, "Pale green aura is at full strength over whole armour")
	for i in 30: await process_frame
	await snapshot("hover")

	# Triple blink pierce without deflection: instant vanish, leaves at the navel, light
	# at the destination navel, body appears when the light ends; three diagonal hits.
	room.dummy.begin_action()
	var start := deer.position
	var start_navel := vine.navel(start)
	room.play_action(1)
	tick(1)
	check(vine.step == DeerVinePhase.Step.BLINK and deer.animated_sprite.modulate.a == 0.0, "Key 2 makes the caster vanish on the next frame")
	check(vine.leaves.size() == 1 and vine.leaves[0].frame == 0 and vine.leaves[0].position == start_navel, "Scatter leaves F00 stay at the caster's navel where it vanished")
	check(start_navel.y < start.y - 150.0 and is_equal_approx(vine.leaves[0].scale.x, 1.4) and vine.leaves[0].offset == -DeerVinePhase.DeerLeafTeleport.CENTER, "Leaves are centred on the navel (%.0f px above the feet) at 1.4 world scale" % (start.y - start_navel.y))
	await snapshot("blink_out")
	tick(int(DeerVinePhase.BLINK_GAP * 60.0))
	var landing := deer.position
	check(is_equal_approx(landing.y, 555.0) and absf(landing.x - dummy_x) >= DeerVinePhase.BLINK_MIN_DISTANCE - 0.5 and absf(landing.x - dummy_x) <= DeerVinePhase.BLINK_MAX_DISTANCE + 0.5, "Ground blink lands beside the target at a random distance (%.0f px away)" % absf(landing.x - dummy_x))
	var distances := {}
	for i in 40: distances[snappedf(absf(vine.blink_destination(&"ground").x - dummy_x), 10.0)] = true
	check(distances.size() >= 10, "Ground blink distances vary (%d distinct in 40 blinks)" % distances.size())
	check(vine.leaves.size() == 2 and vine.leaves.back().frame == 4 and vine.leaves.back().position == vine.navel(landing), "Arrival light F04 plays at the destination navel")
	check(deer.animated_sprite.modulate.a == 0.0, "Caster stays hidden while the arrival light plays")
	check(signf(dummy_x - landing.x) == deer.direction, "Caster faces the target on arrival")
	await snapshot("blink_in")
	var appear := tick_until(func() -> bool: return vine.step != DeerVinePhase.Step.BLINK, 60)
	check(absf((appear + int(DeerVinePhase.BLINK_GAP * 60.0) + 1) / 60.0 - vine.blink_duration()) < 0.04 and vine.blink_duration() < 0.3, "Fast blink takes %.2f s in total" % vine.blink_duration())
	check(vine.step == DeerVinePhase.Step.CAST and deer.animated_sprite.modulate.a == 1.0, "Body appears at once and casts immediately")
	check(vine.leaves.size() == 2 and vine.leaves[0].frame < 3 and vine.leaves[0].duration() > vine.blink_duration() * 2.0, "Scatter leaves are still dissipating slowly after the caster reappears (%.2f s)" % vine.leaves[0].duration())
	var pierce := strike_of(&"pierce")
	var gem := deer.global_position + deer._anchor_offset(DeerVinePhase.PIERCE_RELEASE_CLIP, 1, "staff")
	check(pierce != null and pierce.origin.distance_to(gem) < 1.0 and pierce.origin.y < 555.0 - 200.0, "Pierce starts at the staff gem on the release frame")
	var aim := Vector2(dummy_x, 555.0 - DeerVinePhase.AIM_HEIGHT)
	check(pierce.aim_direction.y > 0.4 and absf(pierce.target.distance_to(aim) - DeerVineStrike.PIERCE_OVERSHOOT) < 0.5, "Pierce aims diagonally down and its fully grown vine ends %.0f px past the target" % DeerVineStrike.PIERCE_OVERSHOOT)
	check(pierce._sprite.texture == DeerVineStrike.PIERCE_TEXTURE and is_equal_approx(pierce._sprite.scale.y, 1.4) and is_equal_approx(pierce._sprite.scale.x, 1.4 * pierce.stretch) and pierce._sprite.position == pierce.origin, "Painted vine keeps its 1.4 thickness and is stretched ×%.2f along its length" % pierce.stretch)
	check(pierce._circle.texture == DeerVineStrike.PIERCE_CIRCLE_TEXTURE and pierce._circle.scale == Vector2.ONE * 1.4 and pierce._circle.position == pierce.origin, "Magic circle stays at 1.4 scale on the staff gem")
	for far in [250.0, 700.0]:
		var probe := vine.spawn_strike(&"pierce", deer.position.x + deer.direction * far, deer.position.x, 0.3, pierce.origin)
		var far_aim := Vector2(deer.position.x + deer.direction * far, 555.0 - DeerVinePhase.AIM_HEIGHT)
		check(absf(probe.target.distance_to(far_aim) - DeerVineStrike.PIERCE_OVERSHOOT) < 0.5, "A target %.0f px away also gets a vine that ends just past it (×%.2f)" % [far, probe.stretch])
		vine.strikes.erase(probe)
		probe.queue_free()
	check(is_equal_approx(pierce._sprite.rotation, pierce.aim_direction.angle() - (PI if pierce.aim_direction.x < 0.0 else 0.0)), "Painted vine is turned toward the target")
	check(pierce.warn < 0.35, "Pierce wind-up is short (%.2f s)" % pierce.warn)
	await snapshot("pierce_warning")
	# Lambdas capture locals by value: record into a shared dictionary.
	var seen := {"red": false, "sides": {}}
	var watch := func() -> void:
		if deer.vfx.red_warning.visible and vine.current_cast() == &"pierce_red": seen.red = true
		if vine.step == DeerVinePhase.Step.CAST and absf(deer.position.y - 555.0) < 1.0:
			seen.sides[vine._step_index] = signf(deer.position.x - dummy_x)
	watch.call()
	tick_until(func() -> bool: return pierce.pierce_frame() >= 7, 120)
	var tip: Array = pierce.capsules()[0]
	check(is_equal_approx(tip[0].distance_to(tip[1]), 291.0 * 1.4 * pierce.stretch), "Damage reach follows the stretched painted frame F07 (%.0f px)" % tip[0].distance_to(tip[1]))
	await snapshot("pierce_active")
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 900, watch)
	var damages: Array = room.dummy.contacts.map(func(contact: Dictionary) -> int: return contact.damage)
	check(damages == [12, 12, 18], "Unparried triple pierce hits the dummy 12, 12, then 18 (got %s)" % [damages])
	var sides: Array = seen.sides.values()
	check(seen.red, "Third pierce shows the red flash before it is sent")
	check(sides.size() == 3 and sides[0] != sides[1] and sides[1] != sides[2], "Successive blinks alternate sides of the target %s" % [sides])
	check(is_equal_approx(deer.position.y, 555.0 - DeerVinePhase.PERCH_HEIGHT) and vine.perch == deer.position, "Sequence ends with a blink back to an aerial casting point")
	check(vine.shield == DeerVinePhase.SHIELD_MAX, "Vines that are not parried leave the armour intact")

	# Gold slam: a vine rises upright behind the target, coils back and slams flat over it.
	room.deflect_toggle.button_pressed = true
	room.dummy.begin_action()
	room.select_combo_library(DeerVinePhase.LIBRARY.find(&"ground_lash"))
	room.play_action(4)
	var lash := strike_of(&"ground_lash")
	var toward := signf(dummy_x - lash.origin.x)
	check(lash != null and lash.danger() == CombatAttackData.DangerType.UNPARRYABLE_DANGER and absf(absf(dummy_x - lash.origin.x) - 200.0) < 1.0 and toward == lash.side, "Slam vine roots 200 px behind the target on the caster's side and is gold")
	check(absf(lash.warn - vine.release_time()) < 0.001, "Slam warning lasts the whole wind-up (%.3f s)" % lash.warn)
	check(DeerVineLashArt.frames().size() == DeerVineLashArt.frame_count() and DeerVineLashArt.frames()[0].get_size() == Vector2(DeerVineLashArt.SIZE), "Procedural slam frames are generated once and cached (%d frames)" % DeerVineLashArt.frame_count())
	await snapshot("slam_warning")
	tick_until(func() -> bool: return lash.lash_frame() == 3, 120)
	var upright: Array = lash.capsules().back()
	check(upright[1].y < 555.0 - 400.0 and absf(upright[1].x - lash.origin.x) < 60.0, "Vine stands straight up out of the ground")
	await snapshot("slam_rise")
	tick_until(func() -> bool: return lash.lash_frame() == 5, 120)
	var coiled: Array = lash.capsules().back()
	check(signf(coiled[1].x - lash.origin.x) == -toward, "Vine coils back away from the target before the slam")
	await snapshot("slam_coil")
	tick_until(func() -> bool: return lash.lash_frame() == 7, 120)
	await snapshot("slam_swing")
	var shakes := {"n": 0}
	tick_until(func() -> bool: return lash.lash_frame() == DeerVineLashArt.impact_frame(), 120)
	var flat: Array = lash.capsules().back()
	check(signf(flat[1].x - lash.origin.x) == toward and flat[1].y > 555.0 - 40.0 and lash._debris.size() > 0, "Vine slams flat onto the floor over the target and throws soil")
	await snapshot("slam_impact")
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER and vine.strikes.is_empty(), 300)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 15 and vine.shield == 3, "Gold slam strikes the dummy once for 15 and is never parried")

	# 落幕: a dense red curtain across the screen, counter-parried for two cracks.
	room.dummy.begin_action()
	room.play_action(3)
	var curtain := strike_of(&"curtain")
	var gaps := []
	for i in curtain.columns.size() - 1: gaps.append(absf(curtain.columns[i + 1] - curtain.columns[i]) - 2.0 * float(DeerVineStrike.KINDS[&"curtain"].radius))
	check(curtain != null and curtain.columns.size() >= 30 and gaps.max() < 14.0, "Curtain hangs %d vines with gaps narrower than the player" % curtain.columns.size())
	var span: float = absf(curtain.columns.back() - curtain.columns[0])
	check(span >= 1200.0 and dummy_x > minf(curtain.columns[0], curtain.columns.back()) and dummy_x < maxf(curtain.columns[0], curtain.columns.back()), "Curtain spans %.0f px over the target" % span)
	check(signf(curtain.columns.back() - curtain.columns[0]) == signf(dummy_x - deer.position.x), "Curtain cascades from the caster's side")
	tick_until(func() -> bool: return deer.vfx.red_warning.visible, 60)
	check(deer.vfx.red_warning.visible and not curtain.is_active(), "Curtain shows the red flash before it drops")
	await snapshot("curtain_warning")
	tick_until(func() -> bool: return curtain.capsules().size() > curtain.columns.size() / 2, 120)
	await snapshot("curtain_falling")
	await run_until(func() -> bool: return curtain.snapped, 120)
	check(curtain.snapped and vine.shield == 1, "Counter-parried curtain snaps and cracks two armour arcs")
	await snapshot("curtain_snapped")
	check(is_equal_approx(vine.aura_level(), 1.0 / 3.0), "Aura dims by one band per cracked arc")
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER and vine.strikes.is_empty(), 300)
	check(room.dummy.contacts.is_empty(), "Parried curtain does not damage the dummy")

	# Parried pierce breaks the last arc: fall, stagger, rise.
	room.play_action(1)
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.FALL, 600)
	check(vine.step == DeerVinePhase.Step.FALL and vine.shield == 0 and vine.strikes.all(func(strike: DeerVineStrike) -> bool: return strike.snapped), "First parried pierce breaks the last arc, cancels the sequence and drops the caster")
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.STAGGER, 120)
	check(is_equal_approx(deer.position.y, 555.0) and deer.poise_broken and deer.animated_sprite.modulate.a == 1.0, "Caster lies on the ground with poise broken (MAX special window)")
	await snapshot("stagger")
	var stagger_ticks := tick_until(func() -> bool: return vine.step != DeerVinePhase.Step.STAGGER, 600)
	check(absf(stagger_ticks / 60.0 - DeerVinePhase.STAGGER_TIME) < 0.05, "Ground stagger lasts %.2f s" % (stagger_ticks / 60.0))
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 240)
	check(vine.shield == DeerVinePhase.SHIELD_MAX and vine.cycle == 1 and is_equal_approx(vine.pace(), 1.15) and not deer.poise_broken, "Caster rises with full armour and the next cycle is 15% faster")
	check(is_equal_approx(deer.position.y, 555.0 - DeerVinePhase.PERCH_HEIGHT), "Rise returns to casting height")

	# Pincer: the curtain is cast as the wiper is released, so both are out together.
	room.deflect_toggle.button_pressed = false
	room.select_combo_library(DeerVinePhase.LIBRARY.find(&"pincer"))
	room.play_action(4)
	var ground := strike_of(&"ground_lash")
	tick_until(func() -> bool: return strike_of(&"curtain") != null, 120)
	var both := strike_of(&"curtain")
	check(both != null and ground.warn - ground._age < 0.02, "Pincer casts the curtain as the wiper is released")
	var wiper_done := tick_until(func() -> bool: return not ground.is_active(), 120)
	var curtain_on := tick_until(func() -> bool: return both.is_active(), 120)
	check(curtain_on <= 15, "Curtain drops %.2f s after the wiper sweep ends" % (curtain_on / 60.0))
	await snapshot("pincer")
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER and vine.strikes.is_empty(), 300)

	# Quarter speed keeps the vines on the action clock.
	room.play_action(3)
	var slow := strike_of(&"curtain")
	var age := slow._age
	for i in 12: deer._physics_process(0.25 / 60.0)
	check(is_equal_approx(slow._age - age, 0.05), "Vine strikes advance on the quarter-speed action clock")

	# Reset returns to the deer on the ground.
	room.reset_room()
	deer = room.adapter.deer; deer.set_physics_process(false); deer.vfx.set_process(false); vine = deer.vine_phase
	check(not vine.human and vine.strikes.is_empty() and vine.leaves.is_empty() and is_equal_approx(deer.position.y, 555.0), "Reset rebuilds the deer on the ground with no vines or leaves left")

	var after := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	check(after == saved, "Vine preview leaves saved progress unchanged")
	print("VINE PHASE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
