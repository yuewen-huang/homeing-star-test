extends "../support/harness.gd"

func run() -> void:
	var save := use_memory_progress()
	var world := Node2D.new()
	root.add_child(world)
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.name = "Lan"
	player.world_min_x = -1000
	player.world_max_x = 1000
	world.add_child(player)
	player.set_physics_process(false)
	var master := load("res://scenes/bosses/master/master_boss.tscn").instantiate() as MasterBoss
	master.aggro_target_path = NodePath("../Lan")
	master.world_min_x = -1000
	master.world_max_x = 1000
	var frog := FroggerBoss.new()
	frog.combat_target = player
	frog.manual_control = true
	frog.world_min_x = -1000
	frog.world_max_x = 1000
	for boss in [frog, master]:
		world.add_child(boss)
		boss.set_physics_process(false)
		var stats: CombatantStats = boss.combat_stats
		var depleted := [0]
		stats.poise_depleted.connect(func(): depleted[0] += 1)
		for i in 20: stats.apply_poise_damage(100000)
		boss._on_poise_depleted()
		check(stats.poise == stats.max_poise and depleted[0] == 0, "Default damage emits no depletion on " + str(boss.get_class()))
		check(not boss.is_poise_broken() and not boss.can_offer_break_empower(), "No default weakness or E reward")
		check(not boss.has_poise_bar() and boss.has_hit_armor(), "HUD removal preserves BOSS hit armor")
	var encounter = load("res://scripts/levels/back_alley/back_alley_encounter.gd").new()
	encounter.save = save
	encounter.player = player
	encounter.frog_boss = frog
	frog.tutorial_protected = true
	world.add_child(encounter)
	encounter._on_frog_sword_wave_received()
	check(save.has_completed(SaveProgressService.STORY_BACK_ALLEY_SPECIAL_TUTORIAL_COMPLETE) and not frog.tutorial_protected, "Actual unbroken sword-wave hit completes tutorial and releases death protection")
	var piece := VineTrialPiece.new()
	piece.kind = "vine"
	piece.vine_length = 380
	piece.position = Vector2(360,70)
	world.add_child(piece)
	var binding := RegionalBindingVine.new()
	binding.preview_only = true
	world.add_child(binding)
	binding.setup(player,piece,VineCombatEnemy.Role.REEL,Rect2(48,555,1184,0),100,40)
	for i in 4: binding.receive_hit(1,Vector2.ZERO)
	check(binding.poise_broken and binding.combat_stats.health == 100, "Actual authored binding target interrupts on four hits without taking health damage")
	binding.step(4.1)
	check(not binding.poise_broken and binding.combat_stats.poise == 40, "Binding resumes after its explicitly authored four-second release")
	world.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("NO DEFAULT POISE")
