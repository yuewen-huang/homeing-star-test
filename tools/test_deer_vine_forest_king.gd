extends SceneTree
## Vine phase v0.2 batches 2–3 on the development dummy: deer-spirit stampede and its
## red king, treant summon (user's walk / cast sheets) with small root spikes, the four
## wind fields (push / pull / gust / downdraft with the player's jump block), and the
## ultimate 万鹿朝王 (centre blink, darkness, centre pull, three waves, curtains, giant
## painted gold god finale: rise, green pulse, dissolution and dust). Reset clears all.
## Design: docs/design/chapter_1_deer_vine_phase_design.md.

var room
var deer: DeerBoss
var vine: DeerVinePhase
var player: LanPlayer
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

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

func run_until(condition: Callable, limit: int) -> bool:
	for i in limit:
		if condition.call(): return true
		tick(1)
		await wait_hit_stop()
	return bool(condition.call())

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func play_library(id: StringName) -> void:
	room.select_combo_library(DeerVinePhase.LIBRARY.find(id))
	room.play_action(4)

func hover() -> void:
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 1200)

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
	player = room.player
	room.select_combo(4)
	var dummy_x: float = room.dummy.position.x
	room.play_action(0)
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 600)
	check(room.adapter.action_names()[2].begins_with("鹿群冲刺") and room.library_picker.item_count == DeerVinePhase.LIBRARY.size(), "Key 3 is the stampede and key 5 plays the selected combo")

	# Stampede, unparried: four spirits and a red king from the caster's side, each hits once.
	room.dummy.begin_action()
	room.play_action(2)
	var stampede: DeerStagStampede = vine.stampedes[0]
	var direction := signf(dummy_x - deer.position.x)
	check(stampede.plan.size() == 5 and stampede.plan.back().king and stampede.plan.all(func(s: Dictionary) -> bool: return s.direction == direction), "Stampede plans four spirits and a king running from the caster's side")
	check(absf(stampede.warn - vine.release_time()) < 0.001 and stampede.warn > 0.7, "Entrance is warned for the whole wind-up (%.2f s)" % stampede.warn)
	tick(20)
	await snapshot("stampede_warning")
	tick_until(func() -> bool: return stampede.phantoms.size() >= 2, 240)
	var first: DeerStagStampede.DeerStagPhantom = stampede.phantoms[0]
	check(first.danger() == CombatAttackData.DangerType.NORMAL and not first.king and first._sprite.modulate.a < 1.0, "Spirits are translucent parryable deer")
	await snapshot("stampede_running")
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER and vine.stampedes.is_empty(), 900)
	var damages: Array = room.dummy.contacts.map(func(c: Dictionary) -> int: return c.damage)
	check(damages == [10, 10, 10, 10, 22], "Each spirit hits once for 10 and the king for 22 (got %s)" % [damages])
	check(vine.step == DeerVinePhase.Step.HOVER and vine.shield == 3, "Caster channels until the last spirit has run, then hovers")

	# Stampede, parried: spirits shatter; the counter-parried king cracks two arcs.
	room.deflect_toggle.button_pressed = true
	room.dummy.begin_action()
	room.play_action(2)
	stampede = vine.stampedes[0]
	var shattered := {"n": 0}
	stampede.phantom_parried.connect(func(_p) -> void: shattered.n += 1)
	await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER and vine.stampedes.is_empty(), 900)
	check(shattered.n == 5 and room.dummy.contacts.is_empty(), "All five spirits are parried and none reaches the dummy")
	check(vine.shield == 1, "Counter-parried king cracks two armour arcs")
	room.deflect_toggle.button_pressed = false

	# Treants: two painted treants beside the target, cast animation spikes, a kill cracks one arc.
	vine.shield = DeerVinePhase.SHIELD_MAX
	play_library(&"summon")
	tick_until(func() -> bool: return not vine.treants.is_empty(), 120)
	check(vine.treants.size() == 2, "Summon raises two treants")
	var xs: Array = vine.treants.map(func(t: DeerVineTreant) -> float: return t.position.x)
	check(absf(xs[0] - dummy_x + DeerVinePhase.TREANT_SPREAD) < 1.0 and absf(xs[1] - dummy_x - DeerVinePhase.TREANT_SPREAD) < 1.0, "Treants rise %d px on both sides of the target" % DeerVinePhase.TREANT_SPREAD)
	var treant: DeerVineTreant = vine.treants[0]
	check(treant.get_node("Hurtbox").is_in_group(&"hurtbox") and treant.is_in_group(&"damageable"), "Treant is damageable")
	check(treant._sprite.texture == DeerVineTreant.WALK_TEXTURE and treant._sprite.hframes == 4 and treant._sprite.vframes == 4 and is_equal_approx(treant._sprite.scale.x, 1.4), "Treant uses the painted walk sheet at 1.4 world scale")
	check(treant._sprite.flip_h == (player.position.x > treant.position.x), "Treant faces the player (sheet faces left, mirrored when the player is to the right)")
	var start_x := treant.position.x
	tick(int(DeerVineTreant.FIRST_CAST * 60.0) + 2)
	check(treant.cast_age >= 0.0 and treant._sprite.texture == DeerVineTreant.CAST_TEXTURE and treant.casts == 0, "Treant starts its painted cast animation at %.1f s" % DeerVineTreant.FIRST_CAST)
	await snapshot("treant_cast")
	tick(int(float(DeerVineTreant.CAST_RELEASE) / DeerVineTreant.CAST_FPS * 60.0) + 1)
	check(signf(treant.position.x - start_x) == signf(player.position.x - start_x) or absf(player.position.x - treant.position.x) <= DeerVineTreant.KEEP_DISTANCE, "Treant walks toward the player")
	check(treant.casts == 1 and treant.volleys.size() == 1, "Spikes start when both arms reach out (cast frame F%02d)" % DeerVineTreant.CAST_RELEASE)
	var volley: RootSpikeVolley = treant.volleys[0]
	check(volley._spikes.size() == 3 and volley.attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER and volley.attack.health_damage == 8, "Volley is three small gold spikes for 8")
	await snapshot("treants")
	var before := vine.shield
	for i in 3:
		treant.receive_hit(10, treant.global_position)
		await wait_hit_stop()
	check(treant.dead and vine.shield == before - 1 and not is_instance_valid(volley) or volley.is_queued_for_deletion(), "Killing a treant cracks one arc and removes its spikes")
	await run_until(func() -> bool: return vine.treants.size() == 1, 60)
	check(vine.treants.size() == 1, "Dead treant fades out and leaves the field")
	play_library(&"summon")
	tick_until(func() -> bool: return vine.treants.size() > 1, 120)
	play_library(&"summon")
	tick_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 240)
	check(vine.treants.size() == DeerVinePhase.TREANT_MAX, "Never more than %d treants (have %d)" % [DeerVinePhase.TREANT_MAX, vine.treants.size()])
	await hover()

	# Winds: push away from the caster, pull toward it, gust flips, downdraft blocks jumping.
	var away := signf(player.position.x - deer.position.x)
	play_library(&"wind_push")
	tick_until(func() -> bool: return vine.wind != null, 120)
	check(is_equal_approx(player.horizontal_combat_wind(), DeerVineWind.SPEED * away), "Headwind pushes the player away from the caster (%.0f px/s)" % player.horizontal_combat_wind())
	await snapshot("wind_push")
	await hover()
	away = signf(player.position.x - deer.position.x)
	play_library(&"wind_pull")
	tick_until(func() -> bool: return vine.wind != null and vine.wind.mode == &"pull", 120)
	check(is_equal_approx(player.horizontal_combat_wind(), -DeerVineWind.SPEED * away), "Tailwind draws the player toward the caster")
	await hover()
	play_library(&"wind_gust")
	tick_until(func() -> bool: return vine.wind != null and vine.wind.mode == &"gust", 120)
	var gust := player.horizontal_combat_wind()
	tick(int(DeerVineWind.GUST_PERIOD * 60.0) + 1)
	check(is_equal_approx(player.horizontal_combat_wind(), -gust), "Gust flips direction every %.1f s" % DeerVineWind.GUST_PERIOD)
	await hover()
	play_library(&"wind_down")
	tick_until(func() -> bool: return vine.wind != null and vine.wind.mode == &"down", 120)
	check(player.is_jump_blocked() and is_zero_approx(player.horizontal_combat_wind()), "Downdraft blocks jumping without pushing sideways")
	await snapshot("wind_down")
	var down: DeerVineWind = vine.wind
	tick(int(DeerVineWind.DURATION * 60.0) + 2)
	check(not player.is_jump_blocked() and is_zero_approx(player.horizontal_combat_wind()), "Wind ends after %.0f s and releases the player" % DeerVineWind.DURATION)
	tick(int(DeerVineWind.FADE * 60.0) + 2)
	check(vine.wind == null and not is_instance_valid(down) or down.is_queued_for_deletion(), "Wind leaves fade out and the field is removed")
	await hover()

	# Entire opening remains intact; only the final red antler becomes a gold god.
	room.deflect_toggle.button_pressed = true
	vine.shield = DeerVinePhase.SHIELD_MAX
	var health := deer.combat_stats.health
	play_library(&"ultimate")
	await run_until(func() -> bool: return vine.ultimate_active, 120)
	check(is_equal_approx(deer.position.x, (deer.world_min_x + deer.world_max_x) * 0.5) and vine._darkness.target == 1.0 and vine.wind.mode == &"center", "Ultimate still centres, darkens the arena and pulls inward")
	var seen := {"waves": 0, "curtains": 0, "kings": 0}
	for i in 3000:
		for ultimate_wave in vine.stampedes:
			if not seen.has(ultimate_wave.get_instance_id()):
				seen[ultimate_wave.get_instance_id()] = true
				seen.waves += 1
				seen.kings += ultimate_wave.plan.filter(func(p: Dictionary) -> bool: return p.king).size()
		for strike in vine.strikes:
			if not seen.has(strike.get_instance_id()):
				seen[strike.get_instance_id()] = true
				if strike.kind == &"curtain": seen.curtains += 1
		if is_instance_valid(vine.god_statue): break
		tick(1)
		await wait_hit_stop()
	check(seen.waves == 3 and seen.kings == 0 and seen.curtains == 2, "All three spirit waves and both curtains remain")
	var god := vine.god_statue
	check(is_instance_valid(god) and god.danger() == CombatAttackData.DangerType.UNPARRYABLE_DANGER and not god.parryable(), "Finale is a gold painted god statue that cannot be parried")
	check(await run_until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER, 1200), "Caster waits for rise, pulse, native dissolution and dust to finish")
	check(deer.combat_stats.health == health and vine.shield == DeerVinePhase.SHIELD_MAX, "Auto-parry cannot counter the gold finale or break ultimate armour")
	check(not vine.ultimate_active and vine._darkness.target == 0 and vine.wind == null and vine.god_statue == null, "Ultimate closes with no lingering statue, darkness or pull")
	check(vine.ultimate_used, "Ultimate is marked used for this fight")

	# Reset clears treants, wind, spirits, darkness and the player's wind and jump block.
	play_library(&"wind_down")
	tick_until(func() -> bool: return vine.wind != null and player.is_jump_blocked(), 120)
	room.reset_room()
	deer = room.adapter.deer; deer.set_physics_process(false); deer.vfx.set_process(false); vine = deer.vine_phase
	await process_frame
	check(vine.treants.is_empty() and vine.stampedes.is_empty() and vine.wind == null and not player.is_jump_blocked() and is_zero_approx(player.horizontal_combat_wind()), "Reset clears treants, spirits, wind and releases the player")

	var after := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	check(after == saved, "Forest-king preview leaves saved progress unchanged")
	print("FOREST KING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
