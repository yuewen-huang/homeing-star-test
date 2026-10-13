extends SceneTree
## Fourth phase (vine · magic duel), batch 1, on the development dummy:
## transform scale, rise to the casting point, spells locking onto the dummy,
## dummy hits, simulated parry returning spells, shield cracks, fall, stagger,
## rise and pace-up, red warning on the heavy bolt, reset back to the deer.
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

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

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
	check(deer.phase == 4 and room.adapter.action_names().size() == 4 and room.deflect_toggle.visible, "Vine phase exposes four actions and the dummy deflect toggle")

	# Transform and rise.
	room.play_action(0)
	tick(1)
	check(deer.state == DeerBoss.State.VINE and deer.animated_sprite.animation == &"human_transform_START", "Key 1 starts the transform from the deer")
	check(is_equal_approx(deer.animated_sprite.scale.x, 1.4 * 1.26), "Transform starts at the deer's in-game size")
	await snapshot("transform_start")
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 600)
	check(vine.human and vine.step == DeerVinePhase.Step.HOVER, "Transform ends hovering in human form")
	check(is_equal_approx(deer.position.y, 555.0 - DeerVinePhase.PERCH_HEIGHT), "Caster rises to the casting point above where the deer stood")
	check(deer.animated_sprite.animation == &"human_idle_ING" and is_equal_approx(deer.animated_sprite.scale.x, 1.4), "Human form hovers at 1.0× drawing scale")
	check(vine.aura_level() == 1.0, "Pale green aura is at full strength over a whole shield")
	for i in 30: await process_frame
	await snapshot("hover")

	# Without deflection a bolt strikes the dummy once.
	room.dummy.begin_action()
	room.play_action(1)
	var spawned := tick_until(func() -> bool: return not vine.bolts.is_empty(), 120)
	check(spawned < 120 and vine.bolts[0].kind == &"bolt", "Cast releases a bolt")
	if not vine.bolts.is_empty():
		var bolt: DeerSpellBolt = vine.bolts[0]
		var to_target := Vector2(688, 555.0 - DeerVinePhase.AIM_HEIGHT) - bolt.global_position
		check(bolt.velocity.normalized().dot(to_target.normalized()) > 0.99 and bolt.velocity.y > 0, "Bolt flies down toward the dummy's chest height on the ground")
		await snapshot("bolt_flight")
	tick_until(func() -> bool: return vine.bolts.is_empty(), 240)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 12, "Unparried bolt hits the dummy once for 12")
	check(vine.shield == DeerVinePhase.SHIELD_MAX, "A bolt that is not returned leaves the shield intact")

	# Simulated parry returns the bolt and cracks the shield.
	room.deflect_toggle.button_pressed = true
	var health := deer.combat_stats.health
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 120)
	room.play_action(1)
	var reflected := false
	for i in 300:
		tick(1)
		for bolt in vine.bolts: reflected = reflected or bolt.reflected
		await wait_hit_stop()
		if reflected and vine.bolts.is_empty(): break
	check(reflected, "Dummy deflect returns the bolt toward the caster")
	check(deer.combat_stats.health == health - 20 and vine.shield == 2, "Returned bolt deals 20 and cracks one shield arc")
	check(is_equal_approx(vine.aura_level(), 2.0 / 3.0), "Aura dims by one band per cracked arc")

	# Red heavy bolt: red cue before release, worth two cracks, breaks the shield.
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 120)
	room.play_action(2)
	var red_seen := false
	for i in 400:
		tick(1)
		red_seen = red_seen or (deer.vfx.red_warning.visible and vine.bolts.is_empty())
		await wait_hit_stop()
		if vine.step == DeerVinePhase.Step.FALL: break
	check(red_seen, "Heavy bolt shows the red flash before it is thrown")
	check(vine.step == DeerVinePhase.Step.FALL and vine.shield == 0, "Returned heavy bolt breaks the remaining two arcs and drops the caster")
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.STAGGER, 120)
	check(is_equal_approx(deer.position.y, 555.0) and deer.poise_broken and deer.is_poise_broken(), "Caster lands staggered on the ground with poise broken (MAX special window)")
	check(vine.aura_level() == 0.0, "Aura is out while the caster is grounded")
	await snapshot("stagger")
	var stagger_ticks := tick_until(func() -> bool: return vine.step != DeerVinePhase.Step.STAGGER, 600)
	check(absf(stagger_ticks / 60.0 - DeerVinePhase.STAGGER_TIME) < 0.05, "Ground stagger lasts %.2f s" % (stagger_ticks / 60.0))
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 240)
	check(vine.step == DeerVinePhase.Step.HOVER and vine.shield == DeerVinePhase.SHIELD_MAX and vine.cycle == 1 and not deer.poise_broken,
		"Caster rises back with a full shield and the next cycle begins")
	check(is_equal_approx(deer.position.y, 555.0 - DeerVinePhase.PERCH_HEIGHT), "Rise returns to the casting point")

	# Triple bolt: three returned bolts break the shield again.
	room.play_action(3)
	var fired := 0
	var seen := {}
	for i in 600:
		tick(1)
		for bolt in vine.bolts:
			if not seen.has(bolt.get_instance_id()): seen[bolt.get_instance_id()] = true; fired += 1
		await wait_hit_stop()
		if vine.step == DeerVinePhase.Step.FALL: break
	check(fired == 3 and vine.step == DeerVinePhase.Step.FALL, "Triple bolt throws three spells and the third return drops the caster")

	# Reset returns to the deer on the ground.
	room.reset_room()
	deer = room.adapter.deer; deer.set_physics_process(false); deer.vfx.set_process(false); vine = deer.vine_phase
	check(not vine.human and vine.bolts.is_empty() and is_equal_approx(deer.position.y, 555.0), "Reset rebuilds the deer on the ground with no spells left")

	var after := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	check(after == saved, "Vine preview leaves saved progress unchanged")
	print("VINE PHASE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
