extends "../../tests/support/harness.gd"

const LAN := preload("res://scenes/player/lan/lan_player.tscn")
const BACKDROP := preload("res://assets/levels/chapter_2_underwater/cavern/environment/deep_cavern/deep_cavern_pool_1536x1024.png")
const STONE := preload("res://assets/levels/chapter_2_underwater/city/environment/terrain/stone_masonry_1254x1254.png")

const STEP_IN_SWEEP := &"step_in_sweep"
const COUNTER_UPSLASH := &"counter_upslash"
const COUNTER_SLASH := &"counter_slash"
const TURNING_UPPERCUT := &"turning_uppercut"
const TRIPLE_JUMP_SLASH := &"triple_jump_slash"
const RAISE_AND_RETURN := &"raise_and_return"
const FRAME_SIZE := Vector2i(520, 350)
const ATLAS_COLUMNS := 4
# Centiseconds per pose. Recovery includes three in-betweens after frame 13.
const SWEEP_HOLDS := [8, 7, 7, 6, 9, 3, 3, 3, 3, 3, 3, 3, 9, 3, 3, 3, 3, 8, 8]
# The four storyboard poses occupy frames 1, 9, 16 and 20.
const COUNTER_HOLDS := [5, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 9, 6, 6, 7, 8]
# Video storyboard keys at 1, 7, 13 and 20. End in the low stance.
const COUNTER_SLASH_HOLDS := [6, 3, 3, 2, 2, 3, 8, 4, 4, 3, 3, 3, 5, 3, 3, 3, 3, 3, 4, 15]
# The shared low stance, draw, raised knee and finish occupy 1, 8, 12 and 20.
const TURNING_UPPERCUT_HOLDS := [6, 4, 4, 4, 4, 4, 4, 5, 3, 2, 2, 3, 2, 2, 3, 3, 3, 4, 4, 13]
# The raised pose at frame 10 holds before the weapon returns to the left hand.
const RAISE_AND_RETURN_HOLDS := [8, 5, 4, 4, 5, 4, 3, 3, 4, 26, 5, 4, 5, 5, 6, 9]
# Landings 12 and 23 are shared. Brief grounded loading, then a fast cut into each landing.
const TRIPLE_JUMP_SLASH_HOLDS := [
	9, 5, 5, 6, 8, 5, 5, 4, 3, 2, 2,
	8, 5, 5, 6, 5, 8, 5, 5, 4, 3, 2,
	8, 6, 5, 7, 8, 6, 5, 4, 3, 2, 18,
]
# Zero-based frame indices. Lift begins just before the first airborne pose.
const TRIPLE_JUMP_ARCS := [
	{lift = 2, land = 11, height = 66.0, advance = 60.0, apex = 0.37},
	{lift = 13, land = 22, height = 72.0, advance = 66.0, apex = 0.42},
	{lift = 24, land = 32, height = 80.0, advance = 74.0, apex = 0.39},
]
# Per-pose x anchors in the original storyboard canvas. Grounded loading poses
# register against their planted boot. Airborne poses register at the pelvis.
const TRIPLE_JUMP_ANCHORS_X := [
	345, 345, 364, 391, 377, 389, 390, 396, 420, 392, 372,
	345, 345, 367, 398, 416, 413, 418, 418, 424, 434, 382,
	364, 368, 402, 436, 428, 423, 433, 444, 453, 398, 369,
]
const TRIPLE_JUMP_SOLE_LINE := 287
const FLOOR := Rect2(48, 584, 1184, 136)
const GENERAL_SPAWN := Vector2(548, 584)
const PLAYER_SPAWN := Vector2(900, 584)

var _general: AnimatedSprite2D
var _player: LanPlayer
var _animation := STEP_IN_SWEEP
var _frame_holds := SWEEP_HOLDS
var _player_spawn := PLAYER_SPAWN
var _triple_jump_clock := PackedInt32Array([0])
var _triple_jump_registration := PackedVector2Array()
var _triple_jump_tween: Tween


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the prototype atlas path after --.")
		quit(1)
		return
	if "--raise-and-return" in args:
		_animation = RAISE_AND_RETURN
		_frame_holds = RAISE_AND_RETURN_HOLDS
	elif "--triple-jump-slash" in args:
		_animation = TRIPLE_JUMP_SLASH
		_frame_holds = TRIPLE_JUMP_SLASH_HOLDS
		_player_spawn = Vector2(1050, FLOOR.position.y)
	elif "--turning-uppercut" in args:
		_animation = TURNING_UPPERCUT
		_frame_holds = TURNING_UPPERCUT_HOLDS
		_player_spawn = Vector2(1110, FLOOR.position.y)
	elif "--counter-slash" in args:
		_animation = COUNTER_SLASH
		_frame_holds = COUNTER_SLASH_HOLDS
	elif "--counter-upslash" in args:
		_animation = COUNTER_UPSLASH
		_frame_holds = COUNTER_HOLDS
	var atlas := Image.load_from_file(args[0])
	var atlas_rows := ceili(float(_frame_holds.size()) / ATLAS_COLUMNS)
	var atlas_size := Vector2i(ATLAS_COLUMNS, atlas_rows) * FRAME_SIZE
	if atlas == null or atlas.get_size() != atlas_size:
		push_error("Expected a %s pixel atlas: %s" % [atlas_size, args[0]])
		quit(1)
		return

	use_memory_progress()
	var room := Node2D.new()
	room.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(room)
	current_scene = room
	root.title = "归航星 · 沉没古城 · 残甲将军动作预览"

	var backdrop := Sprite2D.new()
	backdrop.texture = BACKDROP
	backdrop.position = Vector2(640, 348)
	backdrop.modulate = Color(0.69, 0.73, 0.78)
	room.add_child(backdrop)
	_add_floor(room)

	_general = AnimatedSprite2D.new()
	_general.sprite_frames = _build_animation(ImageTexture.create_from_image(atlas))
	_general.animation = _animation
	_general.centered = false
	_general.offset = Vector2(-203, -287)
	_general.position = GENERAL_SPAWN
	if _animation == RAISE_AND_RETURN:
		# The atlas extends 50 pixels farther left for the raising arc.
		_general.offset.x -= 50
	elif _animation == TRIPLE_JUMP_SLASH:
		# The crop starts 50 pixels farther right than the original atlas.
		_general.offset.x += 50
		for index in _frame_holds.size():
			_triple_jump_clock.append(_triple_jump_clock[-1] + _frame_holds[index])
			var sole_y := atlas.get_region(_atlas_cell(index)).get_used_rect().end.y
			_triple_jump_registration.append(Vector2(
				TRIPLE_JUMP_ANCHORS_X[0] - TRIPLE_JUMP_ANCHORS_X[index],
				TRIPLE_JUMP_SOLE_LINE - sole_y
			))
	elif _animation == TURNING_UPPERCUT:
		# The crop starts 170 pixels farther right than the original atlas.
		_general.offset.x += 170
	elif _animation == COUNTER_SLASH:
		# The forward step needs 20 more pixels of atlas room on the right.
		_general.offset.x += 20
	room.add_child(_general)

	_player = LAN.instantiate() as LanPlayer
	_player.world_min_x = FLOOR.position.x + 12.0
	_player.world_max_x = FLOOR.end.x - 12.0
	_player.fallback_ground_y = 900.0
	_player.z_index = 12
	room.add_child(_player)
	_player.register_ground_surface(Rect2(FLOOR.position, Vector2(FLOOR.size.x, 1.0)))
	_player.reset_after_map_fall(_player_spawn)
	root.window_input.connect(_on_window_input)


func _add_floor(room: Node2D) -> void:
	var body := StaticBody2D.new()
	body.position = FLOOR.get_center()
	var shape := RectangleShape2D.new()
	shape.size = FLOOR.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var texture := Sprite2D.new()
	texture.texture = STONE
	texture.region_enabled = true
	texture.region_rect = Rect2(Vector2(48, 220), FLOOR.size)
	texture.modulate = Color(0.51, 0.60, 0.62)
	body.add_child(texture)
	room.add_child(body)


func _build_animation(atlas: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation(_animation)
	frames.set_animation_speed(_animation, 100.0)
	frames.set_animation_loop(_animation, false)
	for index in _frame_holds.size():
		var cell := AtlasTexture.new()
		cell.atlas = atlas
		cell.filter_clip = true
		cell.region = _atlas_cell(index)
		frames.add_frame(_animation, cell, _frame_holds[index])
	return frames


func _atlas_cell(index: int) -> Rect2i:
	@warning_ignore("integer_division")
	var row := index / ATLAS_COLUMNS
	return Rect2i(Vector2i(index % ATLAS_COLUMNS, row) * FRAME_SIZE, FRAME_SIZE)


func _sample_triple_jump(elapsed: float) -> void:
	var frame_index := 0
	while frame_index + 1 < _frame_holds.size() and elapsed >= _triple_jump_clock[frame_index + 1]:
		frame_index += 1

	var travel := Vector2.ZERO
	for arc in TRIPLE_JUMP_ARCS:
		var lift := _triple_jump_clock[arc.lift] - 2.0
		var land := float(_triple_jump_clock[arc.land])
		var progress := clampf(inverse_lerp(lift, land, elapsed), 0.0, 1.0)
		var peak_distance := inverse_lerp(arc.apex, 1.0, progress) if progress > arc.apex \
			else inverse_lerp(arc.apex, 0.0, progress)
		travel.y -= arc.height * (1.0 - peak_distance * peak_distance)
		# Take the step in the air, with the fastest forward travel on the way down.
		travel.x += arc.advance * smoothstep(0.0, 1.0, pow(progress, 1.35))

	_general.position = GENERAL_SPAWN + travel + _triple_jump_registration[frame_index]
	_general.frame = frame_index


func _is_action_playing() -> bool:
	if _animation == TRIPLE_JUMP_SLASH:
		return _triple_jump_tween != null and _triple_jump_tween.is_running()
	return _general.is_playing()


func _on_window_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_1 and not _is_action_playing():
		if _animation == TRIPLE_JUMP_SLASH:
			_sample_triple_jump(0.0)
			var duration := float(_triple_jump_clock[-1])
			_triple_jump_tween = create_tween()
			_triple_jump_tween.tween_method(_sample_triple_jump, 0.0, duration, duration / 100.0)
		else:
			_general.stop()
			_general.play(_animation)
	elif key == KEY_R:
		if _animation == TRIPLE_JUMP_SLASH:
			if _triple_jump_tween != null:
				_triple_jump_tween.kill()
			_sample_triple_jump(0.0)
		else:
			_general.stop()
		_player.reset_after_map_fall(_player_spawn)
