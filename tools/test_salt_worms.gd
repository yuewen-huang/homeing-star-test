extends SceneTree
const PROJECTION := preload("res://scripts/sideview/salt_field_projection.gd")
class MemorySave extends SaveProgressService:
	var fail_write := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_write
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var field: SaltFieldPrototype
var save: MemorySave
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func enter() -> void:
	field = load("res://scenes/sideview/chapter_2_salt_field.tscn").instantiate() as SaltFieldPrototype
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
	field.ambient.set_physics_process(false)
func tick(seconds: float, movement := Vector2.ZERO, running := false) -> void:
	for i in ceili(seconds*60): field.step_exploration(1.0/60,movement,false,false,running)
func place(worm, offset: Vector2) -> void:
	field.feet = PROJECTION.unproject(worm.position+offset*worm.scale.x)
	field._sync_view(0)
func dig(id: int) -> void:
	check(save.excavate_salt_pile(id),"Persist excavated pit %d" % id)
	field.piles[id].excavated = true
func reset_worm(worm) -> void:
	worm.age = -1
	worm.cooldown = 0
	worm.player_inside = false
	worm.sprite.hide()
	field.pawn.player.reset_after_map_fall(Vector2.ZERO)
	field.pawn.hit_remaining = 0
	field.dodge_remaining = 0
	field.dodge_cooldown = 0
func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_+".png"))==OK,"Capture "+label_)
func run() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.player_invincible = false
	enter()
	var animal_count: int = field.ambient.get_node("Wildlife").get_child_count()
	check(animal_count==16 and field.ambient.puzzle_slots.size()==3,"Sixteen animals include three nearby puzzle supplies")
	for animal in field.ambient.puzzle_slots:
		check(animal.feet.distance_to(PROJECTION.unproject(field.puzzle_stele.position))<600,"Puzzle supply starts near stele")
	var worm = field.worms.worms[4]
	place(worm,Vector2(49,0))
	field.worms.ambush_chance = 1
	tick(0.05)
	check(worm.attacks==0,"Intact heap never ambushes")
	dig(4)
	field.worms.ambush_chance = 0
	tick(0.05)
	check(worm.attacks==0,"Zero probability rejects the entry")
	field.worms.ambush_chance = 1
	tick(0.05)
	check(worm.attacks==0,"Standing inside cannot reroll a rejected entry every frame")
	place(worm,Vector2(150,0))
	tick(1.0/60)
	place(worm,Vector2(49,0))
	tick(1.0/60)
	check(worm.attacks==1 and worm.age==0,"Leaving and crossing the pit again rolls a new ambush")
	await capture("salt_worm_warning")
	var health: int = field.pawn.player.combat_stats.health
	tick(0.15,Vector2.RIGHT)
	check(field.pawn.player.combat_stats.health==health-worm.DAMAGE,"Walking away from the trigger edge is too slow to evade the fast bite")
	check(field.pawn.hit_remaining>0 and not field.pawn.can_move(),"Bite uses production health and a short planar hit reaction")
	field.pawn.request_attack()
	field.pawn.request_skill(&"instant_dash")
	check(field.pawn.player.attack_state==LanPlayer.AttackState.NONE,"Hit reaction cannot be overwritten by attack or skill input")
	await capture("salt_worm_bite")
	tick(0.15)
	check(field.pawn.player.combat_stats.health==health-worm.DAMAGE,"One emergence cannot deal repeated frame damage")
	tick(0.1)
	await capture("salt_worm_retract")
	tick(3.0)
	check(worm.age<0 and not worm.sprite.visible and field.pawn.can_move(),"Worm retracts and hit reaction releases movement")
	reset_worm(worm)
	place(worm,Vector2(49,0))
	health = field.pawn.player.combat_stats.health
	tick(1.0/60)
	tick(0.16,Vector2.RIGHT,true)
	check(field.pawn.player.combat_stats.health==health,"Immediate running can escape from the trigger edge")
	reset_worm(worm)
	place(worm,Vector2(20,0))
	health = field.pawn.player.combat_stats.health
	field.step_exploration(1.0/60,Vector2.LEFT,false,true)
	tick(0.16)
	check(field.pawn.player.combat_stats.health==health,"Production dodge invulnerability evades the bite")
	reset_worm(worm)
	place(worm,Vector2(20,0))
	field.pawn.player.start_parry()
	field.pawn.player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	health = field.pawn.player.combat_stats.health
	worm.begin_attack()
	worm.step(0.15,1,field.worms.rng,[])
	check(field.pawn.player.combat_stats.health==health and field.pawn.player.defense_state==LanPlayer.DefenseState.PARRY_SUCCESS,"Shared parry contract repels a worm bite")
	reset_worm(worm)
	field.worms.ambush_chance = 0
	field.feet = Vector2(3500,1700)
	var animals: Array = field.ambient.get_node("Wildlife").get_children()
	var snack = animals[1]
	var fed_ids := SaveProgressService.SALT_WORM_PUZZLE_PILES
	for id in fed_ids:
		dig(id)
		var puzzle_worm = field.worms.worms[id]
		check(puzzle_worm.puzzle_worm,"Each of three fixed pits is a puzzle worm")
		reset_worm(puzzle_worm)
		place(puzzle_worm,Vector2(25,0))
		field.worms.step(1.0/60)
		check(puzzle_worm.attacks==1,"Fixed pit always ambushes even when random chance is zero")
		reset_worm(puzzle_worm)
		field.feet = Vector2(3500,1700)
		snack.respawn_at(puzzle_worm.pile.ground_position)
		snack.fleeing = true
		if id==fed_ids[0]:
			save.fail_write = true
			puzzle_worm.step(1.0/60,0,field.worms.rng,animals)
			puzzle_worm.step(0.15,0,field.worms.rng,animals)
			check(not puzzle_worm.fed and snack.visible and save.get_salt_fed_worms().is_empty(),"Failed meal save preserves animal and puzzle progress")
			save.fail_write = false
			reset_worm(puzzle_worm)
		puzzle_worm.step(1.0/60,0,field.worms.rng,animals)
		puzzle_worm.step(0.15,0,field.worms.rng,animals)
		check(puzzle_worm.fed and not snack.visible and save.get_salt_fed_worms().has(id),"A herded animal feeds its own worm and persists distinct progress")
		check(save.feed_salt_worm(id) and puzzle_worm.meals==1,"The same fed worm cannot consume a second animal or duplicate progress")
		puzzle_worm.step(0.5,0,field.worms.rng,animals)
		check(not puzzle_worm.sprite.visible,"Fed worm finishes retracting")
		if id==fed_ids[0]:
			check(save.get_stele_state(&"salt_puzzle_01")!=2,"One meal cannot complete the three-worm puzzle")
			save.fail_write = true
			check(not save.feed_salt_worm(999),"Unrelated pit cannot advance puzzle")
			save.fail_write = false
		field.ambient.respawns.erase(snack)
	check(save.get_stele_state(&"salt_puzzle_01")==2 and field.puzzle_stele.state==MinigameStele.SteleState.COMPLETED,"Third distinct meal completes the real stele")
	field.feet = PROJECTION.unproject(field.puzzle_stele.position)+Vector2(0,65)
	field.exploration_camera_position = field.puzzle_stele.position
	field._sync_view(0)
	await capture("salt_worm_puzzle_completed")
	# Animal is replenished only after its delay, clear of player, intact heaps and pits.
	field.feet = Vector2(3500,1700)
	snack.show()
	field.ambient.consume_critter(snack)
	field.ambient.step(4)
	check(not snack.visible,"Consumed animal does not respawn immediately")
	field.ambient.step(10)
	check(snack.visible and field.ambient.spawn_is_clear(snack,snack.feet),"Delayed refresh produces a safe animal")
	check(field.ambient.get_node("Wildlife").get_child_count()==animal_count,"Refreshing reuses individuals without unbounded population growth")
	# Failure of the final meal must roll back completion in the same transaction.
	var snapshot := save._config.encode_to_text()
	var partial: Dictionary = save._config.get_value("map_states","chapter_2_salt_field")
	partial = partial.duplicate(true)
	partial["fed_worms"] = [2,12]
	save._config.set_value("map_states","chapter_2_salt_field",partial)
	save._config.set_value("steles","salt_puzzle_01",1)
	save.fail_write = true
	check(not save.feed_salt_worm(16) and save.get_salt_fed_worms()==[2,12] and save.get_stele_state(&"salt_puzzle_01")==1,"Final meal save failure rolls back progress and completion together")
	save.fail_write = false
	save._config.parse(snapshot)
	field.free()
	current_scene = null
	enter()
	check(save.get_salt_fed_worms().size()==3 and field.puzzle_stele.state==MinigameStele.SteleState.COMPLETED,"Reload restores completed environmental puzzle")
	for id in fed_ids: check(field.worms.worms[id].fed,"Reloaded fed worm stays peaceful")
	field.pawn.player.combat_stats.apply_health_damage(999)
	await process_frame
	check(field.pawn.player.combat_stats.health>0 and field.feet==field.SPAWN,"Lethal hazard damage restores health at the map entrance")
	field.free()
	current_scene = null
	# Exercise real fleeing/steering into each pit without placing an animal in it.
	partial["fed_worms"] = []
	save._config.set_value("map_states","chapter_2_salt_field",partial)
	save._config.set_value("steles","salt_puzzle_01",1)
	enter()
	field.exploration_camera_position = field.puzzle_stele.position
	if save._toast_panel!=null: save._toast_panel.modulate.a = 0
	var captured_meal := false
	for animal in field.ambient.puzzle_slots:
		# Hold the other animals still so each route proves its own meal.
		field.ambient.respawns.clear()
		for other in field.ambient.get_node("Wildlife").get_children(): other.hide()
		animal.respawn_at(field.ambient.puzzle_slots[animal])
		var nearest_worm
		var nearest_distance := INF
		for id in fed_ids:
			var candidate = field.worms.worms[id]
			var distance: float = candidate.pile.ground_position.distance_to(field.ambient.puzzle_slots[animal])
			if distance<nearest_distance:
				nearest_worm = candidate
				nearest_distance = distance
		var start: Vector2 = animal.feet
		for frame in 1500:
			if nearest_worm.fed: break
			var toward: Vector2 = (nearest_worm.position-PROJECTION.project(animal.feet)).normalized()
			field.feet = PROJECTION.unproject(PROJECTION.project(animal.feet)-toward*95*PROJECTION.depth_scale(animal.feet.y))
			field.step_exploration(1.0/60,Vector2.ZERO,false,false)
			if not captured_meal and nearest_worm.age>0.06 and nearest_worm.age<0.13:
				await capture("salt_worm_feeding")
				captured_meal = true
		check(nearest_worm.fed and start.distance_to(nearest_worm.pile.ground_position)>100,"Actual herding steers %s from its local spawn into a hungry worm" % animal.name)
	check(save.get_stele_state(&"salt_puzzle_01")==2,"Three actual fleeing routes can solve the environmental puzzle")
	field.free()
	current_scene = null
	await process_frame
	print("SALT WORMS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
