extends "../../support/harness.gd"
## Deep-water swimming (LanSwimMotor + UnderwaterVolume), real physics frames and input.
const PLAYER := preload("res://scenes/player/lan/lan_player.tscn")
const PIECE := preload("res://scenes/levels/common/terrain_piece.tscn")
const DT := 1.0 / 60.0
const ACTIONS: Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"jump", &"instant_dash"]

var world: Node2D
var player: LanPlayer
var volume: UnderwaterVolume


func run() -> void:
	use_memory_progress()
	build()
	check(LanPlayer.AirState.SWIMMING == LanPlayer.AirState.VINE_SWINGING + 1, "SWIMMING appended after VINE_SWINGING")
	await test_enter_and_sink()
	await test_eight_directions()
	await test_slow_turning()
	await test_art_switch()
	await test_turn_up_no_burst()
	await test_body_continuity()
	await test_stroke()
	await test_kick()
	await test_floor_walk_and_push_off()
	await test_surface_exit()
	await test_animations()
	await test_dive_entry()
	await test_idle_stays_steady()
	await test_shallow_water_unchanged()
	await test_unregister()
	expect_save_untouched()
	finish("LAN SWIMMING")


func build() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	player = PLAYER.instantiate() as LanPlayer
	player.world_min_x = 0
	player.world_max_x = 3000
	player.fallback_ground_y = 3000
	world.add_child(player)
	var floor_piece := PIECE.instantiate() as TerrainPiece
	floor_piece.position = Vector2(0, 1200)
	floor_piece.length = 3000.0
	world.add_child(floor_piece)
	floor_piece.register_to(player)
	volume = UnderwaterVolume.new()
	volume.position = Vector2(400, 500)
	volume.size = Vector2(1800, 760)
	world.add_child(volume)
	volume.register_to(player)


func release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func step(frames: int) -> void:
	for i in frames:
		await physics_frame


func place(at: Vector2, state := LanPlayer.AirState.FALLING) -> void:
	release_all()
	await step(2)
	player.reset_after_map_fall(at)
	player.instant_dash_cooldown_remaining = 0.0
	player.air_state = state
	player.velocity = Vector2.ZERO
	if state == LanPlayer.AirState.FALLING:
		player.play_air_animation(&"fall")


func swimming() -> bool:
	return player.air_state == LanPlayer.AirState.SWIMMING


func test_enter_and_sink() -> void:
	await place(Vector2(1800, 520))
	player.velocity.y = 800.0  # diving in fast
	await step(2)
	check(swimming(), "Airborne inside the volume enters SWIMMING")
	check(player.velocity.y <= LanSwimMotor.MAX_FALL_SPEED + 0.01, "Dive is damped to the swim fall cap: %.1f" % player.velocity.y)
	check(player.animated_sprite.animation == LanSwimMotor.ANIM_ENTER, "Diving in plays the enter-water clip")
	await place(Vector2(1800, 700))
	await step(2)
	var start_y := player.position.y
	var max_vy := 0.0
	for i in 120:
		await step(1)
		max_vy = maxf(max_vy, player.velocity.y)
	check(swimming(), "Still swimming while idling")
	check(player.position.y > start_y + 20.0, "Idle body sinks slowly: %.1f px in 2 s" % (player.position.y - start_y))
	check(max_vy <= LanSwimMotor.IDLE_SINK_SPEED + 0.01, "Idle sink stays at drift speed: %.1f" % max_vy)


func test_eight_directions() -> void:
	var dirs := {
		Vector2(1, 0): [&"ui_right"], Vector2(-1, 0): [&"ui_left"],
		Vector2(0, -1): [&"ui_up"], Vector2(0, 1): [&"ui_down"],
		Vector2(1, -1): [&"ui_right", &"ui_up"], Vector2(-1, -1): [&"ui_left", &"ui_up"],
		Vector2(1, 1): [&"ui_right", &"ui_down"], Vector2(-1, 1): [&"ui_left", &"ui_down"],
	}
	for dir: Vector2 in dirs:
		await place(Vector2(1800, 950))
		await step(2)
		for action in dirs[dir]:
			Input.action_press(action)
		var top := 0.0
		for i in 60:
			await step(1)
			top = maxf(top, player.velocity.length())
		var v := player.velocity
		var aligned := v.normalized().dot(dir.normalized())
		check(swimming() and aligned > 0.98, "Swims %s (vel %s)" % [dir, v.round()])
		check(v.length() > 150.0 and v.length() <= LanSwimMotor.MAX_SPEED + 1.0, "Speed %s near cap: %.1f" % [dir, v.length()])
		if dir.y >= 0:
			check(top <= LanSwimMotor.MAX_SPEED + 1.0, "Never exceeds swim max %s: %.1f" % [dir, top])
	release_all()


func swim_right_steady() -> void:
	await place(Vector2(1000, 950))
	await step(2)
	Input.action_press(&"ui_right")
	await step(60)


func test_slow_turning() -> void:
	var motor := player.swim
	var cap := LanSwimMotor.HEADING_TURN_RATE / 60.0 + 0.001
	# Right, then curve down 45° (W would also stroke): the heading swings at the capped rate, not at once.
	await swim_right_steady()
	check(motor.heading.is_equal_approx(Vector2.RIGHT), "Swimming right sets the heading right: %s" % motor.heading)
	Input.action_press(&"ui_down")
	var last := motor.heading.angle()
	var max_step := 0.0
	var lag := 0.0
	for i in 12:
		await step(1)
		max_step = maxf(max_step, absf(angle_difference(last, motor.heading.angle())))
		last = motor.heading.angle()
		lag = maxf(lag, absf(angle_difference(player.velocity.angle(), motor.heading.angle())))
	check(max_step <= cap, "Heading turn per frame is capped: %.2f° (cap %.2f°)" % [rad_to_deg(max_step), rad_to_deg(cap)])
	var after := rad_to_deg(motor.heading.angle())
	check(after > 15.0 and after < 30.0, "0.2 s into a 45° turn the heading is part way: %.1f°" % after)
	var v_angle := rad_to_deg(player.velocity.angle())
	check(v_angle < 30.0, "Propulsion follows the heading, not the stick (velocity %.1f°)" % v_angle)
	await step(60)
	check(absf(rad_to_deg(motor.heading.angle()) - 45.0) < 0.5, "The heading settles on the stick: %.1f°" % rad_to_deg(motor.heading.angle()))
	check(absf(rad_to_deg(angle_difference(player.velocity.angle(), motor.heading.angle()))) < 3.0, "Velocity lines up with the heading: %s" % player.velocity.round())
	# Right then curve down 90°: takes most of a second.
	await swim_right_steady()
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_down")
	await step(30)
	var half := rad_to_deg(motor.heading.angle())
	check(half > 40.0 and half < 60.0, "Half a second into a 90° turn: %.1f°" % half)
	check(player.velocity.x > 60.0, "Still carrying forward while turning: %s" % player.velocity.round())
	# Reversal: a quick flip, never a slow sweep through 180°.
	await swim_right_steady()
	var rot_before := player.animated_sprite.rotation
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await step(1)
	check(motor.heading.is_equal_approx(Vector2.LEFT), "Reversal flips the heading at once: %s" % motor.heading)
	check(player.facing_direction < 0.0 and player.animated_sprite.flip_h, "Reversal flips the body to face left")
	check(player.animated_sprite.animation == LanSwimMotor.ANIM_TURN and player.animated_sprite.frame <= 1, "Reversal replays the turn segment: %s f%d" % [player.animated_sprite.animation, player.animated_sprite.frame])
	check(is_equal_approx(player.animated_sprite.rotation, -rot_before), "Reversal mirrors the rotation, no swing: %.3f vs %.3f" % [player.animated_sprite.rotation, rot_before])
	var vx_min := player.velocity.x
	for i in 60:
		await step(1)
		if not motor.heading.is_equal_approx(Vector2.LEFT):
			check(false, "Heading stays left while braking: %s" % motor.heading)
		vx_min = minf(vx_min, player.velocity.x)
	check(vx_min < -150.0, "After the flip she swims left: %.1f" % vx_min)
	release_all()


func body_angle() -> float:
	var sprite := player.animated_sprite
	var art := LanSwimMotor.UP_ART_ANGLE if sprite.animation == LanSwimMotor.ANIM_UP else LanSwimMotor.DOWN_ART_ANGLE
	return sprite.rotation + art  # facing right: the on-screen body line


func elevation() -> float:
	var h := player.swim.heading
	return -atan2(h.y, absf(h.x))


func test_art_switch() -> void:
	var cap := LanSwimMotor.HEADING_TURN_RATE / 60.0 + deg_to_rad(0.5)
	var band := LanSwimMotor.ART_HYSTERESIS
	# Right, curve up: the art swaps to 向上游泳 only past +10°, the body line never jumps.
	await swim_right_steady()
	check(anim() == LanSwimMotor.ANIM_GLIDE, "Steady right swim glides: %s" % anim())
	Input.action_press(&"ui_up")
	var last := body_angle()
	var jump := 0.0
	var switch_at := INF
	var turn_seen := false
	for i in 50:
		await step(1)
		if anim() == LanSwimMotor.ANIM_TURN:
			turn_seen = true
		if anim() == LanSwimMotor.ANIM_UP and is_inf(switch_at):
			switch_at = elevation()
		if anim() == LanSwimMotor.ANIM_GLIDE and elevation() > 0.0:
			check(elevation() <= band + 0.001, "Glide art held up to +10° only: %.1f°" % rad_to_deg(elevation()))
		jump = maxf(jump, absf(angle_difference(last, body_angle())))
		last = body_angle()
	check(not is_inf(switch_at) and switch_at >= band - 0.001 and switch_at <= band + cap, "Up art starts just past +10°: %.1f°" % rad_to_deg(switch_at))
	check(jump <= cap, "Body line stays continuous through glide → up: max %.2f°/frame" % rad_to_deg(jump))
	check(not turn_seen, "No turn segment while steering out of a glide")
	# Now curve down: back to the glide art only past −10°.
	Input.action_release(&"ui_up")
	Input.action_press(&"ui_down")
	last = body_angle()
	jump = 0.0
	switch_at = INF
	turn_seen = false
	for i in 70:
		await step(1)
		if anim() == LanSwimMotor.ANIM_TURN:
			turn_seen = true
		if anim() == LanSwimMotor.ANIM_UP:
			check(elevation() >= -band - 0.001, "Up art held down to −10° only: %.1f°" % rad_to_deg(elevation()))
		elif is_inf(switch_at):
			switch_at = elevation()
		jump = maxf(jump, absf(angle_difference(last, body_angle())))
		last = body_angle()
	check(not is_inf(switch_at) and switch_at <= -band + 0.001 and switch_at >= -band - cap, "Glide art returns just past −10°: %.1f°" % rad_to_deg(switch_at))
	check(jump <= cap, "Body line stays continuous through up → glide: max %.2f°/frame" % rad_to_deg(jump))
	check(not turn_seen and anim() == LanSwimMotor.ANIM_GLIDE, "Up → down goes straight to the glide, no turn segment: %s" % anim())
	# Steering inside a glide (right → right-down) never replays the turn segment.
	await swim_right_steady()
	Input.action_press(&"ui_down")
	turn_seen = false
	for i in 40:
		await step(1)
		turn_seen = turn_seen or anim() == LanSwimMotor.ANIM_TURN
	check(not turn_seen, "Steering within a glide never plays the turn segment")
	# Starting from rest still opens with the turn segment.
	await place(Vector2(1000, 950))
	await step(2)
	Input.action_press(&"ui_right")
	await step(2)
	check(anim() == LanSwimMotor.ANIM_TURN, "Starting from rest plays the turn segment: %s" % anim())
	release_all()


## Swimming sideways, W turns her up at the turn rate: no speed spike over the cap.
func test_turn_up_no_burst() -> void:
	for side in [&"ui_right", &"ui_left"]:
		await place(Vector2(1300, 1000))
		await step(2)
		Input.action_press(side)
		await step(60)
		var cruise := player.velocity.length()
		Input.action_press(&"ui_up")
		Input.action_press(&"jump")  # W is both steer-up and the stroke key
		var top := 0.0
		var spike := 0.0
		var last := cruise
		for i in 40:
			await step(1)
			if i == 0:
				Input.action_release(&"jump")
			var v := player.velocity.length()
			top = maxf(top, v)
			spike = maxf(spike, v - last)
			last = v
		check(top <= LanSwimMotor.MAX_SPEED + 0.5, "%s + W: speed stays within the cap (top %.1f, cruise %.1f)" % [side, top, cruise])
		check(spike <= LanSwimMotor.ACCELERATION / 60.0 + 0.5, "%s + W: no speed spike (max rise %.1f px/s per frame)" % [side, spike])
		release_all()
	# A plain W / jump from rest is still the upward stroke.
	await place(Vector2(1300, 1000))
	await step(20)
	Input.action_press(&"jump")
	await step(1)
	check(player.velocity.y <= -LanSwimMotor.STROKE_IMPULSE + 0.01, "Jump with no side input still strokes: %.1f" % player.velocity.y)
	release_all()


## Where the drawn body anchor is relative to the node (NAN for clips without anchors).
func body_rel() -> Vector2:
	return LanSwimMotor.body_point(player)


## Runs `frames` frames and returns the worst on-screen body jump (beyond the node's own
## motion) at a clip switch, and on frame steps of the pinned swim clips.
var body_log: Array[String] = []
func watch_body(frames: int, worst: Array) -> void:
	var prev := body_rel()
	var prev_clip := anim()
	var prev_frame := player.animated_sprite.frame
	for i in frames:
		await step(1)
		var now := body_rel()
		var clip := anim()
		if not is_nan(now.x) and not is_nan(prev.x):
			var pinned_step := clip == prev_clip and clip in LanSwimMotor.PINNED_ANIMATIONS and clip != LanSwimMotor.ANIM_IDLE
			if clip != prev_clip or pinned_step:
				var d := (now - prev).length()
				if d > worst[0]:
					worst[0] = d
					worst[1] = "%s f%d → %s f%d" % [prev_clip, prev_frame, clip, player.animated_sprite.frame]
				if clip != prev_clip:
					body_log.append("%s→%s %.2f px" % [prev_clip, clip, d])
		prev = now
		prev_clip = clip
		prev_frame = player.animated_sprite.frame


func test_body_continuity() -> void:
	var tol := 3.0
	var worst := [0.0, ""]
	body_log.clear()
	# Rest → swim right (idle → turn → glide), curve up (glide → up, up loops), level
	# off (up → glide), reverse (turn replays), stop (glide → idle), start again.
	await place(Vector2(1300, 1000))
	await watch_body(40, worst)
	Input.action_press(&"ui_right")
	await watch_body(70, worst)
	Input.action_press(&"ui_up")
	await watch_body(90, worst)
	Input.action_release(&"ui_up")
	Input.action_press(&"ui_down")
	await watch_body(60, worst)
	Input.action_release(&"ui_down")
	await watch_body(30, worst)
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await watch_body(60, worst)
	Input.action_release(&"ui_left")
	await watch_body(40, worst)
	Input.action_press(&"ui_left")
	await watch_body(40, worst)
	release_all()
	# Kick, then stop.
	Input.action_press(&"instant_dash")
	await watch_body(1, worst)
	Input.action_release(&"instant_dash")
	await watch_body(50, worst)
	# Up while idle (a stroke with no direction: idle → up → idle).
	Input.action_press(&"jump")
	await watch_body(1, worst)
	Input.action_release(&"jump")
	await watch_body(60, worst)
	# Rise to the surface (swim → surfacing → float), swim along it, then S back down.
	await place(Vector2(1300, 700))
	await step(30)
	Input.action_press(&"ui_up")
	await watch_body(120, worst)
	Input.action_release(&"ui_up")
	await watch_body(10, worst)
	Input.action_press(&"ui_right")
	await watch_body(40, worst)
	Input.action_release(&"ui_right")
	await watch_body(30, worst)
	Input.action_press(&"ui_down")
	await watch_body(40, worst)
	release_all()
	await watch_body(30, worst)
	print("Body switches: ", ", ".join(body_log))
	check(worst[0] <= tol, "On-screen body stays continuous over every clip switch (worst %.2f px at %s)" % [worst[0], worst[1]])
	check(body_log.size() >= 8, "The run covers the clip switches (%d)" % body_log.size())


func test_stroke() -> void:
	await place(Vector2(1800, 1000))
	await step(30)
	Input.action_press(&"jump")
	await step(1)
	check(player.velocity.y <= -LanSwimMotor.STROKE_IMPULSE + 0.01, "Jump is an upward stroke: %.1f" % player.velocity.y)
	Input.action_release(&"jump")
	var start_y := player.position.y
	await step(3)
	Input.action_press(&"jump")
	await step(1)
	var vy := player.velocity.y
	check(vy > -LanSwimMotor.STROKE_IMPULSE + 1.0, "Second press inside cooldown adds no impulse: %.1f" % vy)
	Input.action_release(&"jump")
	await step(60)
	check(swimming() and player.position.y < start_y - 40.0, "Stroke lifts the body: %.1f px" % (start_y - player.position.y))
	check(player.velocity.y > -1.0, "Water brakes the rise back to a drift: %.1f" % player.velocity.y)


func test_kick() -> void:
	await place(Vector2(1000, 1000))
	await step(4)
	player.facing_direction = 1.0
	var start := player.position
	Input.action_press(&"instant_dash")
	await step(1)
	Input.action_release(&"instant_dash")
	check(player.swim.is_kicking(), "Dash key starts a water kick")
	check(is_equal_approx(player.instant_dash_cooldown_remaining, LanPlayer.INSTANT_DASH_COOLDOWN) \
		or player.instant_dash_cooldown_remaining > LanPlayer.INSTANT_DASH_COOLDOWN - 0.05, "Kick shares the instant-dash cooldown")
	await step(int(LanSwimMotor.KICK_DURATION / DT) + 1)
	var moved := player.position.x - start.x
	check(absf(moved - LanSwimMotor.KICK_DISTANCE) < 30.0, "Kick covers about half an instant dash: %.1f px" % moved)
	check(LanSwimMotor.KICK_DISTANCE == LanPlayer.INSTANT_DASH_DISTANCE * 0.5, "Kick distance is half INSTANT_DASH_DISTANCE")
	check(swimming() and not player.swim.is_kicking(), "Kick ends back in swimming")
	var cooled := player.position.x
	Input.action_press(&"instant_dash")
	await step(1)
	Input.action_release(&"instant_dash")
	check(not player.swim.is_kicking(), "No second kick during cooldown")
	await place(Vector2(1000, 900))
	await step(4)
	Input.action_press(&"ui_down")
	Input.action_press(&"instant_dash")
	await step(1)
	Input.action_release(&"instant_dash")
	await step(int(LanSwimMotor.KICK_DURATION / DT) + 1)
	check(player.position.y > 900.0 + 180.0, "Kick follows the held direction (down): %.1f" % (player.position.y - 900.0))
	release_all()


func test_floor_walk_and_push_off() -> void:
	await place(Vector2(1500, 1100))
	Input.action_press(&"ui_down")
	for i in 90:
		await step(1)
		if not swimming(): break
	Input.action_release(&"ui_down")
	await step(30)
	var grounded := player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING]
	check(grounded and is_equal_approx(player.position.y, 1200.0), "Lands on the pool floor (%s, y %.1f)" % [LanPlayer.AirState.keys()[player.air_state], player.position.y])
	check(player.is_in_deep_water() and player.is_in_water(), "Floor inside the volume counts as water")
	check(is_equal_approx(player.get_horizontal_speed(), player._base_horizontal_speed() * LanPlayer.WATER_SPEED_SCALE), "Floor walking uses the shallow-water slowdown")
	var x0 := player.position.x
	Input.action_press(&"ui_right")
	await step(60)
	Input.action_release(&"ui_right")
	check(player.air_state == LanPlayer.AirState.GROUNDED and player.position.x > x0 + 60.0, "Walks on the floor with ground movement: %.1f px" % (player.position.x - x0))
	check(player.position.x < x0 + LanPlayer.WALK_SPEED * 1.0, "Floor walk is slower than dry walking")
	await step(10)
	Input.action_press(&"jump")
	await step(1)
	Input.action_release(&"jump")
	check(swimming() and player.velocity.y < 0.0, "Jump from the floor pushes off into a stroke")


var surface_drift := 0.0


func float_y() -> float:
	return volume.position.y + LanSwimMotor.FLOAT_DEPTH


## Swims up from mid-water holding W and returns once she floats.
func surface_from(at: Vector2) -> Array[int]:
	await place(at)
	await step(2)
	Input.action_press(&"ui_up")
	var frames: Array[int] = []
	var first := Vector2.INF
	surface_drift = 0.0
	for i in 300:
		await step(1)
		if anim() == LanSwimMotor.ANIM_SURFACE:
			if first == Vector2.INF: first = canvas_origin()
			surface_drift = maxf(surface_drift, (canvas_origin() - first).length())
			if frames.is_empty() or frames[-1] != player.animated_sprite.frame:
				frames.append(player.animated_sprite.frame)
		if player.swim.is_floating(): break
	return frames


func test_surface_exit() -> void:
	var sprite := player.animated_sprite
	# 1–2. Holding W: 出水start plays in order, then she stops and floats (no burst out).
	var frames := await surface_from(Vector2(1800, 900))
	check(frames == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], "Swimming up plays every 出水start frame in order: %s" % [frames])
	check(surface_drift < 0.05, "出水start frames stay on their canvas places (drift %.2f px)" % surface_drift)
	check(player.swim.is_floating() and swimming(), "Reaching the surface floats (still SWIMMING)")
	check(absf(player.position.y - float_y()) < 0.01, "Float feet %.1f px under the surface" % (player.position.y - volume.position.y))
	var row_y := canvas_origin().y + LanSwimMotor.EXIT_CANVAS_SURFACE_Y * sprite.scale.y
	check(absf(row_y - volume.position.y) < 0.6, "出水start water line (row 200) on the surface (%.2f vs %.1f)" % [row_y, volume.position.y])
	var clips: Array[StringName] = [anim()]
	var worst := 0.0
	var y0 := player.position.y
	for i in 120:
		await step(1)
		if anim() != clips[-1]: clips.append(anim())
		worst = maxf(worst, absf(player.position.y - y0))
	check(player.swim.is_floating() and clips == [LanSwimMotor.ANIM_SURFACE], "W still held: keeps floating, no exit, no clip change: %s" % [clips])
	# 3. Released: the float holds frame 14 with no sinking.
	Input.action_release(&"ui_up")
	for i in 180:
		await step(1)
		worst = maxf(worst, absf(player.position.y - y0))
	check(worst < 0.01 and player.swim.is_floating(), "No sinking at the surface (%.2f px in 5 s)" % worst)
	check(anim() == LanSwimMotor.ANIM_SURFACE and sprite.frame == 14 and not sprite.is_playing(), "Float = static hold of 出水start frame 14 (%s %d)" % [anim(), sprite.frame])
	# 7. Left / right swims along the surface and stays on it.
	var x0 := player.position.x
	Input.action_press(&"ui_left")
	var off_surface := 0.0
	for i in 60:
		await step(1)
		off_surface = maxf(off_surface, absf(player.position.y - y0))
	check(player.position.x < x0 - 60.0 and off_surface < 0.01 and player.swim.is_floating(), "Left swims along the surface (%.0f px, depth drift %.2f)" % [x0 - player.position.x, off_surface])
	check(anim() in [LanSwimMotor.ANIM_TURN, LanSwimMotor.ANIM_GLIDE] and sprite.flip_h, "Surface swim plays the levelled glide facing left (%s)" % anim())
	Input.action_release(&"ui_left")
	Input.action_press(&"ui_right")
	await step(60)
	check(player.velocity.x > 0.0 and absf(player.position.y - y0) < 0.01 and player.swim.is_floating(), "Right swims along the surface too")
	Input.action_release(&"ui_right")
	await step(2)
	check(anim() == LanSwimMotor.ANIM_SURFACE and sprite.frame == 14, "Release returns to the float hold")
	# 6. S dives normally.
	Input.action_press(&"ui_down")
	await step(30)
	Input.action_release(&"ui_down")
	check(swimming() and not player.swim.is_floating() and player.position.y > y0 + 20.0, "S swims down from the surface (%.0f px)" % (player.position.y - y0))
	await step(60)
	check(not player.swim.is_surfacing() and not player.swim.is_floating(), "Drifting under the surface does not re-surface by itself")

	# 4. W at the surface next to a bank: the land-jump height, water-to-land to the bank.
	var bank := PIECE.instantiate() as TerrainPiece
	bank.position = Vector2(100, 500)
	bank.length = 300.0
	world.add_child(bank)
	bank.register_to(player)
	await place(Vector2(200, 500), LanPlayer.AirState.GROUNDED)
	await step(5)
	Input.action_press(&"jump")
	var land_peak := player.position.y
	for i in 90:
		await step(1)
		land_peak = minf(land_peak, player.position.y)
	Input.action_release(&"jump")
	var land_rise := 500.0 - land_peak
	await surface_from(Vector2(470, 800))
	Input.action_release(&"ui_up")
	await step(3)
	player.facing_direction = -1.0
	await step(2)
	var takeoff_y := player.position.y
	var takeoff_off := sprite.offset
	Input.action_press(&"ui_left")
	Input.action_press(&"ui_up")
	await step(1)
	check(player.swim.is_exiting() and anim() == LanSwimMotor.ANIM_WATER_TO_LAND and sprite.frame == 0 and sprite.offset.is_equal_approx(takeoff_off), "W at the surface jumps out: water-to-land frame 0 at the float's canvas place")
	var peak := player.position.y
	var seen: Array[int] = []
	for i in 180:
		if anim() == LanSwimMotor.ANIM_WATER_TO_LAND and (seen.is_empty() or seen[-1] != sprite.frame):
			seen.append(sprite.frame)
		peak = minf(peak, player.position.y)
		if not player.swim.is_exiting(): break
		await step(1)
	Input.action_release(&"ui_up")
	check(absf((takeoff_y - peak) - land_rise) < 2.0, "Exit jump rises like a land jump (%.1f vs %.1f px)" % [takeoff_y - peak, land_rise])
	check(seen.slice(0, 9) == [0, 1, 2, 3, 4, 5, 6, 7, 8], "Flight frames 0–8 in order: %s" % [seen])
	check(seen.slice(9, 10) == [9], "Touchdown frames 8–9 show before held input walks on: %s" % [seen])
	check(not swimming() and absf(player.position.y - 500.0) < 0.5 and player.position.x < 400.0, "She lands on the bank (%s)" % player.position)
	Input.action_release(&"ui_left")
	bank._unregister_surface()
	bank.queue_free()
	await step(2)

	# 5. W with no land in reach: she falls back in and the entry splash plays.
	await surface_from(Vector2(1500, 900))
	Input.action_release(&"ui_up")
	await step(3)
	Input.action_press(&"ui_up")
	await step(2)
	Input.action_release(&"ui_up")
	check(player.swim.is_exiting(), "W jumps out in open water too")
	for i in 120:
		await step(1)
		if swimming(): break
	check(swimming() and anim() == LanSwimMotor.ANIM_ENTER, "Falling back in plays the entry splash (%s)" % anim())
	await place(Vector2(300, 700))
	var vy0 := player.velocity.y
	await step(10)
	check(player.air_state == LanPlayer.AirState.FALLING and player.velocity.y > vy0 + LanPlayer.GRAVITY * DT * 8.0, "Outside the volume normal gravity applies: %.1f" % player.velocity.y)


func test_shallow_water_unchanged() -> void:
	volume.unregister_from(player)
	var shallow := Rect2(0, 1150, 3000, 60)
	player.register_water(shallow)
	await place(Vector2(1500, 1100))
	var saw_swim := false
	for i in 60:
		await step(1)
		saw_swim = saw_swim or swimming()
	check(not saw_swim and not player.is_in_deep_water(), "Shallow water never swims")
	check(player.is_in_water(), "Shallow water still slows the feet")
	check(is_equal_approx(player.get_horizontal_speed(), player._base_horizontal_speed() * LanPlayer.WATER_SPEED_SCALE), "Shallow slowdown unchanged")
	player.unregister_water(shallow)
	volume.register_to(player)


func test_unregister() -> void:
	await place(Vector2(1800, 800))
	await step(2)
	check(swimming(), "Swimming before the volume goes away")
	volume.queue_free()
	await step(2)
	check(player.swim.zones.is_empty(), "Freed volume unregisters itself")
	check(player.air_state == LanPlayer.AirState.FALLING, "Losing the water drops Lan into a fall")
	release_all()


func anim() -> StringName:
	return player.animated_sprite.animation


func test_animations() -> void:
	var frames := player.animated_sprite.sprite_frames
	var expected := {LanSwimMotor.ANIM_DIVE: 10, LanSwimMotor.ANIM_ENTER: 15, LanSwimMotor.ANIM_IDLE: 16, LanSwimMotor.ANIM_UP: 32,
		LanSwimMotor.ANIM_DOWN: 32, LanSwimMotor.ANIM_SURFACE: 15, LanSwimMotor.ANIM_WATER_TO_LAND: 17}
	for name: StringName in expected:
		check(frames.has_animation(name) and frames.get_frame_count(name) == expected[name],
			"%s registered with %d frames" % [name, expected[name]])
	check(not frames.get_animation_loop(LanSwimMotor.ANIM_ENTER) and frames.get_animation_loop(LanSwimMotor.ANIM_IDLE), "Enter plays once, idle loops")
	# Enter → idle.
	await place(Vector2(1800, 800))
	await step(2)
	check(swimming() and anim() == LanSwimMotor.ANIM_IDLE, "Appearing deep under water skips the splash: %s" % anim())
	await place(Vector2(1800, 530))
	await step(2)
	check(anim() == LanSwimMotor.ANIM_ENTER, "Falling in plays enter: %s" % anim())
	await step(int(60.0 * 15.0 / LanSwimMotor.ASEPRITE_FPS) + 20)  # splash + settle (one clip), then idle
	check(swimming() and anim() == LanSwimMotor.ANIM_IDLE, "Enter hands over to the underwater idle: %s" % anim())
	await place(Vector2(1800, 530))
	await step(4)
	Input.action_press(&"ui_right")
	await step(2)
	check(anim() == LanSwimMotor.ANIM_TURN, "Steering cuts the entry splash short: %s" % anim())
	release_all()
	# Clip by angle: up / up-diagonal → 向上游泳; horizontal / down-diagonal / down → 向下游泳
	# turn (0–3) then stroke loop (4–31). Each rotated from its own art axis, mirrored left.
	check(frames.get_frame_count(LanSwimMotor.ANIM_TURN) == 4 and frames.get_frame_count(LanSwimMotor.ANIM_GLIDE) == 28, "Turn 4 f + glide 28 f")
	var sprite := player.animated_sprite
	var headings := {
		[&"ui_right"]: [Vector2(1, 0), false], [&"ui_left"]: [Vector2(-1, 0), true],
		[&"ui_right", &"ui_down"]: [Vector2(1, 1), false], [&"ui_left", &"ui_down"]: [Vector2(-1, 1), true],
		[&"ui_down"]: [Vector2(0, 1), false],
		[&"ui_right", &"ui_up"]: [Vector2(1, -1), false], [&"ui_left", &"ui_up"]: [Vector2(-1, -1), true],
		[&"ui_up"]: [Vector2(0, -1), false],
	}
	for keys: Array in headings:
		await place(Vector2(1300, 1000))
		await step(2)
		player.facing_direction = 1.0
		player.animated_sprite.play(LanSwimMotor.ANIM_IDLE)
		for k in keys:
			Input.action_press(k)
		var dir: Vector2 = headings[keys][0]
		var up := LanSwimMotor.uses_up_art(dir)
		await step(1)
		check(anim() == (LanSwimMotor.ANIM_UP if up else LanSwimMotor.ANIM_TURN), "%s starts with %s: %s" % [keys, "swim_up" if up else "the turn segment", anim()])
		await step(20)
		var want := LanSwimMotor.swim_rotation(dir, 1.0)
		check(anim() == (LanSwimMotor.ANIM_UP if up else LanSwimMotor.ANIM_GLIDE) and sprite.flip_h == headings[keys][1], "%s plays %s (flip %s)" % [keys, anim(), sprite.flip_h])
		check(absf(sprite.rotation - want) < 0.01, "%s rotation %.1f° (want %.1f°)" % [keys, rad_to_deg(sprite.rotation), rad_to_deg(want)])
		release_all()
	check(is_equal_approx(LanSwimMotor.swim_rotation(Vector2(1, -1)), deg_to_rad(-45.0) - LanSwimMotor.UP_ART_ANGLE), "Up-right is measured from the 向上游泳 axis")
	check(is_equal_approx(LanSwimMotor.swim_rotation(Vector2(0, -1), -1.0), -(deg_to_rad(-90.0) - LanSwimMotor.UP_ART_ANGLE)), "Straight up facing left is mirrored")
	check(is_equal_approx(LanSwimMotor.swim_rotation(Vector2(0, 1)), deg_to_rad(90.0) - LanSwimMotor.DOWN_ART_ANGLE), "Straight down is measured from the 向下游泳 axis")
	check(is_equal_approx(LanSwimMotor.glide_rotation(Vector2(1, 0)), -LanSwimMotor.DOWN_ART_ANGLE), "Horizontal right levels the 27° dive axis")
	check(is_equal_approx(LanSwimMotor.glide_rotation(Vector2(-1, 0)), LanSwimMotor.DOWN_ART_ANGLE), "Horizontal left is mirrored")
	await step(40)
	check(absf(sprite.rotation) < 0.01, "Rotation eases back upright when not steering sideways")
	# Up stroke / rising → swim_up; diving → swim_down.
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	check(anim() == LanSwimMotor.ANIM_UP, "Upward stroke plays swim_up: %s" % anim())
	await step(60)
	Input.action_press(&"ui_down")
	await step(20)
	check(anim() == LanSwimMotor.ANIM_GLIDE, "Holding down plays the 向下游泳 stroke rotated: %s" % anim())
	Input.action_release(&"ui_down")
	await step(90)
	check(anim() == LanSwimMotor.ANIM_IDLE, "Back to idle when drifting: %s" % anim())
	# Ground animations keep the original flip convention.
	await place(Vector2(200, 1150))
	player.facing_direction = 1.0
	await step(30)
	player.apply_facing_direction()
	check(anim() not in LanSwimMotor.SWIM_ANIMATIONS and player.animated_sprite.flip_h, "Dry ground keeps the normal flip (%s)" % anim())
	release_all()


## Jumping off a bank into the pool plays the whole dive (0–9) then the splash, with the
## splash's waterline (canvas row CANVAS_SURFACE_Y) on the real surface.
## World position of the aseprite canvas' top-left, from the frame on screen now.
func canvas_origin() -> Vector2:
	var sprite := player.animated_sprite
	# Canvas position of the cell centre: entry cells from their shift, the idle (drawn in
	# place, 192² cells) from where it takes over.
	var c := LanSwimMotor.IDLE_CANVAS_CENTRE
	if anim() == LanSwimMotor.ANIM_ENTER:
		c = LanSwimMotor.CANVAS_SHIFT_ENTER[sprite.frame] + Vector2(80.0, 80.0)
	elif anim() in [LanSwimMotor.ANIM_SURFACE, LanSwimMotor.ANIM_WATER_TO_LAND]:
		c = LanSwimMotor.EXIT_CANVAS_CENTRE
	var f := -1.0 if sprite.flip_h else 1.0
	var k := sprite.scale.y
	var centre := player.position + sprite.position + Vector2(sprite.offset.x * k, sprite.offset.y * k)
	return Vector2(centre.x - f * c.x * k, centre.y - c.y * k)


## Plain idle under water for several loops: one clip, and the art only drifts with the body.
func test_idle_stays_steady() -> void:
	await place(Vector2(1300, 800))
	await step(2)
	var prev := canvas_origin()
	var worst := 0.0
	var other: Array[StringName] = []
	for i in 60 * 4:
		await step(1)
		if anim() != LanSwimMotor.ANIM_IDLE:
			other.append(anim())
		var o := canvas_origin()
		worst = maxf(worst, (o - prev).length())
		prev = o
	check(other.is_empty(), "Idle never switches clip: %s" % [other])
	# 待机 is a 16-frame loop played forward only (no ping-pong) and it wraps 15 → 0.
	var frames := player.animated_sprite.sprite_frames
	check(frames.get_frame_count(LanSwimMotor.ANIM_IDLE) == 16 and frames.get_animation_loop(LanSwimMotor.ANIM_IDLE),
		"Idle is the 16-frame forward loop")
	check(not frames.has_animation(&"swim_idle_settle"), "No separate settle clip (the entry holds it)")
	check(worst <= 1.6, "Idle loop has no frame jump (worst step %.2f px)" % worst)
	# Hysteresis: near a threshold the current clip holds.
	var sprite := player.animated_sprite
	player.velocity.y = LanSwimMotor.DOWN_ANIM_SPEED - 10.0
	sprite.play(LanSwimMotor.ANIM_DOWN)
	check(player.swim.choose_animation(player, 0.0) == LanSwimMotor.ANIM_DOWN, "Down holds just under its threshold")
	sprite.play(LanSwimMotor.ANIM_IDLE)
	check(player.swim.choose_animation(player, 0.0) == LanSwimMotor.ANIM_IDLE, "Idle holds just under the down threshold")
	player.velocity.y = LanSwimMotor.UP_ANIM_SPEED + 10.0
	sprite.play(LanSwimMotor.ANIM_UP)
	check(player.swim.choose_animation(player, 0.0) == LanSwimMotor.ANIM_UP, "Up holds just past its threshold")
	sprite.play(LanSwimMotor.ANIM_IDLE)
	check(player.swim.choose_animation(player, 0.0) == LanSwimMotor.ANIM_IDLE, "Idle holds just past the up threshold")


func test_dive_entry() -> void:
	var bank := PIECE.instantiate() as TerrainPiece
	bank.position = Vector2(100, 500)
	bank.length = 300.0
	world.add_child(bank)
	bank.register_to(player)
	var sprite := player.animated_sprite
	# Facing away from the pool: an ordinary jump.
	await place(Vector2(250, 500), LanPlayer.AirState.GROUNDED)
	player.facing_direction = -1.0
	await step(3)
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	check(not player.swim.is_diving() and player.air_state == LanPlayer.AirState.RISING, "Jumping away from the pool is a normal jump")
	# Facing the pool from the edge: the dive.
	await place(Vector2(330, 500), LanPlayer.AirState.GROUNDED)
	player.facing_direction = 1.0
	await step(3)
	var start_x := player.position.x
	Input.action_press(&"jump")
	await step(1)
	Input.action_release(&"jump")
	check(player.swim.is_diving() and anim() == LanSwimMotor.ANIM_DIVE and sprite.frame == 0, "Jump on the bank starts the dive at frame 0 (%s %d)" % [anim(), sprite.frame])
	await step(15)
	check(is_equal_approx(player.position.x, start_x) and sprite.frame == 2, "Crouch frames 0–2 hold her on the bank (frame %d)" % sprite.frame)
	var seen: Array[int] = []
	var last_dive_frame := -1
	for i in 180:
		await step(1)
		if anim() == LanSwimMotor.ANIM_DIVE:
			if seen.is_empty() or seen[-1] != sprite.frame:
				seen.append(sprite.frame)
			last_dive_frame = sprite.frame
		else:
			break
	check(seen == [2, 3, 4, 5, 6, 7, 8, 9], "Every leap frame is shown in order: %s" % [seen])
	check(swimming() and anim() == LanSwimMotor.ANIM_ENTER and sprite.frame == 0 and last_dive_frame == 9, "Frame 9 hands over to the splash as she enters (%s %d)" % [anim(), sprite.frame])
	var row_y := canvas_origin().y + LanSwimMotor.CANVAS_SURFACE_Y * sprite.scale.y
	check(absf(row_y - volume.position.y) < 1.0, "Splash waterline (canvas row %d) on the surface (%.1f vs %.1f)" % [LanSwimMotor.CANVAS_SURFACE_Y, row_y, volume.position.y])
	# Splash → idle, frame by frame: the clip changes once, and the art never jumps —
	# during the splash every frame sits exactly where the canvas puts it relative to the
	# water; afterwards it moves only with the slow sink.
	var clips: Array[StringName] = [anim()]
	var first := canvas_origin()
	var prev := first
	var worst_splash := 0.0
	var worst_idle := 0.0
	for i in 60 * 4:
		await step(1)
		if anim() != clips[-1]:
			clips.append(anim())
		var o := canvas_origin()
		if anim() == LanSwimMotor.ANIM_ENTER:
			worst_splash = maxf(worst_splash, (o - first).length())
		else:
			worst_idle = maxf(worst_idle, (o - prev).length())
		prev = o
	check(clips == [LanSwimMotor.ANIM_ENTER, LanSwimMotor.ANIM_IDLE], "Splash (with settle) → idle once each, no flip-flop: %s" % [clips])
	check(worst_splash < 0.05, "Splash frames stay on their canvas places (drift %.2f px)" % worst_splash)
	check(worst_idle <= 1.6, "No art jump from splash into idle sinking (worst step %.2f px)" % worst_idle)
	check(is_equal_approx(sprite.offset.y, LanSwimMotor.clip_offset(anim(), sprite.frame, true).y), "Idle uses its per-frame placement (%.1f)" % sprite.offset.y)
	bank._unregister_surface()
	bank.queue_free()
