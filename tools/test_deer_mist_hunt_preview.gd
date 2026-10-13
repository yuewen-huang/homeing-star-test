extends SceneTree

var room
var deer: DeerBoss
var checks := 0
var failures := 0
var output := ""
var rounds: Dictionary = {}
var attacks: Dictionary = {}
var dash_frames: Dictionary = {}
var dash_directions: Dictionary = {}
var synchronized_dash := true
var cleared_between_rounds := true
var saw_charge_trails := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", text)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	room._unhandled_key_input(event)

func advance(seconds: float) -> void:
	for tick in ceili(seconds * 60):
		var delta := Engine.time_scale / 60.0
		deer._physics_process(delta)
		deer.vfx._process(delta)
		room._physics_process(delta)
		if deer.state in [DeerBoss.State.HUNT_WARNING, DeerBoss.State.HUNT_CHARGE]:
			rounds[deer._hunt_round] = true
		if deer.state == DeerBoss.State.HUNT_CHARGE and is_instance_valid(deer.vfx._painted_rush):
			saw_charge_trails = saw_charge_trails or not deer.vfx._trails.is_empty()
			var effect: DeerPaintedEffect = deer.vfx._painted_rush
			var frame := DeerPaintedArt.frame_at("mist_dash", DeerPaintedArt.loop_time("mist_dash", deer._time))
			dash_frames[deer.animated_sprite.frame] = true
			dash_directions[deer.direction] = true
			var rect: Array = frame.front.region
			synchronized_dash = synchronized_dash and effect.kind == "mist_dash" and effect.back.visible and effect.front.visible and effect.position == deer.position and deer.animated_sprite.frame == int(frame.body_frame) and (effect.front.texture as AtlasTexture).region == Rect2(rect[0],rect[1],rect[2],rect[3]) and effect.scale.x == -deer.direction
		if deer.state == DeerBoss.State.HUNT_WARNING:
			cleared_between_rounds = cleared_between_rounds and not is_instance_valid(deer.vfx._painted_rush)
		if deer.attack_hitbox.attack != null:
			var attack := deer.attack_hitbox.attack
			attacks[attack.attack_id] = attack.health_damage

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	deer.vfx.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Captured " + name)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
		DirAccess.make_dir_recursive_absolute(output)
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var save_before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	deer = room.adapter.boss as DeerBoss
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.player.set_physics_process(false)
	room.set_physics_process(false)
	check(room.ultimate_button.visible and room.item_button.visible, "Dedicated deer room exposes manual ultimate and Q controls")
	check(deer.manual_control and deer.vine_test_mode and deer.has_vine_snare(), "Preview grants a local snare without enabling AI or touching inventory")
	room.player.position.x = 640
	key(KEY_5)
	check(deer.state == DeerBoss.State.CHANT and deer._hunt_active, "5 starts the actual hunt chant")
	advance(0.5)
	check(deer.attack_hitbox.attack == null and room.adapter.telemetry().contains("鹿鸣蓄势"), "Chant is a readable windup without an attack")
	await snapshot("chant")
	advance(0.75)
	check(deer.state == DeerBoss.State.HUNT_WARNING and deer._hunt_round == 1, "Chant leads to first warned ambush")
	check(room.adapter.preview_item_status().contains("现在可按 Q"), "Counter timing is shown without automatic item use")
	await snapshot("ambush_warning")
	advance(0.85)
	check(deer.state == DeerBoss.State.HUNT_CHARGE and deer.attack_hitbox.attack != null, "Warning enters the real gold ambush contact")
	await snapshot("ambush_charge")
	advance(0.2)
	await snapshot("mist_dash_right")
	while deer._hunt_round != 2 or deer.state != DeerBoss.State.HUNT_CHARGE: advance(1.0 / 60.0)
	advance(0.25)
	await snapshot("mist_dash_left")
	advance(7.5)
	await snapshot("final_stomp")
	advance(5.0)
	check(dash_frames.size() == 6 and dash_directions.size() == 2 and synchronized_dash, "All six supplied poses and both painted depth layers stay synchronized through four mirrored rushes and their loop boundaries")
	check(cleared_between_rounds and saw_charge_trails and deer.vfx._trails.is_empty(), "Each warning clears the previous painted dash; the original body trails appear during charges and finish before idle")
	room.player.position = room.PLAYER_START
	check(rounds.size() == 4 and deer._hunt_round == 5, "Full manual ultimate performs four ambushes then the final stomp")
	check(attacks.size() == 5 and attacks.values().count(18) == 4 and attacks.values().count(20) == 1, "All five attack segments retain their distinct IDs and intended damage")
	check(not deer._hunt_active and deer.state == DeerBoss.State.IDLE and not deer.poise_broken, "Uncountered hunt ends in recovery and manual idle")
	check(room.player.combat_stats.health == 100 and not root.get_node("ParryQTE").active, "Full hunt cannot damage preview player or trigger QTE")
	await snapshot("complete")

	room.ultimate_button.pressed.emit()
	advance(1.25)
	key(KEY_Q)
	check(deer.snared and deer.state == DeerBoss.State.STAGGER and is_equal_approx(deer.stagger_remaining, 4.5), "Q during warning reveals the real 4.5-second snare stagger")
	check(not deer._hunt_active and deer.attack_hitbox.attack == null, "Successful Q cancels all pending ambush and stomp damage")
	advance(0.08)
	check(is_instance_valid(deer.vfx._painted_vine) and deer.vfx._painted_vine.manual_time, "Real counter creates the persistent painted cage")
	check(not deer.vfx._vine_back.visible and deer.vfx._vine_frames.is_empty(), "Generated cage is replaced by the user's single painted layer")
	var emerging_y: float = deer.vfx._painted_vine.front.position.y
	var emerging_bottom := emerging_y + (deer.vfx._painted_vine.front.texture as AtlasTexture).region.size.y * 1.4
	check(emerging_bottom > -10 and emerging_bottom < 60, "Early painted vines stay anchored around the floor")
	check(is_equal_approx(deer.animated_sprite.position.y, -124 * 1.4 + 1.4), "The cage reference's first hurt poses retain the user's one-pixel body adjustment")
	await snapshot("vine_emerge")
	advance(0.12)
	var rising_y: float = deer.vfx._painted_vine.front.position.y
	check(rising_y < emerging_y, "Painted vines climb above their initial ground frame")
	await snapshot("vine_rise")
	advance(0.28)
	check(deer.vfx._painted_vine.front.visible and room.adapter.telemetry().contains("拦截成功"), "Painted cage and real counter result are visible")
	check(is_equal_approx(deer.vfx._snare_growth, 1) and deer.vfx._painted_vine.front.position.y < -250, "Nine painted frames close above the antlers within their authored 450 ms")
	var closed_region: Rect2 = (deer.vfx._painted_vine.front.texture as AtlasTexture).region
	var paused_growth: float = deer.vfx._snare_growth
	deer._parry_pause = 0.1
	deer.vfx._process(0.05)
	check(is_equal_approx(deer.vfx._snare_growth, paused_growth), "Combat pause also pauses the cage clock")
	deer._parry_pause = 0
	await snapshot("snared")
	check(not room.use_preview_item(), "An already-countered hunt cannot be countered again")
	advance(3.8)
	check(deer.snared and is_equal_approx(deer.vfx._snare_growth, 1) and deer.vfx._painted_vine.front.visible and (deer.vfx._painted_vine.front.texture as AtlasTexture).region == closed_region, "Closed cage holds its last painted cel throughout stagger without looping growth")
	advance(0.4)
	check(not deer.snared and not deer.poise_broken and deer.vfx._snare_growth < 1, "Counter releases after its action-time window and cage starts retracting")
	await snapshot("vine_retract")
	advance(0.3)
	check(not is_instance_valid(deer.vfx._painted_vine) and is_zero_approx(deer.vfx._snare_opacity), "Both cage layers retract completely into the floor")

	key(KEY_5)
	key(KEY_Q)
	check(deer.state == DeerBoss.State.CHANT and deer.item_cooldown == 4.0 and not deer.snared, "Premature Q misses and starts four-second cooldown")
	advance(1.25)
	check(not room.use_preview_item() and not deer.snared, "Cooldown prevents retry during the next warning")
	advance(3.0)
	check(is_zero_approx(deer.item_cooldown), "Missed-item cooldown expires in action time")

	room.item_available.button_pressed = false
	key(KEY_5)
	advance(1.25)
	check(not deer.has_vine_snare() and not room.use_preview_item() and is_zero_approx(deer.item_cooldown), "Missing-item toggle cannot counter or cause a false cooldown")
	await snapshot("without_item")
	room.item_available.button_pressed = true
	check(deer.has_vine_snare(), "Ownership toggle restores only the local preview item")

	key(KEY_1)
	check(deer.state == DeerBoss.State.LIGHT and not deer._hunt_active and not deer.mist.hunting and not deer.snared, "Switching to light cancels hunt, fog state and snare")
	advance(11.0)
	check(deer.state == DeerBoss.State.IDLE and not deer._hunt_active, "Interrupted hunt never resumes or autonomously restarts")
	key(KEY_5)
	advance(1.25)
	key(KEY_Q)
	key(KEY_4)
	check(deer.state == DeerBoss.State.CHARGE and not deer.poise_broken and not deer.snared and is_zero_approx(deer.item_cooldown), "Charge button resets snare, stagger and cooldown before its own motion")
	check(not is_instance_valid(deer.vfx._painted_vine) and deer.vfx._snare_opacity == 0, "Restart removes both visual snare layers")

	room.set_playback_speed(0)
	key(KEY_KP_5)
	advance(4.0)
	check(deer.state == DeerBoss.State.CHANT, "Quarter speed preserves the full chant instead of advancing on wall time")
	advance(1.0)
	check(deer.state == DeerBoss.State.HUNT_WARNING, "Quarter speed reaches the same warned first ambush")
	key(KEY_Q)
	advance(0.8)
	check(deer.snared and deer.vfx._snare_growth > 0.4 and deer.vfx._snare_growth < 0.7, "Quarter-speed cage is still rising after 0.8 wall seconds")
	advance(1.0)
	check(deer.snared and is_equal_approx(deer.vfx._snare_growth, 1), "Quarter-speed cage closes after the same action-time duration")
	key(KEY_5)
	advance(8.4)
	advance(0.8)
	check(deer.state == DeerBoss.State.HUNT_CHARGE and is_instance_valid(deer.vfx._painted_rush) and is_equal_approx(deer.vfx._painted_rush.elapsed, deer._time), "Quarter-speed mist dash follows the real charge clock")
	key(KEY_1)
	check(not is_instance_valid(deer.vfx._painted_rush), "Switching actions removes the dedicated dash immediately")
	room.set_playback_speed(2)
	key(KEY_5)
	advance(1.25)
	deer.direction = 1.0
	key(KEY_Q)
	advance(0.5)
	check(deer.vfx._painted_vine.scale.x == -1, "Cage mirrors the full painting around the original foot anchor")
	await snapshot("vine_mirrored")
	room.boss_picker.item_selected.emit(1)
	await process_frame
	await process_frame
	check(not room.ultimate_row.visible, "Master preview hides unsupported deer ultimate controls")
	current_scene = null
	room.free()
	await process_frame
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == save_before), "All preview controls leave real progress byte-identical")
	print("MIST HUNT PREVIEW: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
