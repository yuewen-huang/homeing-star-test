extends "../../support/harness.gd"
## Structural timing regression, not a successful escape claim. A real unlocked
## root power holds a real wall; manual preview then isolates player damage.
var room: Chapter1DeerBossRoom
var deer: Node2D
var lan: LanPlayer
var tornado: Node2D
var meteors: Node2D
var elapsed := 0.0
var leaf_sent := false
var meteor_sent := false

func step() -> void:
	deer._physics_process(1.0/60.0)
	elapsed+=1.0/60.0
	if elapsed>=1.9 and not leaf_sent:
		check(deer.cast_index<0 and deer.opening<=0 and deer.can_schedule_spell(0),"Leaf follow-up respects body completion and independent cooldown")
		deer.start_spell(0)
		leaf_sent=true
	if elapsed>=4.4 and not meteor_sent:
		check(deer.cast_index<0 and deer.opening<=0 and deer.can_schedule_spell(2),"Meteor follow-up respects the two non-leaf slots")
		deer.start_spell(2)
		meteor_sent=true
	for spell in deer.spells:
		if is_instance_valid(spell) and spell.kind=="tornado": tornado=spell
		if is_instance_valid(spell) and spell.kind=="meteors": meteors=spell

func until_tornado(age: float) -> void:
	for frame in 1000:
		if is_instance_valid(tornado) and tornado.age>=age: return
		step()
		await physics_frame
	check(false,"Timed route reached requested tornado age")

func run() -> void:
	var save:=use_memory_progress()
	save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
	save.claim_unique_reward(ForestCoreRelic.REWARD_ID,ItemCatalog.SPIRIT_PENDANT)
	save.try_complete_fact(ForestCoreRelic.power_id(3))
	(root.get_node("SceneTransition") as SceneTransitionService).deer_rematch_requested=true
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro:=WindSightingComic.new()
	var packed:=PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(4)
	room.encounter._spawn_phase(4,900)
	room.encounter.start()
	deer=room.deer
	lan=room.player
	deer.transform_left=0
	deer.invulnerable=false
	deer.wait_left=999
	lan.reset_after_map_fall(Vector2(880,555))
	lan.set_physics_process(false)
	deer.core_power_state.cooldown=0
	deer.core_powers.refresh_hud()
	# Use the actual Q item selection and signal; no fabricated anchor dictionaries.
	Input.action_press(&"special_item_use")
	var item: StringName=lan.read_special_item_input()
	if item!=&"": lan.special_item_use_requested.emit(item)
	Input.action_release(&"special_item_use")
	check(item==ItemCatalog.ROOT_ANCHOR and deer.core_powers.effect_phase==4,"Real Q plants the unlocked root anchor")
	# The remaining assertions concern scheduling/visual clocks, not damage avoidance.
	deer.manual_control=true
	deer.set_physics_process(false)
	lan.position.x=1280
	deer.start_spell(1)
	await until_tornado(3.15)
	var held: Dictionary=tornado.objects[0]
	var free_wall: Dictionary=tornado.objects[1]
	check(deer.core_powers.triggered and held.get("anchor_hold",0.0)>0 and free_wall.get("anchor_hold",0.0)==0,"Only the wall crossing the actual planted anchor is held")
	var held_release: float=tornado.wall_release_time(held)
	var free_release: float=tornado.wall_release_time(free_wall)
	check(absf(held_release-free_release-1.0)<.025,"Future rush time includes both spent delay and remaining anchor hold")
	await until_tornado(free_release-.1)
	check(held.rush_warning is DangerFlash and free_wall.rush_warning is DangerFlash,"Each wall owns its existing shared danger cue")
	check(free_wall.rush_warning.visible and not held.rush_warning.visible,"The unheld rush flashes without prematurely flashing the delayed wall")
	check(absf(free_wall.rush_warning.global_position.x-tornado.tornado_x(free_wall))<1,"A split cue stays at the wall that will actually rush")
	check(is_instance_valid(meteors) and meteors.meteor_retimed and meteors.spawned==0,"Meteors wait before locking a target across the split escape beat")
	var before := {"tornado_age":tornado.age,"meteor_age":meteors.age,"born":meteors.next_meteor_at,
		"x":tornado.tornado_x(free_wall),"frame":free_wall.rush_warning.frame,
		"delay":deer.meteor_birth_delay(.48,.34,.12)}
	deer.action_clock.pause(.50)
	for frame in 12:
		step()
		await physics_frame
	check(tornado.age==before.tornado_age and meteors.age==before.meteor_age and meteors.next_meteor_at==before.born,"Shared pause freezes walls and delayed meteor births")
	check(tornado.tornado_x(free_wall)==before.x and free_wall.rush_warning.frame==before.frame,"Shared pause freezes the actual wall and gold flash phase")
	check(deer.meteor_birth_delay(.48,.34,.12)==before.delay,"Shared pause freezes the protected escape interval")
	deer.action_clock.clear()
	await until_tornado(held_release-.1)
	check(held.rush_warning.visible and not free_wall.rush_warning.visible,"The held wall gets its own later gold flash")
	check(absf(held.rush_warning.global_position.x-tornado.tornado_x(held))<1,"The later cue follows the delayed wall rather than the old centre")
	var actual_hold_end: float=held_release+float(tornado.config.escape_window)+.15
	var delay: float=deer.meteor_birth_delay(.48,.34,.12)
	check(delay>0 and tornado.age+delay+.48>actual_hold_end,"Meteor birth protection extends beyond the delayed wall's full rush")
	while meteors.spawned==0 and tornado.age<9:
		step()
		await physics_frame
	check(meteors.spawned>0,"The delayed volley eventually resumes")
	var first_fall: float=tornado.age-meteors.age+float(meteors.objects[0].born)+float(meteors.spec.charge)
	check(first_fall>actual_hold_end-.001,"The actual first resumed descent begins after both walls' protected beat")
	check(deer.has_pending_spell_threat() and not deer.escape_opening_active(),"Pending unlaunched meteors prevent a premature recovery promise")
	var old_tornado := tornado
	var old_meteors := meteors
	deer.restart_duel()
	await wait_frames(2)
	check(deer.spells.is_empty() and not is_instance_valid(old_tornado) and not is_instance_valid(old_meteors),"Retry removes both wall cues and the delayed volley")
	check(not deer._escape_recovery_pending and not deer.escape_opening_active() and deer.core_powers.effect_phase==0,"Retry clears the anchor and pending recovery state")
	room.encounter.stop()
	current_scene=null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER WIND ANCHOR ESCAPE")
