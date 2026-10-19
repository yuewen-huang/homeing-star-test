extends SceneTree

class Receiver extends DamageReceiver2D:
	var hits := 0
	func receive_hit(_damage: int, _source_position: Vector2) -> void:
		hits += 1

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for i in range(5):
		await physics_frame

func receiver_at(parent: Node, point: Vector2) -> Receiver:
	var receiver := Receiver.new()
	receiver.position = point
	var area := Area2D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.add_to_group("hurtbox")
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 1.0
	collision.shape = circle
	area.add_child(collision)
	receiver.add_child(area)
	parent.add_child(receiver)
	return receiver

func run_checks() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
		return
	for config in [LanAttackEffectCatalog.attack_2x_1(), LanAttackEffectCatalog.attack_2x_2()]:
		assert(config.frame_size == Vector2i(180, 61))
		assert(config.texture.get_width() == 540 and config.texture.get_height() == 122)
		for direction in [-1.0, 1.0]:
			var room := Node2D.new()
			root.add_child(room)
			var owner := Node2D.new()
			room.add_child(owner)
			var effect = load("res://scenes/player/lan/lan_attack_effect.tscn").instantiate()
			effect.setup(owner, direction, config, true)
			owner.add_child(effect)
			var targets: Array[Receiver] = []
			for spec in config.hitboxes[2]:
				# Probe the forward cap of each band, including the newly extended reach.
				var point: Vector2 = spec.center - Vector2(config.frame_size) * 0.5
				var axis := Vector2(cos(spec.angle), sin(spec.angle))
				point -= axis * (spec.length * 0.5 - 1.0)
				if direction > 0.0:
					point.x = -point.x
				point += Vector2(direction * config.sprite_offset.x, config.sprite_offset.y)
				point = point * config.visual_scale + config.sprite_position
				targets.append(receiver_at(room, point))
			var distant := receiver_at(room, Vector2(direction * 500.0, -43.0))
			await settle()
			for target in targets:
				assert(target.hits == 0, "Startup must not deal damage")
			effect.set_timeline_frame(2)
			await settle()
			for target in targets:
				assert(target.hits == 1, "Edited blade cap must hit in either facing direction")
			assert(distant.hits == 0, "Target beyond the slash must not be hit")
			effect.set_timeline_frame(3)
			await settle()
			for target in targets:
				assert(target.hits == 1, "One attack must not damage the same target twice")
			for frame in range(6):
				effect.set_timeline_frame(frame)
				assert(effect.hitbox.monitoring == (frame in [1,2,3,4]), "Active damage window changed")
			room.queue_free()
			await process_frame
	print("PASS: both edited attacks, both facings, extended blade caps, misses, startup/recovery and one hit per target")
	quit(0)

func capture() -> void:
	var room := Node2D.new()
	root.add_child(room)
	RenderingServer.set_default_clear_color(Color("22262e"))
	var index := 0
	for variant in [1,2]:
		for direction in [-1.0,1.0]:
			var player = load("res://scenes/player/lan/lan_player.tscn").instantiate()
			player.world_min_x = -2000.0
			player.world_max_x = 2000.0
			player.position = Vector2(400 if direction < 0 else 900, 240 if variant == 1 else 520)
			room.add_child(player)
			player.set_physics_process(false)
			player.get_node("SkillBar").hide()
			player.get_node("PlayerStatusHUD").hide()
			player.animated_sprite.stop()
			player.animated_sprite.animation = "attack_2x_%d" % variant
			player.animated_sprite.frame = 2 if variant == 1 else 4
			player.animated_sprite.flip_h = direction > 0
			player.animated_sprite.offset = Vector2(direction * -14.0, -3.5)
			var config = LanAttackEffectCatalog.attack_2x_1() if variant == 1 else LanAttackEffectCatalog.attack_2x_2()
			var effect = load("res://scenes/player/lan/lan_attack_effect.tscn").instantiate()
			effect.setup(player, direction, config, true)
			player.add_child(effect)
			effect.set_physics_process(false)
			effect.set_timeline_frame(2)
			var label := Label.new()
			label.text = "attack_2x_%d / %s" % [variant, "LEFT" if direction < 0 else "RIGHT"]
			label.position = player.position + Vector2(-180,-150)
			room.add_child(label)
			index += 1
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_cmdline_user_args()[-1]
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK)
	print("Rendered edited attacks: ", path)
	quit(0)
