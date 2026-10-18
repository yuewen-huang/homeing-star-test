extends SceneTree
class MemorySave extends SaveProgressService:
	var fail_write := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_write
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var field: SaltFieldPrototype
var save: MemorySave
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",label_)
func enter() -> void:
	field = load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
func advance(seconds: float) -> void:
	for i in ceili(seconds*60): field.crab_encounter.step(1.0/60)
func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label_+".png"))
func run() -> void:
	seed(20261018)
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	save._config.set_value("map_states","chapter_2_salt_field",{"boss_pile":1,"dug":[]})
	enter()
	field.feet = field.piles[1].ground_position+Vector2(0,42)
	field._sync_view(0)
	field.target = 1
	field._finish_dig()
	var encounter = field.crab_encounter
	var player: LanPlayer = field.pawn.player
	var crab: CrystalCrabBoss = encounter.crab
	check(encounter.active and encounter.entering and not crab.visible,"Real excavation triggers underground entrance")
	check(player.get_parent()==encounter.battle_root and player.input_frozen and not player.is_physics_processing(),"Existing Lan transferred safely from planar control")
	advance(1.8)
	check(crab.current_clip==&"burrow_END" and crab.visible and crab.source_frame>=23,"Entrance plays authored emergence only")
	check(is_equal_approx(player.position.y,crab.position.y),"Player pulled onto boss baseline")
	check(signf(crab.position.x-player.position.x)==player.facing_direction and signf(player.position.x-crab.position.x)==crab.direction,"Both actors face each other on entrance")
	check(crab.attack_hitbox.attack==null,"Entrance cannot damage Lan")
	await capture("salt_crab_emergence")
	advance(0.7)
	check(not encounter.entering and player.is_physics_processing() and not player.input_frozen and not crab.manual_control,"Entrance enables actual autonomous fight and player physics")
	check(player.hurtbox.monitorable and player.hurtbox.collision_layer==4,"Production damage receiver restored")
	player.set_physics_process(false)
	crab.set_physics_process(false)
	Input.action_press(&"jump")
	player._physics_process(1.0/60)
	Input.action_release(&"jump")
	check(player.position.y<encounter.baseline,"Real jump input leaves the explicit baseline")
	player.reset_after_map_fall(encounter.pull_to)
	Input.action_press(&"ui_down")
	player._physics_process(1.0/60)
	Input.action_release(&"ui_down")
	check(player.animated_sprite.animation==&"crouch","Production crouch restored")
	player.reset_after_map_fall(encounter.pull_to)
	crab.start_quake(&"double",player.position)
	crab._physics_process(0.45)
	await capture("salt_crab_warning")
	crab._physics_process(0.25)
	await capture("salt_crab_combat")
	crab._physics_process(1.4)
	await capture("salt_crab_recovery")
	# Death clears the old boss, preserves discovery, and re-enters after respawn.
	field._respawn_after_worm()
	await process_frame
	encounter = field.crab_encounter
	crab = encounter.crab
	check(encounter.active and encounter.entering and crab.combat_stats.health==300,"Death retries with a fresh boss and intact discovery")
	advance(2.5)
	player.set_physics_process(false)
	crab.set_physics_process(false)
	save.fail_write = true
	player.reset_after_map_fall(crab.position+Vector2(150,0))
	crab.combat_stats.health = 1
	player.perform_special_attack(-1,1.0)
	var killing_effect: Node = player.timeline_attack_effect
	player.animated_sprite.pause()
	killing_effect.set_timeline_frame(10)
	await physics_frame
	await physics_frame
	await process_frame
	check(crab.combat_stats.health==0,"Real special attack hitbox kills crab")
	check(not is_instance_valid(killing_effect) or killing_effect.is_queued_for_deletion() or killing_effect.detached_from_source,"Victory does not leave an attached undriven special effect")
	check(crab.peaceful and not encounter.active and encounter.pending_victory,"Defeat pacifies immediately even if persistence fails")
	check(player.get_parent()==field.pawn and not player.is_physics_processing() and not player.hurtbox.monitorable,"Victory returns to planar exploration")
	check(crab.attack_hitbox.attack==null and not crab.is_in_group("damageable"),"Peaceful crab has no attacks and is not targetable")
	var start := crab.position
	crab.set_physics_process(true)
	advance(4)
	check(crab.position.distance_to(start)>10 and crab.rhythm==null,"Defeated crab wanders without attacking")
	check(not save.has_completed(encounter.VICTORY),"Failed save does not claim persistent completion")
	save.fail_write = false
	advance(1.1)
	check(save.has_completed(encounter.VICTORY) and not encounter.pending_victory,"Victory save retries successfully")
	await capture("salt_crab_peaceful")
	field.free()
	current_scene = null
	enter()
	check(field.crab_encounter.crab.peaceful and not field.crab_encounter.active,"Reentry restores peaceful crab without entrance or refight")
	var resident: CrystalCrabBoss = field.crab_encounter.crab
	resident.start_action(&"walk",resident.position+Vector2(100,0))
	resident.receive_hit(99,resident.position)
	check(resident.combat_stats.health==300 and resident.invulnerable,"Reentered resident stays invulnerable while walking")
	field.free()
	current_scene = null
	save._config.set_value("progress","chapter_2_salt_crab_defeated",false)
	enter()
	await process_frame
	advance(2.5)
	encounter = field.crab_encounter
	crab = encounter.crab
	player = field.pawn.player
	player.set_physics_process(false)
	crab.set_physics_process(false)
	player.reset_after_map_fall(crab.position+Vector2(150,0))
	crab.combat_stats.health = 1
	player.perform_special_attack(-1,1.0,crab)
	var max_effect: Node = player.timeline_attack_effect
	player.animated_sprite.pause()
	max_effect.set_timeline_frame(10)
	await physics_frame
	await physics_frame
	await process_frame
	check(crab.combat_stats.health==0 and not encounter.active,"Real enhanced special attack hitbox finishes encounter")
	check(not is_instance_valid(max_effect) or max_effect.is_queued_for_deletion() or max_effect.detached_from_source,"Enhanced wolf effect cannot freeze on Lan after victory")
	await create_timer(0.4).timeout
	check(not is_instance_valid(max_effect) and player.active_attack_effects.is_empty(),"Victory releases the killing effect and its tracking references")
	await capture("salt_crab_special_kill_clean")
	field.free()
	current_scene = null
	await process_frame
	print("SALT CRAB ENCOUNTER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
