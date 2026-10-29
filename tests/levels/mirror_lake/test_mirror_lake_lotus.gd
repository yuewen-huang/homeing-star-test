extends SceneTree
class MemoryProgress extends SaveProgressService:
	var reject := false
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not reject
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var failures := 0
var checks := 0
var scene: MirrorLake
var actor: LanPlayer
var lotus: MirrorLakeLotus
var memory: MemoryProgress
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",label)
func key(code: Key,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func side(value: int) -> void:
	if scene.side == value: return
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN+0.1)
	check(scene.request_switch(),"Normal F route changes the lotus phase")
func place(foot: Vector2) -> void:
	actor.position = foot
	actor.velocity = Vector2.ZERO
	actor.air_state = LanPlayer.AirState.GROUNDED
	actor.ground_action_state = LanPlayer.GroundActionState.NONE
	actor.play_idle()
func leave_leaf() -> void:
	place(lotus.position+Vector2(100,0))
	lotus.tick(0.01)
func step_leaf(index: int) -> void:
	leave_leaf()
	place(lotus.position+Vector2(lotus.LEAF_X[index],lotus.DECK_Y))
	lotus.tick(0.01)
func make_scene() -> void:
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	actor = scene.player as LanPlayer
	actor.set_physics_process(false)
	lotus = scene.lotus
func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	memory = MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	make_scene()
	await process_frame
	check(lotus != null and lotus.leaves.size()==4,"Optional lotus pond is installed with four leaf platforms")
	check(lotus.surfaces.size()==4 and not lotus.solved,"Fresh pond starts unsolved with registered low platforms")
	check(lotus.position.x>MirrorLakeInkCarp.PATROL_MAX_X and lotus.position.x<MirrorLake.ZONE_BOSS_START,"Pond is after the carp and before the boss, outside the combat patrol")
	var atlas := lotus.art.get_image()
	check(atlas.get_pixel(0,0).a==0,"Lotus art preserves transparent surroundings")
	lotus.clue_clock = 0.5
	check(lotus.current_clue_leaf()==0,"Yang clue first visits the left leaf")
	lotus.tick(0.01)
	var ripple_at := lotus.clue.position
	lotus.tick(0.20)
	check(lotus.clue.position==ripple_at and ripple_at.x==lotus.LEAF_X[0],"Ripple expands on the current leaf without translating between leaves")
	lotus.tick(lotus.CLUE_BEAT)
	check(lotus.current_clue_leaf()==2,"Yang clue next visits the third leaf")
	lotus.tick(lotus.CLUE_BEAT)
	check(lotus.current_clue_leaf()==1,"Yang clue finishes at the second leaf")
	lotus.tick(lotus.CLUE_BEAT)
	check(lotus.current_clue_leaf()==-1 and not lotus.clue.visible,"A quiet gap separates repeat demonstrations")
	lotus.tick(lotus.CLUE_REST)
	check(lotus.current_clue_leaf()==0,"The clue repeats without an input time limit")
	check(not lotus.red_seal.visible and lotus.red_seal.texture!=null,"Before completion, the only red seal stays hidden as the future reward")
	for i in lotus.ORDER: step_leaf(i)
	check(lotus.step_count==0 and not lotus.solved,"Following leaves on yang cannot solve the puzzle")
	# Walking past below the leaf tops is an optional bypass, even in yin.
	side(MirrorLake.Side.YIN)
	check(not lotus.red_seal.visible and not lotus.clue.visible,"Yin shows no red seals on the leaves and hides the answer ripple")
	for i in lotus.ORDER:
		place(lotus.position+Vector2(lotus.LEAF_X[i],0))
		lotus.tick(0.02)
	check(lotus.step_count==0,"Walking along the water beneath the leaves does not opt into the puzzle")
	# Real physical keys climb onto the first pad under inverted controls.
	place(lotus.position+Vector2(-120,0))
	scene.refresh_controls()
	key(KEY_A,true)
	key(KEY_S,true)
	for i in 50:
		if i==1: key(KEY_S,false)
		actor._physics_process(1.0/60.0)
		lotus.tick(1.0/60.0)
	key(KEY_A,false)
	key(KEY_S,false)
	check(lotus.step_count==1 and absf(actor.position.y-(lotus.position.y+lotus.DECK_Y))<1,
		"A real yin jump lands on the pad and counts a fresh first step")
	lotus.tick(600)
	check(lotus.step_count==1,"Holding a leaf for any duration neither advances nor times out")
	step_leaf(3)
	check(lotus.step_count==0 and not lotus.solved and not lotus.dropped,"Wrong leaf immediately resets only this attempt")
	step_leaf(0)
	check(lotus.step_count==1,"A fresh attempt can begin immediately after a wrong step")
	step_leaf(0)
	check(lotus.step_count==0,"Leaving and re-entering the same wrong next leaf is a distinct input")
	place(lotus.position+Vector2(lotus.LEAF_X[0],lotus.DECK_Y))
	side(MirrorLake.Side.YANG)
	side(MirrorLake.Side.YIN)
	lotus.tick(0.02)
	check(lotus.step_count==0,"Switching phase while already on a leaf cannot manufacture a step")
	leave_leaf()
	place(lotus.position+Vector2(lotus.LEAF_X[0],lotus.DECK_Y-25))
	actor.air_state = LanPlayer.AirState.FALLING
	lotus.tick(0.02)
	check(lotus.step_count==0,"Passing above a seal in midair does not count")
	step_leaf(0)
	side(MirrorLake.Side.YANG)
	check(lotus.step_count==0 and lotus.clue_clock==0,"Returning to yang restarts observation and clears a partial attempt")
	side(MirrorLake.Side.YIN)
	leave_leaf()
	actor.set_input_frozen(true)
	place(lotus.position+Vector2(lotus.LEAF_X[0],lotus.DECK_Y))
	lotus.tick(0.02)
	actor.set_input_frozen(false)
	lotus.tick(0.02)
	check(lotus.step_count==0,"Frozen input does not queue a hidden seal step")
	step_leaf(0)
	step_leaf(2)
	memory.reject = true
	step_leaf(1)
	check(lotus.completion_pending and not lotus.solved and not memory.has_completed(lotus.SOLVED_FACT),"Failed completion save does not open the lotus or mark success")
	check(not lotus.dropped and memory.get_item_count(lotus.REWARD_ITEM)==0,"No reward is granted before a successful completion transaction")
	memory.reject = false
	lotus.retry_remaining = 0
	lotus.tick(0.01)
	check(lotus.solved and memory.has_completed(lotus.SOLVED_FACT),"Retry commits the puzzle independently of claiming its drop")
	check(not lotus.dropped and lotus.bloom.visible,"The lotus begins opening before its red seal drops")
	for i in 100: lotus.tick(0.02)
	check(lotus.dropped and lotus.drop_landed and lotus.red_seal.visible,"One red seal rises from the opening lotus and lands in the world")
	check(memory.get_item_count(lotus.REWARD_ITEM)==0,"A visible dropped seal is not already in the inventory")
	check(scene.controls_inverted_enabled and scene.controls_inverted(),"Solving grants no calm stone and preserves yin inversion")
	scene.queue_free()
	await process_frame
	make_scene()
	await process_frame
	check(lotus.solved and lotus.dropped and not lotus.claimed,"Re-entry restores the completed lotus and unclaimed world drop")
	place(lotus.position+Vector2(lotus.FLOWER_AT.x,0))
	memory.reject = true
	lotus.tick(0.02)
	check(lotus.red_seal.visible and not lotus.claimed and memory.get_item_count(lotus.REWARD_ITEM)==0,"Failed pickup save keeps the drop visible and gives no item")
	memory.reject = false
	lotus.tick(1.1)
	check(lotus.claimed and not lotus.red_seal.visible and memory.get_item_count(lotus.REWARD_ITEM)==1,"Approaching the settled drop atomically claims one red seal")
	lotus.tick(1)
	check(memory.get_item_count(lotus.REWARD_ITEM)==1,"Holding pickup range cannot duplicate the seal")
	side(MirrorLake.Side.YIN)
	check(scene.controls_inverted() and scene.controls_inverted_enabled,"Picking up the red seal still does not remove inversion")
	check((scene.player as LanPlayer).are_attacks_allowed() and not (scene.player as LanPlayer).are_parries_allowed(),"Yin attack/parry restrictions remain intact after pickup")
	scene.queue_free()
	await process_frame
	make_scene()
	await process_frame
	check(lotus.solved and lotus.claimed and not lotus.red_seal.visible,"A claimed seal never respawns on re-entry")
	var owned := lotus.surfaces.duplicate()
	var before := actor.ground_surfaces.size()
	lotus.queue_free()
	await process_frame
	check(actor.ground_surfaces.size()==before-owned.size(),"Teardown removes only lotus platform surfaces")
	scene.lotus = null
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	print("LOTUS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
