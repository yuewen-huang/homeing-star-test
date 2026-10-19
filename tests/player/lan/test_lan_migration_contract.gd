extends SceneTree


func _initialize() -> void:
	call_deferred("run_test")


func require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func run_test() -> void:
	var room := Node2D.new()
	root.add_child(room)
	current_scene = room
	var player := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate() as LanPlayer
	player.world_min_x = -1000.0
	player.world_max_x = 1000.0
	room.add_child(player)
	await process_frame
	if not require(player.combat_timeline != null, "Lan combat timeline player is missing"):
		return
	if not require(player.combat_timeline.callback_mode_process == 0, "Lan combat timeline is not physics-processed"):
		return
	if not require(player.combat_timeline.get_animation_library(&"") != null, "Lan combat timeline library is missing"):
		return
	if not require(
		player.combat_timeline.get_animation_list() == PackedStringArray([
			"attack_1x", "attack_2x", "attack_2x_1", "attack_2x_2", "attack_3x",
			"back_dodge", "dodge_attack_1x", "dodge_attack_2x",
			"dodge_attack_3x_z", "dodge_attack_3x_z1",
		]),
		"Lan timeline ownership changed unexpectedly",
	):
		return
	var attack_1_timeline := player.combat_timeline.get_animation(&"attack_1x")
	if not require(attack_1_timeline != null and is_equal_approx(attack_1_timeline.length, 0.64), "Attack 1 timeline length changed"):
		return
	if not require(attack_1_timeline.get_track_count() == 2, "Attack 1 timeline track count changed"):
		return
	if not require(
		attack_1_timeline.track_get_type(0) == Animation.TYPE_VALUE
		and attack_1_timeline.track_get_path(0) == NodePath("AnimatedSprite2D:frame")
		and attack_1_timeline.track_get_key_count(0) == 16,
		"Attack 1 character frame timeline changed",
	):
		return
	for frame_index in 16:
		if not require(attack_1_timeline.track_get_key_value(0, frame_index) == frame_index, "Attack 1 character frame order changed"):
			return
	if not require(
		attack_1_timeline.track_get_type(1) == Animation.TYPE_METHOD
		and attack_1_timeline.track_get_key_count(1) == 10,
		"Attack 1 event timeline changed",
	):
		return
	for effect_frame in 9:
		var event: Dictionary = attack_1_timeline.track_get_key_value(1, effect_frame)
		if not require(
			event.get("method") == &"_timeline_attack_1_effect_frame"
			and event.get("args") == [effect_frame],
			"Attack 1 effect frame event changed",
		):
			return
	var finish_event: Dictionary = attack_1_timeline.track_get_key_value(1, 9)
	if not require(finish_event.get("method") == &"_timeline_finish_attack_effect", "Attack 1 effect finish event changed"):
		return

	var attack_2_timeline_contracts := {
		&"attack_2x": {"length": 1.0, "frames": 25, "effect_frames": 11, "effect_start": 0.2},
		&"attack_2x_1": {"length": 0.24, "frames": 6, "effect_frames": 6, "effect_start": 0.0},
		&"attack_2x_2": {"length": 0.4, "frames": 10, "effect_frames": 6, "effect_start": 0.08},
	}
	for animation_name: StringName in attack_2_timeline_contracts:
		var contract: Dictionary = attack_2_timeline_contracts[animation_name]
		var timeline := player.combat_timeline.get_animation(animation_name)
		if not require(
			timeline != null
			and is_equal_approx(timeline.length, contract["length"])
			and timeline.track_get_key_count(0) == contract["frames"]
			and timeline.track_get_key_count(1) == contract["effect_frames"] + 1,
			"Attack 2 timeline structure changed for %s" % animation_name,
		):
			return
		if not require(is_equal_approx(timeline.track_get_key_time(1, 0), contract["effect_start"]), "Attack 2 effect start changed for %s" % animation_name):
			return
		for effect_frame in contract["effect_frames"]:
			var event: Dictionary = timeline.track_get_key_value(1, effect_frame)
			if not require(
				event.get("method") == &"_timeline_attack_2_effect_frame"
				and event.get("args") == [effect_frame, animation_name],
				"Attack 2 effect event changed for %s" % animation_name,
			):
				return
	var attack_3_timeline := player.combat_timeline.get_animation(&"attack_3x")
	if not require(
		attack_3_timeline != null
		and is_equal_approx(attack_3_timeline.length, 1.05)
		and attack_3_timeline.track_get_key_count(0) == 30
		and attack_3_timeline.track_get_key_count(1) == 31,
		"Attack 3 timeline structure changed",
	):
		return
	var dodge_timeline_frames := {
		&"back_dodge": 24,
		&"dodge_attack_1x": 19,
		&"dodge_attack_2x": 16,
		&"dodge_attack_3x_z": 37,
		&"dodge_attack_3x_z1": 37,
	}
	for animation_name: StringName in dodge_timeline_frames:
		var timeline: Animation = player.combat_timeline.get_animation(animation_name)
		if not require(
			timeline != null
			and timeline.track_get_path(0) == NodePath("AnimatedSprite2D:frame")
			and timeline.track_get_key_count(0) == dodge_timeline_frames[animation_name],
			"Dodge timeline structure changed for %s" % animation_name,
		):
			return
	var back_dodge_timeline: Animation = player.combat_timeline.get_animation(&"back_dodge")
	if not require(
		back_dodge_timeline.track_get_key_value(1, 0).get("method") == &"_timeline_set_back_dodge_invulnerable"
		and back_dodge_timeline.track_get_key_value(1, 1).get("method") == &"_timeline_open_back_dodge_attack_cancel"
		and back_dodge_timeline.track_get_key_value(1, 2).get("args") == [false],
		"Back dodge windows are not owned by timeline events",
	):
		return

	var expected_frames := {
		&"attack_1x": 16,
		&"attack_2x": 25,
		&"attack_2x_1": 6,
		&"attack_2x_2": 10,
		&"attack_3x": 30,
		&"back_dodge": 24,
		&"dodge_attack_1x": 19,
		&"dodge_attack_2x": 16,
		&"dodge_attack_3x_z": 37,
		&"dodge_attack_3x_z1": 37,
		&"jump_attack_1x": 9,
		&"jump_attack_2x": 8,
		&"instant_dash": 15,
		&"parry": 5,
		&"parry_success": 9,
		&"parry_failure": 11,
		&"ultimate_cast": 18,
		&"normal_hit": 22,
		&"roll_landing": 9,
	}
	for animation_name: StringName in expected_frames:
		if not require(
			player.animated_sprite.sprite_frames.get_frame_count(animation_name) == expected_frames[animation_name],
			"Migration contract frame count changed for %s" % animation_name,
		):
			return

	if not require(
		player.BACK_DODGE_INVULNERABLE_START_FRAME == 3
		and player.BACK_DODGE_INVULNERABLE_END_FRAME == 14
		and player.BACK_DODGE_ATTACK_CANCEL_FRAME == 9,
		"Back dodge windows changed before timeline migration",
	):
		return
	if not require(
		player.DODGE_ATTACK_2_LAUNCH_FRAME == 8
		and player.DODGE_ATTACK_2_FALL_FRAME == 14
		and player.DODGE_ATTACK_3_TELEPORT_FRAME == 12
		and player.DODGE_ATTACK_3_IMPACT_FRAME == 22
		and player.DODGE_ATTACK_3_RECOVERY_FRAME == 27,
		"Phased dodge attack events changed before timeline migration",
	):
		return
	if not require(
		player.INSTANT_DASH_TELEPORT_FRAME == 4
		and player.ULTIMATE_MAGIC_START_FRAME == 4,
		"Skill event frames changed before timeline migration",
	):
		return

	var effect_definitions: Array[AttackEffectDefinition] = [
		LanAttackEffectCatalog.attack_1x(),
		LanAttackEffectCatalog.attack_2x(),
		LanAttackEffectCatalog.attack_2x_1(),
		LanAttackEffectCatalog.attack_2x_2(),
		LanAttackEffectCatalog.attack_3x(player.ATTACK_3_FPS),
		LanAttackEffectCatalog.dodge_attack_1x(player.DODGE_ATTACK_1_FPS),
		LanAttackEffectCatalog.dodge_attack_2x(player.DODGE_ATTACK_2_FPS),
		LanAttackEffectCatalog.dodge_attack_3x(player.DODGE_ATTACK_3_SPRITE_POSITION_Y),
		LanAttackEffectCatalog.jump_attack_1x(player.JUMP_ATTACK_1X_FPS),
		LanAttackEffectCatalog.jump_attack_2x(player.JUMP_ATTACK_2X_FPS),
		LanAttackEffectCatalog.instant_dash(),
	]
	for definition in effect_definitions:
		if not require(definition.texture != null and definition.frame_count > 0, "Attack effect definition is incomplete"):
			return
	if not require(effect_definitions[0].frame_count == 9 and effect_definitions[1].frame_count == 11, "Ground combo FX lengths changed"):
		return
	if not require(effect_definitions[6].frame_count == 16 and effect_definitions[7].frame_count == 37, "Dodge attack FX lengths changed"):
		return

	player.start_attack_2x_1()
	player.combat_timeline.advance(0.001)
	if not require(player.active_attack_effects.size() == 1, "Attack 2 variant 1 did not execute its frame-zero FX event"):
		return
	if not require(player.active_attack_effects[0].timeline_driven, "Attack 2 variant 1 FX retained an independent clock"):
		return
	player.cancel_uncommitted_attack_effects()
	await process_frame
	player.attack_state = player.AttackState.NONE

	player.air_state = player.AirState.GROUNDED
	player.start_back_dodge()
	player.combat_timeline.advance(3.0 / 35.0 + 0.001)
	if not require(player.is_invulnerable() and not player.back_dodge_attack_cancel_open, "Back dodge timeline did not open invulnerability on frame 3"):
		return
	player.combat_timeline.advance(6.0 / 35.0)
	if not require(player.back_dodge_attack_cancel_open, "Back dodge timeline did not open its attack branch on frame 9"):
		return
	player.cancel_uncommitted_attack_effects()
	player.ground_action_state = player.GroundActionState.NONE

	player.start_dodge_attack_1x()
	player.combat_timeline.advance(0.001)
	if not require(player.active_attack_effects.size() == 1 and player.active_attack_effects[0].timeline_driven, "Dodge attack 1 retained an independent FX clock"):
		return
	player.combat_timeline.advance(14.0 / 25.0)
	if not require(player.dodge_attack_1_braking, "Dodge attack 1 brake is not a timeline event"):
		return
	player.cancel_uncommitted_attack_effects()
	await process_frame
	player.attack_state = player.AttackState.NONE

	player.start_dodge_attack_2x()
	player.combat_timeline.advance(8.0 / 25.0 + 0.001)
	if not require(player.dodge_attack_2_launched and player.air_state == player.AirState.RISING, "Dodge attack 2 launch is not a timeline event"):
		return
	player.combat_timeline.advance(6.0 / 25.0)
	if not require(player.dodge_attack_2_fall_started and player.air_state == player.AirState.FALLING, "Dodge attack 2 fall is not a timeline event"):
		return
	player.cancel_uncommitted_attack_effects()
	await process_frame
	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.GROUNDED

	player.start_dodge_attack_3x()
	player.combat_timeline.advance(12.0 / 25.0 + 0.001)
	if not require(player.dodge_attack_3_teleported and player.air_state == player.AirState.FALLING, "Dodge attack 3 teleport is not a timeline event"):
		return
	if not require(player.active_attack_effects.size() == 2 and player.active_attack_effects.all(func(effect): return effect.timeline_driven), "Dodge attack 3 FX layers do not share the character timeline"):
		return
	player.cancel_uncommitted_attack_effects()
	await process_frame
	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.GROUNDED

	if not require(player.can_accept_parry_action(), "Idle ground state must accept K"):
		return
	player.start_attack_1x()
	if not require(player.can_accept_parry_action(), "Interruptible ground attack must accept K"):
		return
	player.finish_ground_attack()
	player.start_back_dodge()
	if not require(not player.can_accept_parry_action(), "Back dodge must reject K"):
		return
	player.ground_action_state = player.GroundActionState.NONE
	player.attack_state = player.AttackState.DODGE_ATTACK_2X
	if not require(not player.can_accept_parry_action(), "Dodge attack 2 must reject K"):
		return
	player.attack_state = player.AttackState.NONE
	player.air_state = player.AirState.FALLING
	if not require(not player.can_accept_parry_action(), "Airborne state must reject K"):
		return

	print("PASS: Lan migration frame, event, effect, and parry contracts are frozen")
	quit(0)
