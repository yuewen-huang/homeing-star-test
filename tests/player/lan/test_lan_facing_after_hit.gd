extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room:=load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene=room
	var player: LanPlayer=room.get_node("Lan")
	var master: MasterBoss=room.get_node("MasterBoss")
	master.manual_control=true
	master.set_process(false)
	player.set_physics_process(false)
	Input.action_release(&"special_attack")
	for direction in [-1.0,1.0]:
		player.reset_after_map_fall(Vector2(500,555))
		master.global_position=player.global_position
		player.facing_direction=direction
		player.apply_facing_direction()
		var hit:=CombatAttackData.new(&"same_x_hit",master,1,0,180,0)
		player.start_normal_hit(hit)
		check(player.facing_direction==direction,"Same-X hit preserves the player's previous facing")
		player.finish_hit_reaction()
		player.special_attack_cooldown_remaining=0
		player.start_special_attack(0)
		player.update_special_attack_charge(.05)
		check(is_instance_valid(player.timeline_attack_effect) and player.timeline_attack_effect.facing_direction==direction,"Releasing charged special after the hit creates a nonzero-facing effect")
		player.reset_after_map_fall(Vector2(500,555))
		player.facing_direction=0
		player.animated_sprite.flip_h=direction>0
		player.special_attack_cooldown_remaining=0
		player.perform_special_attack(0,.5)
		check(player.facing_direction==direction and player.timeline_attack_effect.facing_direction==direction,"Attack entry repairs an old zero-facing state from the retained visual side")
	expect_save_untouched()
	finish("LAN FACING AFTER HIT")
