extends SceneTree
## Normal-attack hit backstep (2026-10-14): a landed normal attack steps back only when Lan
## is pressed against or inside the target's hurtbox, restoring at most
## NORMAL_ATTACK_MIN_GAP, so a run of hits cannot drift out of range.

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

class Target extends DamageReceiver2D:
	func receive_hit(_damage: int, _source_position: Vector2) -> void: pass

func make_target(parent: Node, at: Vector2, width: float) -> Target:
	var target := Target.new()
	var hurtbox := Area2D.new(); hurtbox.name = "Hurtbox"
	var shape := CollisionShape2D.new()   # unnamed on purpose, like enemies built in code
	var rect := RectangleShape2D.new(); rect.size = Vector2(width, 80)
	shape.shape = rect; shape.position = Vector2(0, -40)
	hurtbox.add_child(shape); target.add_child(hurtbox)
	parent.add_child(target)
	target.global_position = at
	return target

func run() -> void:
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false)
	var player: LanPlayer = room.player
	player.set_physics_process(false)
	var target := make_target(room, Vector2(600, 555), 60.0)
	var edge := 600.0 - 30.0
	player.facing_direction = 1.0
	for case in [[40.0, 0.0], [LanPlayer.NORMAL_ATTACK_MIN_GAP, 0.0], [5.0, LanPlayer.NORMAL_ATTACK_MIN_GAP - 5.0], [-20.0, LanPlayer.NORMAL_ATTACK_HIT_BACKSTEP_DISTANCE]]:
		player.global_position = Vector2(edge - float(case[0]), 555)
		var step := player.normal_attack_backstep_distance(target)
		check(is_equal_approx(step, float(case[1])), "Facing right %.0f px from the hurtbox edge steps back %.0f px (got %.1f)" % [case[0], case[1], step])
	player.facing_direction = -1.0
	player.global_position = Vector2(600.0 + 30.0 + 40.0, 555)
	check(is_zero_approx(player.normal_attack_backstep_distance(target)), "Facing left at a distance does not step back")
	player.global_position = Vector2(600.0 + 30.0 + 2.0, 555)
	check(is_equal_approx(player.normal_attack_backstep_distance(target), LanPlayer.NORMAL_ATTACK_MIN_GAP - 2.0), "Facing left pressed against the target steps back only to the minimum gap")

	# A run of landed hits from a normal distance never starts a backstep.
	player.facing_direction = 1.0
	player.global_position = Vector2(edge - 30.0, 555)
	var effect := Node.new()
	room.add_child(effect)
	player.active_attack_effects.append(effect)
	player.attack_state = LanPlayer.AttackState.ATTACK_1X
	for i in 5: player._on_attack_effect_hit_landed(target, effect)
	check(is_zero_approx(player.normal_attack_hit_backstep_remaining), "Five hits from 30 px away start no backstep (no drift out of range)")
	player.global_position = Vector2(edge + 10.0, 555)
	player._on_attack_effect_hit_landed(target, effect)
	check(player.normal_attack_hit_backstep_remaining > 0.0 and is_equal_approx(player.normal_attack_hit_backstep_distance, LanPlayer.NORMAL_ATTACK_MIN_GAP + 10.0), "A hit from 10 px inside the target backs out to the minimum gap (%.0f px)" % player.normal_attack_hit_backstep_distance)
	player.active_attack_effects.erase(effect)
	player.attack_state = LanPlayer.AttackState.NONE
	print("LAN ATTACK BACKSTEP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
