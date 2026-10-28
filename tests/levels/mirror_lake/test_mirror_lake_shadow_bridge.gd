extends SceneTree
## Full scene, real player traversal, safe falls, local geometry, save/reward transactions.
class MemoryProgress extends SaveProgressService:
	var reject := false
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not reject
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var checks := 0
var failures := 0
var scene: MirrorLake
var actor: LanPlayer
var puzzle: MirrorLakeShadowBridge
var memory: MemoryProgress
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func key(code: Key,pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func side(value: int) -> void:
	if scene.side == value: return
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN+0.1)
	check(scene.request_switch(),"Actual mirror-switch route succeeds")
func place(at: Vector2) -> void:
	actor.position = at
	actor.velocity = Vector2.ZERO
	actor.air_state = LanPlayer.AirState.GROUNDED
	actor.ground_action_state = LanPlayer.GroundActionState.NONE
	actor.play_idle()
func make_scene() -> void:
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	actor = scene.player as LanPlayer
	actor.set_physics_process(false)
	puzzle = scene.shadow_bridge
func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	memory = MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	make_scene()
	await process_frame
	check(puzzle != null and puzzle.bridges.size() == 2,"Two bridge encounters are installed in the real map")
	check(puzzle.texture != null and puzzle.texture.get_size() == Vector2(1774,887),"New ink-wash bridge art is loaded")
	var art := puzzle.texture.get_image()
	check(art.get_pixel(0,0).a == 0 and art.get_pixel(880,650).a == 0,"Outside and arch opening are genuinely transparent")
	var gap := MirrorLakeShadowBridge.deck_point(puzzle.bridges[0],950)
	check(gap.y < MirrorLake.STAND_Y-206.0,"Crown and reward route are above a water-level double jump")
	place(gap)
	check(is_equal_approx(actor.resolve_ground_snap_y(),MirrorLake.STAND_Y),"Yang missing bridge has no invisible collision")
	var before := actor.sloped_ground_surfaces.size()
	side(MirrorLake.Side.YIN)
	check(is_equal_approx(actor.resolve_ground_snap_y(),gap.y),"Yin fills the correct arch at its painted deck")
	var yin_slopes := actor.sloped_ground_surfaces.size()
	check(yin_slopes > before,"Yin adds only the missing walk ranges")
	for i in 6:
		side(MirrorLake.Side.YANG)
		side(MirrorLake.Side.YIN)
	check(actor.sloped_ground_surfaces.size() == yin_slopes,"Repeated switches do not leak or duplicate walk surfaces")
	# Walk under the inverted controls through the complete first arch.
	place(Vector2(3080,MirrorLake.STAND_Y))
	scene._update_zone_controls()
	check(scene.controls_inverted(),"Real traversal retains the existing yin direction inversion")
	key(KEY_A,true) # Actual A maps to right in yin.
	key(KEY_S,true) # Actual S maps to jump in yin.
	var min_y := actor.position.y
	for i in 760:
		if i == 1: key(KEY_S,false)
		actor._physics_process(1.0/60.0)
		min_y = minf(min_y,actor.position.y)
	key(KEY_A,false)
	key(KEY_S,false)
	check(actor.position.x > 5200.0 and min_y < 345 and absf(actor.position.y-MirrorLake.STAND_Y)<1,
		"Real jump and walking cross the entire ink arch, then return to the lake floor")
	check(actor.combat_stats.health == actor.combat_stats.max_health,"Bridge traversal causes no damage")
	# The fake lower branch's middle never gets a walk surface.
	var false_bridge := {"origin":puzzle.bridges[1].origin+Vector2(260,322),"scale":0.5}
	place(MirrorLakeShadowBridge.deck_point(false_bridge,760))
	check(is_equal_approx(actor.resolve_ground_snap_y(),MirrorLake.STAND_Y),"Mirage with a broken reflection is not a walkable shadow bridge")
	# Falling off or switching early returns to the ordinary lake floor.
	place(gap)
	side(MirrorLake.Side.YANG)
	for i in 100: actor._physics_process(1.0/60.0)
	check(absf(actor.position.y-MirrorLake.STAND_Y) < 1 and not actor.hit_reaction_active,"Switching off an unfixed bridge safely falls to walkable water")
	# A stamp is not settled on the wrong plane or while in the air.
	var crown := MirrorLakeShadowBridge.deck_point(puzzle.bridges[0],875)
	place(crown)
	puzzle.tick(0.02)
	check(not puzzle.bridges[0].fixed,"Yang cannot activate the yin stamp")
	side(MirrorLake.Side.YIN)
	actor.air_state = LanPlayer.AirState.FALLING
	puzzle.tick(0.02)
	check(not puzzle.bridges[0].fixed,"Passing above the stamp does not activate it in midair")
	place(crown)
	memory.reject = true
	puzzle.tick(0.02)
	check(not puzzle.bridges[0].fixed and not memory.has_completed(puzzle.FIRST_FACT),"Failed save rolls back the stamp and leaves the bridge unfixed")
	memory.reject = false
	puzzle.tick(1.1)
	check(puzzle.bridges[0].fixed and memory.has_completed(puzzle.FIRST_FACT),"Successful retry permanently records the first stamp")
	side(MirrorLake.Side.YANG)
	place(gap)
	check(is_equal_approx(actor.resolve_ground_snap_y(),gap.y),"Fixed shadow remains walkable in yang")
	side(MirrorLake.Side.YIN)
	place(MirrorLakeShadowBridge.deck_point(puzzle.bridges[1],875))
	puzzle.tick(0.02)
	check(puzzle.bridges[1].fixed and puzzle.reward.visible,"Second stamp fixes the fork route and reveals the high reward")
	place(puzzle.reward.position+Vector2(0,28))
	memory.reject = true
	puzzle.tick(0.02)
	check(not puzzle.reward_claimed and memory.get_item_count(puzzle.REWARD_ITEM) == 0,"Failed reward save gives no item and keeps the pickup")
	memory.reject = false
	puzzle.tick(1.1)
	check(puzzle.reward_claimed and memory.get_item_count(puzzle.REWARD_ITEM) == 1,"High pickup atomically grants the rubbing once")
	puzzle.tick(0.02)
	check(memory.get_item_count(puzzle.REWARD_ITEM) == 1,"Standing on the reward cannot duplicate it")
	scene.queue_free()
	await process_frame
	make_scene()
	await process_frame
	check(puzzle.bridges[0].fixed and puzzle.bridges[1].fixed,"Re-entering restores both fixed bridges independently")
	check(puzzle.reward_claimed and not puzzle.reward.visible,"Claimed reward stays gone after re-entry")
	# Removing this component must leave entry platforms and the water alone.
	var rectangles := actor.ground_surfaces.duplicate()
	puzzle.queue_free()
	await process_frame
	check(actor.sloped_ground_surfaces.is_empty() and actor.ground_surfaces == rectangles,"Teardown removes only owned slopes and preserves entry terrain")
	scene.shadow_bridge = null
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	print("SHADOW BRIDGE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
