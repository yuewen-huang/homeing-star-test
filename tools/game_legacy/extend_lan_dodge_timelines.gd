extends SceneTree

const LIBRARY_PATH := "res://assets/sideview/characters/lan/lan_combat_timelines.tres"


func _initialize() -> void:
	var library := load(LIBRARY_PATH) as AnimationLibrary
	assert(library != null, "Lan combat timeline library must exist before dodge migration")
	add_back_dodge(library)
	add_dodge_attack_1(library)
	add_dodge_attack_2(library)
	add_dodge_attack_3(library, &"dodge_attack_3x_z")
	add_dodge_attack_3(library, &"dodge_attack_3x_z1")
	var error := ResourceSaver.save(library, LIBRARY_PATH)
	if error != OK:
		push_error("Could not save Lan dodge timelines: %s" % error_string(error))
		quit(1)
		return
	print("Extended %s with dodge timelines" % LIBRARY_PATH)
	quit()


func add_back_dodge(library: AnimationLibrary) -> void:
	var animation := create_frame_animation(24, 1.0 / 35.0)
	var events := add_method_track(animation)
	insert_method(animation, events, 3.0 / 35.0, &"_timeline_set_back_dodge_invulnerable", [true])
	insert_method(animation, events, 9.0 / 35.0, &"_timeline_open_back_dodge_attack_cancel", [])
	insert_method(animation, events, 15.0 / 35.0, &"_timeline_set_back_dodge_invulnerable", [false])
	set_animation(library, &"back_dodge", animation)


func add_dodge_attack_1(library: AnimationLibrary) -> void:
	var animation := create_frame_animation(19, 1.0 / 25.0)
	var effects := add_method_track(animation)
	for frame in 19:
		insert_method(animation, effects, frame / 25.0, &"_timeline_dodge_attack_effect_frame", [frame, &"dodge_attack_1x"])
	insert_method(animation, effects, 14.0 / 25.0, &"_timeline_dodge_attack_1_brake", [])
	set_animation(library, &"dodge_attack_1x", animation)


func add_dodge_attack_2(library: AnimationLibrary) -> void:
	var animation := create_frame_animation(16, 1.0 / 25.0)
	var effects := add_method_track(animation)
	for frame in 16:
		insert_method(animation, effects, frame / 25.0, &"_timeline_dodge_attack_effect_frame", [frame, &"dodge_attack_2x"])
	insert_method(animation, effects, 8.0 / 25.0, &"_timeline_dodge_attack_2_launch", [])
	insert_method(animation, effects, 14.0 / 25.0, &"_timeline_dodge_attack_2_fall", [])
	set_animation(library, &"dodge_attack_2x", animation)


func add_dodge_attack_3(library: AnimationLibrary, animation_name: StringName) -> void:
	var animation := create_frame_animation(37, 1.0 / 25.0)
	var events := add_method_track(animation)
	for frame in 37:
		insert_method(animation, events, frame / 25.0, &"_timeline_dodge_attack_3_effect_frame", [frame])
	insert_method(animation, events, 12.0 / 25.0, &"_timeline_dodge_attack_3_teleport", [])
	insert_method(animation, events, 27.0 / 25.0, &"_timeline_dodge_attack_3_recovery", [])
	set_animation(library, animation_name, animation)


func create_frame_animation(frame_count: int, frame_duration: float) -> Animation:
	var animation := Animation.new()
	animation.length = frame_count * frame_duration
	animation.loop_mode = Animation.LOOP_NONE
	var frames := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(frames, NodePath("AnimatedSprite2D:frame"))
	animation.value_track_set_update_mode(frames, Animation.UPDATE_DISCRETE)
	for frame in frame_count:
		animation.track_insert_key(frames, frame * frame_duration, frame)
	return animation


func add_method_track(animation: Animation) -> int:
	var track := animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(track, NodePath("."))
	return track


func insert_method(animation: Animation, track: int, time: float, method: StringName, args: Array) -> void:
	animation.track_insert_key(track, time, {"method": method, "args": args})


func set_animation(library: AnimationLibrary, animation_name: StringName, animation: Animation) -> void:
	if library.has_animation(animation_name):
		library.remove_animation(animation_name)
	library.add_animation(animation_name, animation)
