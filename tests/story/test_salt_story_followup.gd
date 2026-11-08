extends SceneTree
class MemorySave extends SaveProgressService:
	var fail := false
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return not fail
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var save: MemorySave
var field: Chapter2SaltField
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func key(code: Key = KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
	await process_frame; await process_frame
func finish_lines(count: int) -> void:
	for i in count: await key()
func choose(npc, index: int) -> void:
	npc.choices.choose(index)
	await process_frame; await process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
func clear() -> void:
	if is_instance_valid(field): field.free()
	current_scene = null
func enter(fresh := false) -> void:
	clear()
	if fresh: save._config = ConfigFile.new()
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field); current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
	await process_frame; await process_frame
func stand(point) -> void:
	field.feet = point.ground + Vector2(-42, 5)
	field._sync_view(0)
	field.camera.position = field.pawn.position - Vector2(0, 100)
	field.camera.reset_smoothing()
	await process_frame; await process_frame
func wait_transition() -> void:
	var transition = root.get_node("SceneTransition")
	for i in 180:
		await process_frame
		if not transition.is_transitioning: break
	field = current_scene as Chapter2SaltField
	field.set_physics_process(false)
	await process_frame
func swing_at_cart(apu, facing: float) -> void:
	field.feet = apu.ground + Vector2(130, 0)
	field._sync_view(0)
	field.pawn.player.facing_direction = facing
	field.pawn.player.play_idle()
	await physics_frame; await physics_frame
	await key(KEY_J)
	for i in 80:
		field.step_exploration(1.0 / 60.0, Vector2.ZERO, false, false)
		await physics_frame
	await process_frame

func run() -> void:
	var old := root.get_node("SaveProgress"); root.remove_child(old); old.free()
	save = MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	await enter(true)
	check(field.salt_story.points.size() == 3, "Three optional locations replace rejected vignettes")
	for point in field.salt_story.points.values():
		var clear_feet := true
		for pile in field.piles:
			if pile.footprint().grow(45).has_point(point.ground): clear_feet = false
		check(clear_feet, "%s is reachable away from ordinary heap footprints" % point.kind)
		await stand(point)
		await capture("location_" + point.kind)
	var shed = field.salt_story.points.shed
	await stand(shed); await key(); await key(KEY_ESCAPE)
	check(not paused and not save.has_completed(shed.SHED), "Skipped shed inspection grants no knowledge")
	await key(); await finish_lines(1)
	check(save.has_completed(shed.SHED), "Shed is readable before Shibo")
	var apu = field.salt_story.points.apu
	var road = field.salt_story.points.road
	await stand(road); await key(); await finish_lines(1)
	check(save.has_completed(road.ROAD) and not save.has_completed(road.WIND), "Road evidence works before Apu and does not invent a conversation")
	await stand(apu); await key()
	await capture("apu_right_dialogue")
	await key(); await capture("apu_lan_left_dialogue")
	await key(KEY_ESCAPE)
	check(not paused and not save.has_completed(apu.CART), "Skipped Apu introduction restores movement")
	await key(); await choose(apu, 2); await finish_lines(2)
	check(save.has_completed(apu.DIRECTION) and not apu.cart_binding.freed, "Direction is available without helping or reading intro")
	await key(); await choose(apu, 1); await finish_lines(5)
	check(save.has_completed(apu.WIND), "Wind account records only what Apu witnessed")
	await key(); await choose(apu, 0); await finish_lines(3)
	check(save.has_completed(apu.CART), "Cart account can be read after direction and Wind")
	var binding = apu.cart_binding
	var state_before: Dictionary = field.state.duplicate(true)
	# Ordinary exploration uses the actual J action, production timeline and overlap detector.
	await swing_at_cart(apu, -1)
	check(not binding.freed, "A real sword swing away from cart cannot release it")
	save.fail = true
	await swing_at_cart(apu, 1)
	check(not binding.freed and not save.has_completed(binding.FREED), "Failed prop save leaves crystal retryable")
	save.fail = false
	await swing_at_cart(apu, 1)
	check(binding.freed and save.has_completed(binding.FREED), "Actual ordinary attack breaks wheel crystals and persists")
	check(field.state == state_before, "Breaking wheel salt never changes any heap or boss discovery")
	await capture("cart_released")
	await stand(apu); await key(); await choose(apu, 0)
	check(apu.dialogue._lines[0].text == "能转了。", "Freed cart changes Apu response")
	await key(KEY_ESCAPE)
	await enter()
	apu = field.salt_story.points.apu
	check(apu.cart_binding.freed and not apu.cart_binding.art.visible and apu.cart_binding.hurtbox.collision_layer == 0, "Reentry restores freed art and disables its hit target")
	await enter(true)
	apu = field.salt_story.points.apu
	await swing_at_cart(apu, 1)
	check(apu.cart_binding.freed and not save.has_completed(apu.CART) and not save.has_completed(apu.WIND), "Player can free the cart before speaking to Apu")
	await stand(apu); await key()
	check(apu.dialogue._lines[0].text == "能转了。", "First conversation respects a cart already freed")
	await key(KEY_ESCAPE)
	await enter()
	apu = field.salt_story.points.apu
	await stand(apu)
	check(not apu._owns_bubble, "Returning to a freed cart does not repeat the warning to stop pushing")
	await enter(true)
	# Previously shipped story facts must not suppress new anomaly lines.
	for id in ["story_c2_shibo_intro_offered", "story_c2_apu_intro_offered", "story_c2_salt_rake_read", "story_c2_salt_wind_help_understood"]:
		save.try_complete_fact(StringName(id))
	await enter()
	apu = field.salt_story.points.apu
	check(not apu._offered and not field.shibo._offered, "Old story offered flags do not hide new introductions")
	await stand(apu); await key(); await key(KEY_ESCAPE)
	save.fail = true
	await key(); await choose(apu, 1); await finish_lines(5)
	check(not paused and not save.has_completed(apu.WIND), "Optional dialogue save failure never traps player")
	save.fail = false
	await enter(true)
	# Zero NPC/inspection facts: only the existing combat victory is seeded.
	save.try_complete_fact(&"chapter_2_salt_crab_defeated")
	await enter()
	var encounter = field.crab_encounter
	check(encounter.portal.visible and not encounter.session_active, "Old victory immediately opens exit without any story prerequisites")
	field.feet = encounter.CAVE_FEET; field._sync_view(0)
	check(encounter.can_use_exit(), "Unwatched departure never blocks the normal exit")
	field.feet = encounter.patrol_feet + Vector2(70, 0); field._sync_view(0)
	encounter._interaction_released = true
	encounter.interact()
	await process_frame
	check(encounter.dialogue != null and paused, "Optional old-save departure still playable")
	await key(KEY_ESCAPE)
	await wait_transition()
	encounter = field.crab_encounter
	check(field.feet == encounter.ARRIVAL_FEET and not paused and field.pawn.can_move(), "Esc during first dialogue skips entire route and returns control at cave")
	check(save.get_cinematic_status(encounter.DEPARTURE_ID) == SaveProgressService.CinematicStatus.SKIPPED and not save.has_completed(encounter.DIALOGUE_FACT), "Whole-route skip is separate from dialogue read and WATCHED")
	check(encounter.portal.visible and not save.has_completed(&"mirror_lake_entered"), "Skip opens cave without pretending to enter lake")
	await capture("whole_route_skipped")
	# Skip must also remain escapable when its optional viewing record cannot be saved.
	await enter(true)
	save.try_complete_fact(&"chapter_2_salt_crab_defeated")
	await enter()
	encounter = field.crab_encounter
	encounter._start_departure()
	save.fail = true
	await key(KEY_ESCAPE)
	await wait_transition()
	encounter = field.crab_encounter
	check(not paused and field.feet == encounter.ARRIVAL_FEET and encounter.portal.visible, "Failed skip save still reaches usable cave")
	check(save.get_cinematic_status(encounter.DEPARTURE_ID) == SaveProgressService.CinematicStatus.UNHANDLED, "Failed skip save never fabricates persisted viewing status")
	save.fail = false
	clear()
	print("Salt follow-up: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
