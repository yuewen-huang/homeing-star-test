extends SceneTree
## Real production rooms and defense settlement, isolated from the user's progress.
class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	func show_toast(_message: String) -> void: pass

const ROOMS := ["wind_boss", "special_boss_upper_right", "special_boss_lower_left", "root_heart"]
var room: Chapter1BossRoom
var core: RegionalCoreBoss
var battle: RegionalCoreBattle
var progress: LocalProgress
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func select(region: int) -> void:
	if is_instance_valid(room):
		current_scene = null
		room.free()
	progress._config = ConfigFile.new()
	room = load("res://scenes/sideview/chapter_1_%s_room.tscn" % ROOMS[region]).instantiate()
	root.add_child(room)
	current_scene = room
	core = room.regional_core
	battle = core.battle
	core.set_physics_process(false)
	room.player.set_physics_process(false)
	await process_frame
	check(core.region == region and battle.automatic, "Production room instantiates autonomous core %d" % region)
	check(not room.get_node("CoreVisual").visible and room.core_shield == core.shield, "Actual boss replaces static body and owns one shield")

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60): core._physics_process(1.0 / 60.0)

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	Engine.time_scale = 1.0
	await create_timer(0.35, true, false, true).timeout
	core.shield.step(0.5)
	(root.get_node("CombatFeedback") as CombatFeedbackService).screen_fx.clear()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Render " + label)

func unlock() -> void:
	for id: StringName in RegionalCoreProtection.CONDITIONS[core.region]: progress.set_stele_state(id, 2)

func ring_at_player() -> RegionalCoreRing:
	var ring := battle.spawn_ring(room.player.global_position + Vector2(0, -42), 1, Color.WHITE)
	ring.age = RegionalCoreRing.WARNING
	return ring

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var snapshot := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	progress = LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var old_invincible := assist.player_invincible
	var old_difficulty := assist.difficulty
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	for region in 4:
		await select(region)
		var hp := core.combat_stats.health
		var poise := core.combat_stats.poise
		core.receive_hit(1, room.player.global_position)
		core.receive_skill_hit(SkillHitContext.new(&"test", 40), room.player.global_position)
		check(core.combat_stats.health == hp and core.combat_stats.poise == poise, "Both shields block health and poise damage")
		advance(3.1)
		check(battle.normal_count == 1, "Shielded core emits ordinary ring at three seconds")
		advance(3.0)
		check(battle.normal_count == 2, "Ordinary cadence stays independent of the regional skill")
		battle.automatic = false
		battle.random_rings = false
		battle.interrupt_attacks()
		core._parry_pause = 0
		core.red_parry_hold = false
		var ring := ring_at_player()
		room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
		ring.step(0.01)
		check(ring.resolved and ring.finished and core.combat_stats.poise == poise and not core.poise_broken, "Protected ring can be parried without breaking core shield")
		unlock()
		core._parry_pause = 0
		core.red_parry_hold = false
		poise = core.combat_stats.poise
		ring = ring_at_player()
		room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
		ring.step(0.01)
		check(core.combat_stats.poise == poise - 25, "Unprotected ring parry drains shared core poise")
		if region == 0:
			core._parry_pause = 0
			ring = ring_at_player()
			ring.attack.danger_type = CombatAttackData.DangerType.COUNTERABLE_DANGER
			room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
			ring.step(0.01)
			check(core.poise_broken and core.red_parry_hold, "Red phantom contact uses shared core stagger and red hold")
			room.player.red_parry_finished.emit(core)
			check(not core.red_parry_hold, "Player red animation completion releases caster hold")
			core._parry_pause = 0
			advance(2.2)
			check(not core.poise_broken, "Core recovers from red counter without a stuck timer")
		core._parry_pause = 0
		room.player.finish_defense()
		room.player.combat_stats.restore_health()
		var player_hp := room.player.combat_stats.health
		ring = ring_at_player()
		ring.step(0.01)
		ring.step(0.01)
		check(room.player.combat_stats.health == player_hp - 10 and ring.resolved, "Normal ring settles exactly one damage contact")
		room.player.finish_defense()
		room.player.combat_stats.restore_health()
		room.player.start_back_dodge(1)
		room.player.animated_sprite.frame = 2
		ring = ring_at_player()
		ring.step(0.01)
		check(ring.resolved and room.player.combat_stats.health == room.player.combat_stats.max_health, "Ring can be evaded with the player's real dodge frames")
		room.player.reset_after_map_fall(room.get_node("Entry").position)
		room.player.dodge_bullet_time_remaining = 0
		core._parry_pause = 0
		core._dodge_remaining = 0
		battle.interrupt_attacks()
		battle._prune_finished()
		var showing := battle.spawn_normal_ring()
		check(showing.global_position == core.animated_sprite.global_position, "Wave originates at boss body centre")
		showing.preview_only = true
		await capture("core_%d_ring_warning" % region)
		showing.step(0.80)
		check(showing.radius > 700 and showing.global_position == core.animated_sprite.global_position, "Wave rapidly expands without moving its centre")
		await capture("core_%d_ring_active" % region)
		showing.step(0.15)
		await capture("core_%d_ring_screen" % region)
		var passed := Rect2(showing.global_position - Vector2(20, 20), Vector2(40, 40))
		check(not showing.intersects_wave(passed), "Passed interior is hollow and no longer deals damage")
		var far := Rect2(showing.global_position + Vector2(showing.max_radius - 70, -20), Vector2(40, 40))
		showing.step(0.6)
		check(showing.intersects_wave(far) and showing.finished, "Swept ring reaches far screen edge without tunnelling on a large step")
		showing.finish()
		await capture("core_%d_ring_recovery" % region)
		var before := battle.clock
		core._parry_pause = 1.0
		core._physics_process(0.1)
		check(is_equal_approx(battle.clock, before), "Regional timers freeze on shared action pause")
		core._parry_pause = 0
		match region:
			RegionalCoreBoss.Region.MIST: await mist_checks()
			RegionalCoreBoss.Region.ROOT: await root_checks()
			RegionalCoreBoss.Region.WIND: await wind_checks()
			RegionalCoreBoss.Region.VINE: await vine_checks()
		battle.cancel()
		await process_frame
		check(not room.player.is_combat_anchored() and room.player.combat_winds.is_empty(), "Encounter cancellation releases captures and wind")
		check(battle.hazards.is_empty() and battle.spikes.is_empty() and battle.nodules.is_empty() and battle.vines.is_empty(), "Cancellation clears all registered attack/terrain collections")
	await select(RegionalCoreBoss.Region.ROOT)
	unlock()
	battle.spawn_nodules()
	var previous: WeakRef = weakref(core)
	room._revive()
	check(not battle.running, "Player death stops attacks synchronously before deferred retry")
	await process_frame
	await process_frame
	check(previous.get_ref() == null and room.regional_core.combat_stats.health == 300 and room.regional_core.battle.running, "Retry rebuilds core and timers without stale summon references")
	core = room.regional_core
	battle = core.battle
	core.set_physics_process(false)
	core.combat_stats.apply_health_damage(300)
	check(not battle.running and not core.shield.visible, "Core defeat stops combat and hides shield")
	current_scene = null
	room.free()
	await process_frame
	await preview_checks()
	progress.free()
	root.add_child(original)
	assist.player_invincible = old_invincible
	assist.set_difficulty(old_difficulty)
	check(snapshot == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "Production, preview and retry tests preserve user save bytes")
	print("REGIONAL CORE ENCOUNTERS: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func mist_checks() -> void:
	battle.trigger_skill(0)
	battle.fog.set_process(false)
	battle.fog.clear_radius = 90.0
	battle.fog.density = 0.98
	battle.fog.update_material()
	room.player.reset_after_map_fall(Vector2(640, 555))
	var frog := battle.spawn_frog()
	frog.preview_only = true
	frog.side = 1
	frog.position = Vector2(280, 555)
	frog._process(0)
	check(frog.fog == battle.fog and frog.z_index == SideviewLayers.NPC and frog.modulate.a == 0, "Frog body and warning are fully hidden behind the live mist")
	await capture("mist_frog_hidden_warning")
	frog.step(0.64)
	frog.step(0.02)
	check(frog.position.x > 280 and frog.modulate.a == 0, "Frog keeps charging while fully hidden in the mist")
	await capture("mist_frog_hidden_charge")
	frog.position = Vector2(500, 555)
	frog.step(0.02)
	check(frog.modulate.a > 0 and frog.modulate.a < 1, "Moving frog fades in only through the mist's soft visibility boundary")
	await capture("mist_frog_boundary")
	frog.position = Vector2(640, 555)
	frog._process(0)
	check(is_equal_approx(frog.modulate.a, 1.0), "Frog is fully visible in Lan's clear disk")
	await capture("mist_frog_clear_active")
	room.player.global_position.x = 1000
	frog._process(0)
	check(frog.modulate.a == 0, "Moving Lan away hides the frog even with its action clock paused")
	await capture("mist_frog_hidden_active")
	frog.position = Vector2(1200, 555)
	frog.side = -1
	frog.step(0.1)
	check(frog.position.x < 1200 and frog.modulate.a > 0 and frog.modulate.a < 1, "Right-origin frog uses the same mist visibility boundary")
	frog.finish()
	check(not frog.visible and not frog.warning_audio.playing and frog.hitbox.attack == null, "Finished frog clears body, warning sound and damage")
	await capture("mist_frog_recovery")
	battle._prune_finished()
	room.player.reset_after_map_fall(Vector2(640, 555))
	advance(1.6)
	check(is_instance_valid(battle.fog) and battle.hazards.any(func(h): return h is RegionalMistSummon and h.kind == RegionalMistSummon.Kind.FROG), "Fog summons frog rushes")
	await capture("mist_frog_rush")
	advance(6.0)
	check(not is_instance_valid(battle.fog) and not battle.hazards.any(func(h): return h is RegionalMistSummon and h.kind == RegionalMistSummon.Kind.FROG), "Fog skill leaves no frog in room")
	var phantom := battle.spawn_phantom()
	check((phantom.sprite.scale * DeerActionLibrary.frame_size(phantom.current_clip)).is_equal_approx(Vector2(256,256) * 1.4 * 0.8) and phantom.sprite.modulate.a < 1 and phantom.current_clip == &"idle_ING", "Mist phantom preserves its smaller logical size with native edited deer pixels")
	phantom.preview_only = true
	battle.preview_only = true
	battle.preview_target = Vector2(640, 555)
	advance(1.0)
	check(phantom.current_clip == &"thrust_START", "Phantom begins first-three-phases horn thrust")
	await capture("mist_phantom_warning")
	advance(0.42)
	check(phantom.phantom_attacks >= 1 and phantom.current_clip == &"thrust_ING" and battle.hazards.any(func(h): return h is RegionalPhantomSpell and not h.contact_shapes.is_empty()), "Phantom horn art and physical contact share active frames")
	await capture("mist_phantom_thrust")
	advance(0.4)
	check(phantom.current_clip == &"thrust_END", "Horn thrust completes authored recovery")
	await capture("mist_phantom_recovery")
	battle.preview_only = false
	advance(7.6)
	check(not is_instance_valid(phantom) or phantom.finished, "Phantom expires and cannot persist after skill")
	# Exercise the actual physical horn attack, including the shared defenses.
	room.player.reset_after_map_fall(Vector2(640, 555))
	room.player.combat_stats.restore_health()
	core._parry_pause = 0
	core._dodge_remaining = 0
	phantom = battle.spawn_phantom()
	phantom.step(0.82)
	var locked := phantom.locked_x
	room.player.global_position.x = 950
	phantom.step(0.1)
	check(phantom.locked_x == locked and phantom.facing == -1, "Deer horn thrust commits target and facing during startup")
	phantom.finish()
	battle._prune_finished()
	room.player.reset_after_map_fall(Vector2(640, 555))
	phantom = battle.spawn_phantom()
	phantom.step(0.82)
	phantom.step(0.6)
	var strike: RegionalPhantomSpell = battle.hazards.back()
	var hp := room.player.combat_stats.health
	strike.step(0.01)
	strike.step(0.01)
	check(strike.resolved and room.player.combat_stats.health == hp - 12, "Deer phantom horn deals one ordinary damage contact")
	phantom.finish()
	strike.finish()
	room.player.combat_stats.restore_health()
	room.player.finish_defense()
	phantom = battle.spawn_phantom()
	phantom.step(0.82)
	phantom.step(0.6)
	strike = battle.hazards.back()
	room.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var poise := core.combat_stats.poise
	strike.step(0.01)
	check(strike.finished and core.combat_stats.poise == poise - 25, "Deer phantom horn parry drains the owning core's poise")
	room.player.finish_defense()
	core._parry_pause = 0

func root_checks() -> void:
	battle.spawn_nodules()
	check(not battle.nodules.is_empty(), "Root skill creates random destructible nodules")
	var nodule := battle.nodules[0]
	for i in 5: nodule.receive_hit(1, room.player.global_position)
	check(not nodule.broken and nodule.health == 8, "Five sword hits leave stronger core nodule alive")
	nodule.receive_hit(1, room.player.global_position)
	check(nodule.broken, "Sixth contact destroys nodule without triggering explosion")
	battle._prune_finished()
	var trigger := battle.nodules[1]
	room.player.reset_after_map_fall(trigger.position)
	room.player.air_state = LanPlayer.AirState.GROUNDED
	battle.rng.seed = 5
	for i in 32:
		trigger._was_on = false
		trigger._trigger_cooldown = 0
		trigger.step(0.001)
		if trigger.eruptions > 0: break
	check(trigger.stage == 0 and trigger.eruptions > 0, "Stepping on original-colored nodule can randomly summon spikes")
	var eruptions := trigger.eruptions
	trigger.age = 4.1
	for i in 32:
		trigger._was_on = false
		trigger._trigger_cooldown = 0
		trigger.step(0.001)
		if trigger.eruptions > eruptions: break
	check(trigger.stage == 1 and trigger.eruptions > eruptions, "Yellow nodule retains random step-triggered spikes")
	room.player.reset_after_map_fall(Vector2(1100, 555))
	nodule = battle.nodules[0]
	nodule.step(4.1)
	check(nodule.stage == 1, "Nodule transitions from authored color to yellow")
	await capture("root_nodule_yellow")
	nodule.step(4.0)
	check(nodule.stage == 2, "Nodule transitions from yellow to red")
	await capture("root_nodule_red")
	room.player.reset_after_map_fall(nodule.position + Vector2(0, -20))
	nodule.step(0.01)
	check(nodule.broken and battle.hazards.any(func(h): return h is RegionalCoreBlast), "Stepping on red nodule triggers immediate explosion")
	var blast: RegionalCoreBlast = battle.hazards.back()
	blast.preview_only = true
	blast.step(0.15)
	check(blast.sprite.texture == RegionalCoreBlast.TEXTURE and blast.sprite.frame == 2, "Root explosion samples approved VFX3 frames on action clock")
	await capture("root_nodule_explosion")
	blast.step(0.2)
	await capture("root_nodule_explosion_recovery")
	blast.step(0.2)
	check(blast.finished, "VFX3 completes all seven frames then clears")
	room.player.reset_after_map_fall(Vector2(640, 555))
	battle.spawn_spikes([room.player.position.x])
	advance(0.85)
	check(not battle.spikes.is_empty() and not battle.spikes.back().active_rects().is_empty(), "Root spike skill uses active painted footprint after warning")
	await capture("root_spikes_active")
	var timed: RegionalRootNodule = battle.nodules.back()
	timed.step(11.1)
	check(timed.broken, "Untouched root nodule eventually detonates on its timer")

func wind_checks() -> void:
	battle.start_gust(-1)
	advance(1.0)
	check(is_instance_valid(battle.wall) and room.player.horizontal_combat_wind() < 0, "Left wind pushes toward left thorn wall")
	await capture("wind_left_thorns")
	battle.start_gust(1)
	advance(1.0)
	check(not is_instance_valid(battle.wall) and room.player.horizontal_combat_wind() > 0, "Right wind removes left wall and pushes toward pulsing core")
	check(is_instance_valid(battle.purple_aura) and battle.purple_aura.get_parent() == core.animated_sprite, "Right wind emits strong purple smoke from the whole breathing body")
	check(not battle.purple_body_contact(Rect2(Vector2(400, 200), Vector2(40, 80))), "Purple smoke does not damage empty screen space")
	room.player.reset_after_map_fall(core.position + Vector2(-60, 0))
	var hp := room.player.combat_stats.health
	advance(0.05)
	check(room.player.combat_stats.health < hp, "Purple core contact during right wind damages player")
	await capture("wind_right_purple")
	advance(0.15)
	await capture("wind_right_purple_motion")
	battle._end_gust()
	check(not is_instance_valid(battle.purple_aura), "Ending gust removes body aura immediately")
	room.player.reset_after_map_fall(Vector2(500, 555))
	battle.random_rings = true
	battle.extra_remaining = 0.01
	advance(3.5)
	check(battle.extra_count >= 2, "Extra random ring cadence runs permanently alongside baseline")
	var first := battle.spawn_normal_ring(true)
	var second := battle.spawn_normal_ring(true)
	check(first != second and first.attack.attack_id != second.attack.attack_id and first.position == second.position, "Overlapping rings retain separate attack IDs and settlement")
	await capture("wind_overlapping_rings")

func vine_checks() -> void:
	check(battle.vines.size() == 3, "Vine fight has exactly three permanent binding vines")
	var vine := battle.vines[0]
	var hp := vine.combat_stats.health
	var tip := vine.tip
	for i in 4: vine.receive_hit(1, room.player.global_position)
	check(vine.combat_stats.health == hp and vine.poise_broken, "Binding vines are health-immune but sword hits break poise")
	vine.step(1.0)
	check(vine.tip == tip, "Poise break freezes the actual vine tip")
	await capture("vine_broken")
	vine.step(3.2)
	check(not vine.poise_broken and vine.combat_stats.poise == vine.combat_stats.max_poise, "Poise recovery returns vine to swinging binding state")
	var captor := battle.vines[0]
	for other in battle.vines: other.next_attack = INF
	room.player.reset_after_map_fall(Vector2(640, 555))
	room.player.start_back_dodge(1)
	captor.begin_attack()
	for i in 90: captor.step(1.0 / 60.0)
	check(not room.player.is_combat_anchored(), "Real roll invulnerability evades binding grab")
	room.player.reset_after_map_fall(Vector2(640, 555))
	room.player.dodge_bullet_time_remaining = 0
	captor._dodge_remaining = 0
	captor.begin_attack()
	for i in 75: captor.step(1.0 / 60.0)
	check(room.player.combat_anchor_owner == captor, "Undodged binding strike actually captures player")
	room.player.release_combat_anchor(captor)
	battle._handled_captor = null
	for other in battle.vines: other._stop_attack()
	for other in battle.vines:
		other.response = false
		other.role = VineCombatEnemy.Role.REEL
	var skipped := battle.vines[2]
	for i in 4: skipped.receive_hit(1, room.player.global_position)
	room.player.bind_combat_anchor(captor, room.player.position.x)
	captor._enter(VineCombatEnemy.State.PULL)
	battle._on_grabbed(captor)
	check(battle.vines[1].response and battle.vines[1].role == VineCombatEnemy.Role.PIERCE and skipped.poise_broken and not skipped.response, "Only unbroken other vines join capture retaliation")
	room.player.release_combat_anchor(captor)
	advance(2.1)
	check(not battle.vines[1].response and battle.vines[1].role == VineCombatEnemy.Role.REEL, "Partner makes one attack then restores binding role")
	skipped.step(4.2)
	room.player.bind_combat_anchor(captor, room.player.position.x)
	captor._enter(VineCombatEnemy.State.PULL)
	battle._on_grabbed(captor)
	check(battle.vines[1].role == VineCombatEnemy.Role.PIERCE and battle.vines[2].role == VineCombatEnemy.Role.SLASH, "Two healthy partners become pierce and slash respectively")
	await capture("vine_capture_combo_warning")
	advance(1.0)
	await capture("vine_capture_combo_active")
	captor.combat_stats.restore_poise()
	for i in 4: captor.receive_hit(1, room.player.global_position)
	check(not room.player.is_combat_anchored(), "Breaking captor releases player immediately")

func preview_checks() -> void:
	var preview: Node2D = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	preview.player.set_physics_process(false)
	for region in 4:
		preview.select_boss(4 + region)
		var specimen: RegionalCoreBoss = preview.adapter.boss
		specimen.set_physics_process(false)
		var hp: int = preview.player.combat_stats.health
		for i in 240: specimen._physics_process(1.0 / 60.0)
		check(specimen.battle.normal_count == 0 and specimen.battle.skill_count == 0, "Development core does not choose attacks autonomously")
		preview.play_action(0)
		for i in 90:
			specimen._physics_process(1.0 / 60.0)
			preview._physics_process(1.0 / 60.0)
		preview.play_action(1)
		for i in 90:
			specimen._physics_process(1.0 / 60.0)
			preview._physics_process(1.0 / 60.0)
		if region == RegionalCoreBoss.Region.VINE:
			check(specimen.battle.vines.size() == 3 and not preview.player.is_combat_anchored(), "Capture retaliation previews against dummy without grabbing observer")
		preview.play_action(2)
		for i in 180:
			specimen._physics_process(1.0 / 60.0)
			preview._physics_process(1.0 / 60.0)
		check(preview.dummy.contacts.size() == 1, "Development ring uses real single-contact dummy probe")
		check(preview.player.combat_stats.health == hp and not preview.player.is_combat_anchored(), "Preview attacks leave observer unharmed and unbound")
		preview.reset_room()
		await process_frame
		check(preview.player.combat_winds.is_empty(), "Specimen reset clears wind sources")
	current_scene = null
	preview.free()
	await process_frame
