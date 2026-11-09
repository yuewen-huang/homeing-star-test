extends SceneTree
## Lan's special attack (I): shared skill-hit emphasis, timing curve, lunge, trimmed
## damage windows, input buffer / combo cancel / recovery cancel and boss skill poise.

class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass

class Receiver extends DamageReceiver2D:
	var hits := 0
	var poise_bar := false
	var immune := false
	func receive_hit(_damage: int, _source_position: Vector2) -> void:
		hits += 1
	func receive_skill_hit(_hit: RefCounted, source_position: Vector2) -> void:
		hits += 1
		if immune: return
		(get_node("/root/CombatFeedback") as CombatFeedbackService).emit_receiver_hit(self, global_position, source_position)
	func has_poise_bar() -> bool: return poise_bar
	var broken_poise := false
	func is_poise_broken() -> bool: return broken_poise

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func receiver_at(parent: Node, point: Vector2) -> Receiver:
	var receiver := Receiver.new()
	receiver.position = point
	var area := Area2D.new()
	area.name = "Hurtbox"
	area.collision_layer = 2
	area.collision_mask = 0
	area.add_to_group("hurtbox")
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2, 2)
	collision.shape = rect
	area.add_child(collision)
	receiver.add_child(area)
	parent.add_child(receiver)
	return receiver

func settle() -> void:
	for i in 4: await physics_frame

func run() -> void:
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var world := Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	await process_frame

	# --- A1: emphasis only through settle_skill_hit, scaled by form, skipped for immune receivers.
	var receiver := receiver_at(world, Vector2(5000, 0))
	var plain := SkillHitContext.new(&"skill_feedback_sample", 18)
	var serial := feedback.hit_stop_serial
	feedback.settle_skill_hit(receiver, plain, Vector2.ZERO)
	check(feedback.hit_stop_serial == serial + 1 and is_zero_approx(feedback.punch_remaining), "Skill without emphasis keeps the receiver's ordinary feedback")
	var skill := SkillHitContext.new(&"skill_feedback_sample", 18)
	skill.emphasis = SkillHitContext.Emphasis.SKILL
	serial = feedback.hit_stop_serial
	feedback.settle_skill_hit(receiver, skill, Vector2.ZERO)
	check(feedback.hit_stop_serial == serial + 2, "Skill emphasis requests a longer hit-stop over the receiver's own")
	check(is_equal_approx(feedback.punch_amount, CombatFeedbackService.SKILL_PUNCH) and feedback.skill_layer_player.playing, "Skill emphasis punches the camera and layers the heavy slash sound")
	check(feedback._settling_skill == null, "Settlement context is cleared after the hit")
	feedback._reset_punch()
	var heavy := SkillHitContext.new(&"skill_feedback_sample", 60, false, false, false, true)
	heavy.emphasis = SkillHitContext.Emphasis.HEAVY_SKILL
	feedback.settle_skill_hit(receiver, heavy, Vector2.ZERO)
	check(is_equal_approx(feedback.punch_amount, CombatFeedbackService.TIER_PUNCH[CombatFeedbackService.Tier.HEAVY]), "Max form uses the HEAVY tier punch")
	feedback._reset_punch()
	receiver.immune = true
	serial = feedback.hit_stop_serial
	feedback.settle_skill_hit(receiver, skill, Vector2.ZERO)
	check(feedback.hit_stop_serial == serial and receiver.hits == 4, "Immune receivers get the hit call but no emphasis")
	receiver.queue_free()
	await create_timer(0.3, true, false, true).timeout
	Engine.time_scale = 1.0

	# --- A8: BossBase honours skill poise (shields removed on a regional core).
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var progress := LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	room.select_boss(4)
	var core := room.adapter.boss as RegionalCoreBoss
	core.set_physics_process(false)
	room.shield_toggles[0].button_pressed = false
	room.shield_toggles[1].button_pressed = false
	var poise := core.combat_stats.poise
	var poised := SkillHitContext.new(&"skill_feedback_sample", 18)
	poised.poise_damage = 15
	core.receive_skill_hit(poised, Vector2(600, 555))
	check(core.combat_stats.poise == poise, "Default boss ignores skill poise damage")
	poise = core.combat_stats.poise
	core.receive_skill_hit(SkillHitContext.new(&"skill_feedback_sample", 18), Vector2(600, 555))
	check(core.combat_stats.poise == poise, "Skill hits without poise damage leave poise alone")
	room.shield_toggles[0].button_pressed = true
	poise = core.combat_stats.poise
	core.receive_skill_hit(poised, Vector2(600, 555))
	check(core.combat_stats.poise == poise, "A shield still blocks skill poise")
	var finished: Node = room
	current_scene = null
	finished.free()
	await process_frame
	progress.free()
	root.add_child(original)
	await create_timer(0.3, true, false, true).timeout
	Engine.time_scale = 1.0
	print("LAN SPECIAL CHECKS: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
