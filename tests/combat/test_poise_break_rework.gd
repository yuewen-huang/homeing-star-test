extends "../support/harness.gd"
## Regression for removal of the former default break/pressure-stun contract.
func run() -> void:
	use_memory_progress()
	var world := Node2D.new()
	root.add_child(world)
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x=-1000
	player.world_max_x=1000
	world.add_child(player)
	player.set_physics_process(false)
	for boss in [FroggerBoss.new(), CrystalCrabBoss.new()]:
		boss.combat_target=player
		boss.manual_control=true
		boss.world_min_x=-1000
		boss.world_max_x=1000
		world.add_child(boss)
		boss.set_physics_process(false)
		for i in 20:
			boss.combat_stats.restore_health()
			boss.receive_attack_hit(AttackHitContext.new(&"pressure",10,9999),Vector2.ZERO)
			boss.combat_stats.apply_poise_damage(9999)
			boss.tick_combat(.1)
		check(not boss.poise_broken and boss.stagger_remaining==0, "Continuous pressure never activates default break stun")
		check(not boss.has_poise_bar() and not boss.can_offer_break_empower(), "No default bar or break E")
		check(player.find_throw_target()==null, "Player cannot redeem a removed break reward")
	world.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEFAULT BREAK REMOVAL")
