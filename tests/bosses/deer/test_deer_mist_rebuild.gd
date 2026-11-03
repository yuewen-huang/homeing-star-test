extends "../../support/harness.gd"
var deer: DeerBoss
var lan: LanPlayer
func tick(seconds: float) -> void:
	for i in ceili(seconds*120):
		deer._physics_process(1.0/120)
		deer.vfx._process(1.0/120)
		lan.combat_clock += 1.0/120

func reset() -> void:
	deer.phase = 1
	deer.reset_phase()
	deer.manual_control = true
	deer.short_stun_remaining = 0
	lan.reset_after_map_fall(Vector2(1100,555))
	lan.input_frozen = false
	lan.set_physics_process(false)
	deer.position = Vector2(1500,555)

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	deer = room.adapter.deer
	lan = room.player
	room.set_physics_process(false)
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	reset()
	deer.start_mist_hunt()
	var types := {}
	var elapsed := 0.0
	while deer._hunt_active and elapsed < 12:
		if deer.state == DeerBoss.State.HUNT_WARNING:
			types[deer._hunt_round] = deer.mist_hunt_danger()
			lan.position.y = 300 # Ordinary jump clearance, no special power.
		tick(1.0/120)
		elapsed += 1.0/120
	check(types.values() == [0,1,2], "Hunt progresses from normal to red to gold instead of four gold rushes")
	check(not deer._hunt_active and deer.state == DeerBoss.State.RECOVER and deer._recovery >= 1.8, "No-item hunt ends in a reachable punish window")
	check(deer.attack_hitbox.attack == null, "Recovery has no lingering attack")
	reset()
	deer.start_mist_hunt()
	deer._hunt_round = 1
	deer._start_hunt_round()
	deer.manual_control = false
	tick(.7)
	check(deer.vfx.red_warning.visible and deer.vfx.red_warning.modulate.a == 1, "Red chest warning remains opaque despite mist concealment")
	deer.manual_control = true
	var red := CombatAttackData.new(&"mist_red",deer,18,3,0,0,CombatAttackData.DangerType.COUNTERABLE_DANGER)
	deer.on_attack_parried(red, deer.position)
	check(not deer._hunt_active and deer.state == DeerBoss.State.RECOVER, "Successful red counter cancels the remaining hunt")
	reset()
	deer.start_mist_hunt(true)
	check(deer.use_vine_snare() and not deer.snared, "Q plants a trap without remotely cancelling the warning")
	var planted: Vector2 = deer.mist_phase.trap_position
	lan.position.x += 250
	tick(1.8)
	check(deer.snared and deer.state == DeerBoss.State.STAGGER, "Committed rush crossing the planted position triggers the painted cage")
	check(deer.mist_phase.trap_remaining == 0 and deer.attack_hitbox.attack == null, "Trap is consumed and capture clears all contact")
	check(planted.distance_to(lan.global_position) > 150, "Trap stays planted when Lan moves away")
	reset()
	check(deer.use_vine_snare(), "Trap may be prepared before an attack")
	tick(3.6)
	check(not deer.snared and deer.mist_phase.trap_remaining == 0, "Uncrossed trap expires without granting a stun")
	reset()
	deer.combat_stats.apply_poise_damage(42)
	var damaged := deer.combat_stats.poise
	deer.start_mist_hunt()
	lan.position.y = 300
	tick(4)
	check(deer.combat_stats.poise == damaged, "Mist hunt does not erase earned poise damage")
	reset()
	deer._rng.seed = 44
	var previous := &""
	var moves := {}
	for i in 12:
		deer._end_hunt()
		deer.mist_phase.choose(180)
		check(deer.mist_phase.last_move != previous, "AI alternates attack families")
		previous = deer.mist_phase.last_move
		moves[previous] = true
	check(moves.size() == 3, "Production selector uses steps, charge and mist ambush")
	reset()
	deer.start_combo(&"mist_steps")
	var contacts := {}
	for i in 360:
		tick(1.0/120)
		if deer.attack_hitbox.attack != null: contacts[deer.attack_hitbox.attack.attack_id] = deer.attack_hitbox.attack.danger_type
	check(contacts.size() == 2 and contacts.values().all(func(v): return v == 0), "Opening close combo has two independently parryable stomps")
	deer.vfx.charge_wake(deer.position,deer.direction,"mist_dash")
	var effect := deer.vfx._painted_rush
	var texture_id := effect.front.texture.get_instance_id()
	for i in 120: effect.update_image(DeerPaintedArt.loop_time("mist_dash",i/60.0))
	check(effect.front.texture.get_instance_id() == texture_id and effect._atlases.size() == 2, "Painted animation reuses its two atlas resources across every frame")
	deer.vfx.clear_attacks()
	var pooled_ids := {}
	for quake in deer.vfx._stomp_pool: pooled_ids[quake.get_instance_id()] = true
	for i in 12:
		deer.vfx._stomp_quake(deer.position, i % 3 == 0)
		check(pooled_ids.has(deer.vfx._stomp_quakes[0].get_instance_id()), "Repeated ground impacts reuse a warmed mesh instance")
		deer.vfx.clear_attacks()
	check(deer.vfx._stomp_pool.size() == 3, "The warm ground-effect pool stays bounded after cancellation")
	deer._end_hunt()
	reset()
	check(deer.use_vine_snare(), "Trap can be planted before phase completion")
	deer._on_health_depleted()
	check(deer.mist_phase.trap_remaining == 0, "Phase completion clears planted trap immediately")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("DEER MIST REBUILD")
