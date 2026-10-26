extends SceneTree
class MemorySave extends SaveProgressService:
	var fail_writes := false
	func load_progress() -> void:
		_loaded = true
		_config = ConfigFile.new()
	func save_progress() -> bool: return not fail_writes
	func is_ability_unlocked(_id: StringName) -> bool: return true

var room
var deer: DeerBoss
var save: MemorySave
var failures := 0
var checks := 0
var output := ""
var saved: PackedByteArray

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick() -> void:
	deer._physics_process(1.0 / 60.0)
	deer.vfx._process(1.0 / 60.0)
func until(predicate: Callable, limit := 2400) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick()
	return bool(predicate.call())
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.clear_body_reaction(deer.animated_sprite)
	feedback.screen_fx.clear()
	feedback._reset_punch()
	await create_timer(0.25).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	saved = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	for region in 4:
		save.try_complete_fact(ForestCoreRelic.victory_id(region))
	check(ForestCoreRelic.absorb_available(save) and ForestCoreRelic.power_mask(save) == Vector4.ZERO, "Victories without pendant retain rewards without fictitious absorption")
	save.claim_unique_reward(ForestCoreRelic.REWARD_ID, ItemCatalog.SPIRIT_PENDANT)
	for region in 4:
		save.fail_writes = true
		check(not ForestCoreRelic.absorb_available(save) and not ForestCoreRelic.has_power(save, region), "Failed essence save does not unlock region %d" % region)
		save.fail_writes = false
		check(save.try_complete_fact(ForestCoreRelic.power_id(region)) and ForestCoreRelic.has_power(save, region), "Independent essence unlocks region %d" % region)
	check(ForestCoreRelic.absorb_available(save) and ForestCoreRelic.power_mask(save) == Vector4.ONE, "Repeated absorption preserves exactly four slots")
	check(ForestCoreRelic.status_text(save).count("已解锁") == 4, "Pendant tooltip names all four unlocked skills")
	var snapshot := save._config.encode_to_text()
	save.load_progress()
	save._config.parse(snapshot)
	check(ForestCoreRelic.power_mask(save) == Vector4.ONE, "Reload retains all four essence skills")
	save.load_progress()
	save.add_item(ItemCatalog.VINE_SNARE)
	check(ForestCoreRelic.has_power(save, 1) and not ForestCoreRelic.has_power(save, 0), "Legacy vine item remains usable without granting unrelated powers")
	save.load_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	deer.vine_test_mode = false
	deer.manual_control = false
	check(not deer.has_vine_snare() and not deer.root_phase.item_available, "Formal encounter does not grant vine or mist skills by default")
	# The development room installs its own isolated progress service.
	var preview_save := root.get_node("SaveProgress") as SaveProgressService
	preview_save.claim_unique_reward(ForestCoreRelic.REWARD_ID, ItemCatalog.SPIRIT_PENDANT)
	preview_save.try_complete_fact(ForestCoreRelic.power_id(2))
	check(deer.root_phase.item_available and not deer.has_core_power(3), "Mist slot alone unlocks the decoy")
	deer.vine_test_mode = true
	deer.manual_control = true
	room.select_combo(5)
	room.play_action(4)
	var wind := deer.wind_ultimate
	check(wind.active and wind.stage == DeerWindUltimate.Stage.GATHER, "Development picker starts the real wind ultimate")
	deer.test_core_powers[3] = false
	check(not wind.plant(), "Missing root essence cannot plant")
	deer.test_core_powers[3] = true
	room.player.air_state = LanPlayer.AirState.FALLING
	check(not wind.plant(), "Airborne planting is rejected")
	room.player.air_state = LanPlayer.AirState.GROUNDED
	check(wind.plant() and not wind.plant(), "Grounded root skill plants exactly one stake")
	tick()
	check(room.player.horizontal_combat_wind() == 0, "Stake's nearby area resists the ultimate wind")
	await capture("wind_gather_root")
	check(RootAnchorArt.frame_at(wind.root_age) == 0, "Planted stake begins on the first native generation cel")
	for index in range(1, 6):
		for i in 6: tick()
		check(RootAnchorArt.frame_at(wind.root_age) == index, "Stake plays native cel %d at its authored 100ms timing" % index)
		await capture("root_anchor_frame_%d" % index)
	var held_root_age := wind.root_age
	wind.advance(0)
	check(wind.root_age == held_root_age, "Paused action time freezes stake animation")
	for i in 6: tick()
	check(RootAnchorArt.frame_at(wind.root_age) == 4, "Standing stake loops back to cel four without replaying generation")
	for i in 6: tick()
	check(RootAnchorArt.frame_at(wind.root_age) == 5, "Standing stake alternates the final two cels")
	check(until(func() -> bool: return wind.stage == DeerWindUltimate.Stage.CUT), "First close pressure strike begins")
	for i in 15: tick()
	await capture("wind_cut")
	check(until(func() -> bool: return wind.stage == DeerWindUltimate.Stage.WARNING), "Exactly three beats lead into gold finisher warning")
	check(wind.beat == 3 and deer.warning_kind == &"gold", "Finisher has distinct gold danger")
	for i in 42: tick()
	await capture("wind_gold_warning")
	check(until(func() -> bool: return deer.state == DeerBoss.State.STAGGER), "Physical charge hits the planted root and staggers the deer")
	check(not wind.active and not wind.root_planted and room.player.combat_winds.is_empty(), "Root counter clears all temporary wind and root state")
	for i in 20: tick()
	await capture("wind_root_counter")
	deer.finish_stagger()
	room.play_action(4)
	deer.test_core_powers[3] = false
	check(until(func() -> bool: return wind.stage == DeerWindUltimate.Stage.CHARGE), "Without root essence the same complete ultimate still plays")
	check(not deer.attack_hitbox.attack.guardable and deer.attack_hitbox.attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER, "Final charge is unguardable and unparryable")
	check(until(func() -> bool: return not wind.active), "Uncountered charge ends with normal recovery")
	room.play_action(4)
	deer._change_state(DeerBoss.State.PHASE_END)
	check(not wind.active and room.player.combat_winds.is_empty(), "Phase interruption cancels the wind source")
	deer.phase = 3
	deer.manual_control = false
	deer.reset_phase()
	deer._phase_age = 10
	deer.combat_stats.health = deer.combat_stats.max_health / 2
	deer._update_approach(0.01)
	check(wind.active and wind.used, "Formal AI starts the ultimate at half health after the current combo")
	wind.cancel()
	deer._recover(0)
	deer._update_approach(0.01)
	check(not wind.active, "Half-health ultimate only triggers once in one attempt")
	deer.manual_control = true
	room.select_combo(4)
	room.play_action(0)
	var vine := deer.vine_phase
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "Human transformation reaches casting state")
	deer.start_vine(&"ultimate")
	var seen := {}
	var waves := 0
	var curtains := 0
	for i in 3000:
		for stampede in vine.stampedes:
			if not seen.has(stampede.get_instance_id()):
				seen[stampede.get_instance_id()] = true
				waves += 1
		for strike in vine.strikes:
			if strike.kind == &"curtain" and not seen.has(strike.get_instance_id()):
				seen[strike.get_instance_id()] = true
				curtains += 1
		if is_instance_valid(vine.god_statue): break
		tick()
	check(waves == 3 and curtains == 2, "Wind shield preserves all three stampede waves and both curtains")
	check(until(func() -> bool: return vine.can_use_wind_shield()), "Shield opens only in the gold-statue warning window")
	deer.test_core_powers[0] = false
	check(not vine.use_wind_shield(), "Missing wind essence cannot raise the shield")
	deer.test_core_powers[0] = true
	room.player.position = Vector2(vine.god_statue.position.x, vine.ground_y)
	check(vine.use_wind_shield() and not vine.use_wind_shield(), "Wind shield activates once per ultimate")
	for i in 30: tick()
	await capture("vine_wind_shield")
	check(until(func() -> bool: return vine._wind_counter_pending), "Shield absorbs the actual statue pulse")
	check(is_instance_valid(vine.god_statue) and vine.ultimate_active, "Counter preserves the statue's native dissolution")
	var hp := deer.combat_stats.health
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.FALL), "After the finale the shield counter knocks the caster down")
	check(deer.combat_stats.health == hp - CombatTuning.DEER_VINE_ULTIMATE_DAMAGE and vine.shield == 0, "Wind counter deals one backlash and breaks vine armour")
	check(not vine.ultimate_active and vine.wind_shield.remaining == 0, "Counter clears shield and ultimate state")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.STAGGER), "Counter opens the grounded damage window")
	await capture("vine_wind_counter")
	# Verify protection against real Lan, whose health and launch are not overridden
	# by the development observer's immunity.
	var observer := deer.combat_target
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = 0
	player.world_max_x = 1280
	player.fallback_ground_y = 555
	room.add_child(player)
	player.set_physics_process(false)
	player.reset_after_map_fall(Vector2(650, 555))
	deer.combat_target = player
	vine.wind_shield.player = player
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	vine._open_ultimate()
	deer.item_cooldown = 0
	vine.god_statue = DeerGodCome.new()
	deer.get_parent().add_child(vine.god_statue)
	vine.god_statue.setup(vine, player.position.x, 0)
	check(vine.use_wind_shield(), "Real player can raise the unlocked shield")
	var health := player.combat_stats.health
	vine.god_statue.step(0.8)
	check(player.air_state == LanPlayer.AirState.GROUNDED, "Shield prevents the real statue launch")
	vine.god_statue.step(1.0)
	check(player.combat_stats.health == health and vine._wind_counter_pending, "Shield prevents real flash damage and records its counter")
	vine.cancel()
	check(vine.wind_shield.remaining == 0 and not vine._wind_counter_pending, "Cancellation removes pending shield protection and backlash")
	deer.combat_target = observer
	vine.wind_shield.player = observer
	player.free()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	check(saved == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "Development and in-memory reward checks never alter player save")
	room.free()
	await process_frame
	current_scene = null
	# Formal-room wiring: no test overrides, actual contextual Q dispatch and retry.
	save.load_progress()
	var arena = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await process_frame
	if arena.story.comic != null: arena.story._close_intro()
	deer = arena.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	arena.player.set_physics_process(false)
	deer.manual_control = true
	deer.phase = 3
	deer.reset_phase()
	arena.player.reset_after_map_fall(Vector2(1200, 555))
	deer.start_mist_hunt()
	arena.refresh_context_item()
	check(arena.player.contextual_special_item == ItemCatalog.ROOT_ANCHOR, "Formal wind phase selects root skill in contextual Q slot")
	arena._on_special_item(ItemCatalog.ROOT_ANCHOR)
	check(not deer.wind_ultimate.root_planted, "Formal Q cannot bypass missing root essence")
	save.claim_unique_reward(ForestCoreRelic.REWARD_ID, ItemCatalog.SPIRIT_PENDANT)
	save.try_complete_fact(ForestCoreRelic.power_id(3))
	arena._on_special_item(ItemCatalog.ROOT_ANCHOR)
	check(deer.wind_ultimate.root_planted, "Formal Q plants after the root slot is unlocked")
	arena._revive()
	check(not deer.wind_ultimate.active and arena.player.combat_winds.is_empty(), "Formal death immediately releases root and wind state")
	await process_frame
	deer.set_physics_process(false)
	deer.phase = 3
	deer.reset_phase()
	check(not deer.wind_ultimate.used, "Retry restores the wind ultimate's once-per-attempt budget")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.position = Vector2(1500, 555)
	arena.player.reset_after_map_fall(Vector2(1200, 555))
	deer.start_mist_hunt()
	arena._on_special_item(ItemCatalog.ROOT_ANCHOR)
	check(until(func() -> bool: return deer.wind_ultimate.stage == DeerWindUltimate.Stage.WARNING), "Rooted formal encounter reaches its terminal warning")
	var before_root_charge: int = arena.player.combat_stats.health
	check(until(func() -> bool: return deer.state == DeerBoss.State.STAGGER), "Formal charge physically hits the root stake")
	check(arena.player.combat_stats.health == before_root_charge, "Stake intercepts the real attack footprint before it can injure the player behind it")
	deer.reset_phase()
	# Real player's dodge still avoids the unguardable finisher without essence.
	save.load_progress()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	deer.position = Vector2(1500, 555)
	arena.player.reset_after_map_fall(Vector2(1200, 555))
	deer.start_mist_hunt()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(until(func() -> bool: return deer.wind_ultimate.stage == DeerWindUltimate.Stage.CHARGE), "Unassisted formal wind hunt reaches its finisher")
	var remaining_hp: int = arena.player.combat_stats.health
	var evades := {"count": 0, "age": 0.0}
	arena.player.dodge_evaded_attack.connect(func(source: Node2D, _duration: float):
		if source == deer:
			evades.count += 1
			evades.age = deer.wind_ultimate.age)
	arena.player.start_back_dodge(1)
	check(until(func() -> bool: return not deer.wind_ultimate.active), "Uncountered formal charge completes without a forced item check")
	check(arena.player.combat_stats.health == remaining_hp, "Actual dodge invulnerability avoids the finisher without root essence")
	check(evades.count == 1 and evades.age < 0.45, "With F9 disabled the actual charge contact is evaded within the dodge window")
	arena.free()
	await process_frame
	print("CORE ESSENCES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
