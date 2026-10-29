extends SceneTree
class MemoryProgress extends SaveProgressService:
	var reject := false
	var reject_stele := false
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not reject
	func set_stele_state(id: StringName, value: int) -> bool:
		return false if reject_stele else super.set_stele_state(id, value)
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var failures := 0
var checks := 0
var scene: MirrorLake
var player: LanPlayer
var trial: MirrorLakeInkTrial
var memory: MemoryProgress
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + label)
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func side(value: int) -> void:
	if scene.side == value: return
	scene.advance_switch(3.0)
	check(scene.request_switch(), "map switch accepted")
	scene.advance_switch(3.0)
func place(x: float) -> void:
	player.position = Vector2(x, MirrorLake.STAND_Y)
	player.velocity = Vector2.ZERO
	player.air_state = LanPlayer.AirState.GROUNDED
	player.defense_state = LanPlayer.DefenseState.NONE
	player.attack_state = LanPlayer.AttackState.NONE
	player.ground_action_state = LanPlayer.GroundActionState.NONE
	player.combat_timeline.stop()
	player.attack_queued = false
	player.consume_buffered_attack()
	player.consume_buffered_parry()
	player.facing_direction = 1.0
	player.play_idle()
func make_scene() -> void:
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	player = scene.player as LanPlayer
	player.set_physics_process(false)
	trial = scene.ink_trial
	trial.set_physics_process(false)
	var bounds := trial.stele.texture.get_image().get_used_rect()
	check(is_equal_approx(bounds.size.y * trial.stele.scale.y, 320.0), "shared trial/combat Bixi retains 320 world-pixel visible height")
	check(trial.stele.get_parent() == trial.combat_stele and trial.combat_stele.scene_file_path == "res://scenes/levels/mirror_lake/mirror_lake_combat_stele.tscn", "trial uses the combat-stele prefab's single artwork instance")
	check(absf(trial.stele.position.y + bounds.end.y * trial.stele.scale.y) < 0.01, "resized Bixi feet remain on the standing line")
	var mouth_at := trial.to_local(trial.mouth.global_position)
	check(mouth_at.x < -70 and mouth_at.y < -130 and mouth_at.y > -170, "resized art keeps the mouth on the dragon head")
func charge_round() -> void:
	side(MirrorLake.Side.YIN)
	for i in 5: trial.receive_hit(1, player.global_position)
	check(trial.state == MirrorLakeInkTrial.State.WINDUP, "five yin contacts arm exactly one stroke")
func parry_round() -> void:
	side(MirrorLake.Side.YANG)
	place(MirrorLakeInkTrial.STELE_X - 120)
	trial.tick(MirrorLakeInkTrial.RELEASE_DELAY + 0.01)
	check(trial.hitbox.global_position.distance_to(trial.mouth.global_position) < 0.01, "ink originates at the measured Bixi mouth")
	check(trial.stroke.kind == &"horizontal", "trial uses only the authored horizontal stroke")
	check(trial.stroke_velocity.y > 0, "mouth shot aims down toward standing player's guard")
	check(trial.hitbox.attack != null and trial.hitbox.attack.health_damage == 0, "released ink stroke deals zero damage")
	await process_frame
	key(KEY_K, true)
	player._physics_process(1.0 / 60)
	key(KEY_K, false)
	check(player.defense_state == LanPlayer.DefenseState.PARRY_ACTIVE, "real yang K opens guard")
	trial.hitbox.resolve_nearby_parries()
	for i in 18:
		if trial.state != MirrorLakeInkTrial.State.FLIGHT: break
		trial.tick(1.0 / 60)
		trial.hitbox.resolve_nearby_parries()
		await physics_frame
func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	memory = MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	make_scene()
	await process_frame
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(InkStrokeEffect.ROOT + "library.json"))
	for kind in InkStrokeEffect.KINDS:
		var effect := InkStrokeEffect.new()
		root.add_child(effect)
		effect.configure(kind)
		var entry: Dictionary = library.strokes[String(kind)]
		var folder := InkStrokeEffect.ROOT + String(kind) + "/"
		for filename: String in entry.sha256:
			check(FileAccess.get_sha256(folder + filename) == entry.sha256[filename], "%s %s preserved exactly" % [kind, filename])
		check(effect.draw_duration > 0 and effect.picture.texture != null, "%s package can play authored timing" % kind)
		effect.queue_free()
	check(trial.state == MirrorLakeInkTrial.State.LOCKED, "trial initially locked")
	place(MirrorLakeInkTrial.TURTLE_X - 100)
	trial.tick(0.01)
	check(trial.dialogue != null and trial.dialogue.opened and player.input_frozen, "first approach automatically opens dialogue and freezes player")
	check(not scene.request_switch(), "dialogue blocks map switch")
	while trial.dialogue != null: trial.dialogue.advance()
	check(trial.state == MirrorLakeInkTrial.State.CHARGING and not player.input_frozen, "finishing intro unlocks trial")
	check(memory.has_completed(trial.INTRO_FACT), "intro completion persisted independently")
	check(trial.combat_stele.state == MinigameStele.SteleState.UNLOCKED, "opening ink trial unlocks that same combat stele")
	trial.receive_hit(1, player.global_position)
	check(trial.charge == 0, "yang cannot charge")
	side(MirrorLake.Side.YIN)
	place(trial.STELE_X - 65)
	key(KEY_J, true)
	player._physics_process(1.0 / 60)
	key(KEY_J, false)
	for i in 45:
		player._physics_process(1.0 / 60)
		await physics_frame
	check(trial.charge >= 1, "real J sword collision charges the stele")
	trial._reset_round()
	charge_round()
	trial.tick(trial.RELEASE_DELAY - 0.1)
	check(trial.state == MirrorLakeInkTrial.State.WINDUP, "stroke respects release delay")
	trial.tick(0.2)
	trial.tick(trial.FLIGHT_DURATION + 0.1)
	check(trial.state == MirrorLakeInkTrial.State.CHARGING and trial.successes == 0, "miss resets charge without success")
	charge_round()
	await parry_round()
	check(trial.successes == 1 and not memory.has_completed(trial.SOLVED_FACT), "one real parry does not complete trial")
	charge_round()
	memory.reject = true
	await parry_round()
	check(trial.successes == 2 and trial.state == MirrorLakeInkTrial.State.SETTLING, "second parry waits for successful save")
	memory.reject = false
	memory.reject_stele = true
	trial.tick(1.1)
	check(trial.state == MirrorLakeInkTrial.State.COMPLETE and memory.has_completed(trial.SOLVED_FACT), "two parries persist completion")
	check(trial.combat_stele.state == MinigameStele.SteleState.UNLOCKED and trial.stele_sync_retry > 0, "failed combat-progress save does not falsely show completed")
	memory.reject_stele = false
	trial.tick(1.1)
	check(trial.combat_stele.state == MinigameStele.SteleState.COMPLETED, "successful ink trial completes the same combat progress stele")
	scene.queue_free()
	await process_frame
	make_scene()
	await process_frame
	check(trial.state == MirrorLakeInkTrial.State.COMPLETE and trial.dialogue == null, "re-entry restores completed state without repeating intro")
	check(trial.combat_stele.state == MinigameStele.SteleState.COMPLETED, "re-entry restores combat-stele completion on the trial carrier")
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	print("Ink trial: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
