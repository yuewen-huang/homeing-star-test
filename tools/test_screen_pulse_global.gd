extends SceneTree
## Full-screen effects (2026-10-14): the dodge bullet-time visual is global (every LanPlayer
## owns one; it echoes whatever attacker was dodged), and the unavoidable full-screen moments
## (red counter / guard break, god statue) use the same tinted vignette pulse instead of the
## RGB split, speed lines or a flat overlay.

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func run() -> void:
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.select_combo(2)
	var player: LanPlayer = room.player
	var deer: DeerBoss = room.adapter.deer
	var visual := player.dodge_bullet_time_visual
	check(visual != null and visual.get_parent() == player.get_parent(), "Every player owns a bullet-time visual in its world (outside the master fight too)")
	player.dodge_evaded_attack.emit(deer, LanPlayer.DODGE_BULLET_TIME_DURATION)
	check(visual.remaining > 0.0 and visual.boss_sprite == deer.animated_sprite, "Dodging the deer starts bullet time and echoes the deer's body")
	for i in 20: await process_frame
	var ghosts := visual.get_children().filter(func(n: Node) -> bool: return n is Sprite2D)
	check(not ghosts.is_empty(), "Blue afterimages of the dodged deer appear (%d)" % ghosts.size())
	var strike := Node2D.new()
	room.add_child(strike)
	player.dodge_evaded_attack.emit(strike, 1.0)
	check(visual.boss_sprite == null and visual.remaining > 0.0, "A dodged attacker without a body still gets the vignette and ring")
	strike.free()

	# Red counter: vignette pulse, no RGB split.
	feedback.screen_fx.clear()
	feedback.emit_parry_success(deer, CombatAttackData.new(&"t", deer, 20, 12, 180.0, 0.0, CombatAttackData.DangerType.COUNTERABLE_DANGER), deer.global_position)
	check(feedback.screen_fx.pulse_active() and not feedback.screen_fx._split.visible and feedback.screen_fx._lines_remaining <= 0.0, "Red counter uses the tinted vignette pulse instead of the RGB split and speed lines")
	check(feedback.screen_fx._pulse.size == Vector2(root.get_viewport().get_visible_rect().size), "Pulse covers the whole screen (size %s)" % feedback.screen_fx._pulse.size)
	var tint: Vector3 = feedback.screen_fx._pulse_material.get_shader_parameter(&"tint")
	check(tint.x > tint.y and tint.x > tint.z, "Red counter pulse is red-tinted")
	feedback.screen_fx.stop_pulse()
	check(not feedback.screen_fx.pulse_active(), "A pulse can be stopped at once")
	while Engine.time_scale < 1.0: await process_frame
	print("SCREEN PULSE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
