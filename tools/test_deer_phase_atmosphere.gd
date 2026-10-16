extends SceneTree
## Presentation clocks and cleanup must never create attacks or change geometry.

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)

func run() -> void:
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	var field := deer.vfx.phase_atmosphere
	var material := deer.animated_sprite.material as ShaderMaterial
	var source_scale := deer.animated_sprite.scale
	var source_position := deer.animated_sprite.position
	var health: int = deer.combat_stats.health
	var player_health: int = room.player.combat_stats.health
	for phase in [1,2,3]:
		deer.phase = phase
		deer.vfx.reset_effects()
		for i in 180: deer.vfx._process(1.0/60.0)
		check(field.phase == phase and not field.particles.is_empty(), "Phase %d has live distinct atmosphere" % phase)
		check(field.particles.size() <= field.MAX_PARTICLES, "Phase %d particle count is bounded" % phase)
		check(int(material.get_shader_parameter("atmosphere_phase")) == phase, "Phase %d body accents match phase" % phase)
		check(material.get_shader_parameter("phase_color") == deer.phase_color(), "Phase %d established chest colour unchanged" % phase)
		check(deer.attack_hitbox.attack == null and deer.combat_stats.health == health and room.player.combat_stats.health == player_health, "Atmosphere has no combat side effects")
		var before := field.particles.duplicate(true)
		var clock := field.clock
		deer.red_parry_hold = true
		deer.vfx._process(0.5)
		check(field.particles == before and is_equal_approx(field.clock,clock), "Parry pause freezes particle position and life")
		deer.red_parry_hold = false
		deer._dodge_remaining = 1.0
		deer.vfx._process(0.1)
		check(is_equal_approx(field.clock-clock,0.018), "Dodge slow motion advances atmosphere on action time")
		deer._dodge_remaining = 0.0
	check(deer.animated_sprite.scale == source_scale and deer.animated_sprite.position == source_position, "Body scale and pivot remain unchanged")
	check(field.z_index < SideviewLayers.NPC and field._front.z_index < SideviewLayers.PLAYER, "Atmosphere stays below actor/player and chest cue layers")
	deer.phase = 2
	deer.vfx._process(0.0)
	check(field.phase == 2 and field.particles.is_empty(), "Phase handoff clears previous particles even at zero delta")
	deer.vfx._process(0.5)
	deer.vfx.reset_effects()
	check(field.particles.is_empty() and field.clock == 0.0, "Retry/action preview reset clears atmosphere immediately")
	deer.phase = 4
	deer.vfx._process(0.5)
	check(field.phase == 0 and field.particles.is_empty() and float(material.get_shader_parameter("atmosphere_strength")) == 0.0, "Fourth phase stays outside deer-form atmosphere")
	deer.phase = 1
	deer.vfx._process(0.5)
	deer.animated_sprite.modulate.a = 0.0
	deer.vfx._process(0.0)
	check(field.particles.is_empty(), "Hidden body leaves no atmospheric silhouette")
	deer.animated_sprite.modulate.a = 1.0
	deer.vfx._process(0.5)
	deer.state = DeerBoss.State.COMPLETE
	deer.vfx._process(0.0)
	check(field.particles.is_empty() and float(material.get_shader_parameter("atmosphere_strength")) == 0.0, "Defeat clears particles and accents")
	room.reset_room()
	await process_frame
	await process_frame
	check(not is_instance_valid(field), "Development room reset frees atmosphere subtree")
	room.free()
	print("PHASE ATMOSPHERE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
