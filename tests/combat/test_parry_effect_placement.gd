extends SceneTree
## Guard effect placement (2026-10-14): parry, red parry and blocked-hit impacts land on Lan's
## blade toward the attacker (not the hurtbox origin at her feet), and the red counter (global,
## LanClashVisual since 2026-10-16) lands on any attacker's counter point.

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func effects() -> Array:
	return root.get_tree().get_nodes_in_group(CombatImpactEffect.GROUP)

func clear_effects() -> void:
	for effect in effects(): effect.free()

func run() -> void:
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var was_invincible := assist.player_invincible
	assist.player_invincible = false
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.select_combo(2)
	var player: LanPlayer = room.player
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false); player.set_physics_process(false)
	player.global_position.x = deer.global_position.x - 150.0

	var right := player.defense_contact_point(deer.global_position)
	var left := player.defense_contact_point(player.global_position - Vector2(100, 0))
	check(right - player.global_position == LanPlayer.DEFENSE_CONTACT_OFFSET, "Blade point sits in front of Lan toward an attacker on the right (%s)" % (right - player.global_position))
	check(left.x < player.global_position.x and is_equal_approx(left.y, right.y), "Blade point flips toward an attacker on the left")
	check(right.y < player.global_position.y - 20.0, "Blade point is at hand height, not on the ground")

	# Real settlement on a plain LanPlayer (the dev-room player ignores hits): a normal parry
	# reports the blade point, whatever contact the hitbox had.
	var guard := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	guard.world_min_x = -1000.0; guard.world_max_x = 3000.0
	room.add_child(guard)
	guard.set_physics_process(false)
	await process_frame
	guard.global_position = player.global_position
	check(guard.parry_cue._display != null and guard.parry_cue._display.texture is AtlasTexture, "Lan's closing guard cue plays from the baked atlas")
	right = guard.defense_contact_point(deer.global_position)
	var hitbox := CombatHitbox2D.new()
	room.add_child(hitbox); hitbox.set_physics_process(false)
	var hurtbox := guard.get_node("Hurtbox") as CombatHurtbox2D
	clear_effects()
	guard.start_parry(); guard.animated_sprite.frame = 3; guard.on_player_animation_frame_changed()
	var normal := CombatAttackData.new(&"t", deer, 20, 12, 180.0, 0.0)
	var result := hurtbox.receive_attack(normal)
	hitbox._complete_hit(guard, hurtbox.global_position, normal, result)
	var spawned := effects()
	check(result == CombatHitResult.Type.PARRY_SUCCESS and spawned.size() == 1 and spawned[0].kind == CombatImpactEffect.Kind.PARRY, "Normal parry spawns the parry impact")
	check(not spawned.is_empty() and spawned[0].global_position == right, "Parry impact lands on the blade, not at Lan's feet (%s)" % (spawned[0].global_position if not spawned.is_empty() else Vector2.ZERO))
	while Engine.time_scale < 1.0: await process_frame

	# Guard failure (early parry): the blocked-hit spark is also on the blade.
	clear_effects()
	guard.parry_chain.cancel()
	guard.play_idle(); guard.defense_state = LanPlayer.DefenseState.NONE
	guard.start_parry_nothing()
	result = guard.receive_combat_hit(CombatAttackData.new(&"t", deer, 20, 12, 180.0, 0.0))
	spawned = effects()
	var blocked_at: Vector2 = spawned[0].global_position if not spawned.is_empty() else Vector2.INF
	check(result == CombatHitResult.Type.PARRY_FAILURE and spawned.size() == 1 and blocked_at == right,
		"Blocked-hit spark lands on the blade (result=%s, count=%d, at=%s, blade=%s)" % [CombatHitResult.Type.keys()[result], spawned.size(), blocked_at, right])
	while Engine.time_scale < 1.0: await process_frame

	# Red counter: global (every Lan's clash visual), landing on the deer's chest light.
	check(player.get(&"red_counter_slash_visual") == null and player.clash_visual != null and player.clash_visual.get_parent() == player, "Every player owns the clash visual; the painted counter slash is gone")
	check(LanClashVisual.counter_point(deer) == deer.get_counter_slash_point(), "The counter lands on the deer's own counter point")
	check(deer.get_counter_slash_point().distance_to(deer.get_parent().to_global(deer.vfx.chest())) < 0.01, "Deer counter point is its chest light")

	# An attacker without a counter point gets the middle of its sprite.
	var plain := Node2D.new()
	room.add_child(plain)
	plain.global_position = Vector2(500, 500)
	check(LanClashVisual.counter_point(plain) == Vector2(500, 500 - LanClashVisual.FALLBACK_HEIGHT), "Bare attacker falls back above its origin")
	plain.free()

	# The master keeps its old slash position but no longer owns a copy.
	var master := load("res://scenes/bosses/master/master_boss.tscn").instantiate() as Node2D
	check(master.get_node_or_null("RedParryEffect") == null, "Master scene no longer carries its own red parry effect")
	master.position = Vector2(300, 555)
	check(master.call(&"get_counter_slash_point") == Vector2(300, 555 - 128), "Master counter point keeps the original spot above its origin")
	master.free()

	assist.player_invincible = was_invincible
	print("PARRY EFFECT PLACEMENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
