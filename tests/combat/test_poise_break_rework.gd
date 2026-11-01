extends SceneTree
## Poise/break rework: E empower once per break phase; broken boss keeps acting unless pressed.
## Fixed break window: continuous poise regen + poise-damage immunity so the window always ends.

class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("OK " if ok else "FAIL ", label)

func run() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var progress := LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)

	var world := Node2D.new()
	root.add_child(world)
	var player := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate() as LanPlayer
	player.world_min_x = -1000.0
	player.world_max_x = 1000.0
	player.position = Vector2(520, 500)
	player.facing_direction = -1.0
	world.add_child(player)
	player.set_physics_process(false)

	var frog := FroggerBoss.new()
	frog.combat_target = player
	frog.manual_control = true
	frog.tutorial_protected = true
	frog.world_min_x = -1000.0
	frog.world_max_x = 1000.0
	# Face the player's facing direction (left) so find_throw_target can see the boss.
	frog.position = Vector2(400, 500)
	world.add_child(frog)
	frog.set_physics_process(false)
	await process_frame

	check(is_equal_approx(CombatTuning.BOSS_BREAK_WINDOW_DURATION, 5.0), "BOSS_BREAK_WINDOW_DURATION locked to 5s")
	check(is_equal_approx(CombatTuning.BOSS_STAGGER_DURATION, CombatTuning.BOSS_BREAK_WINDOW_DURATION), "BOSS_STAGGER_DURATION aliases break window")

	# Force a break window.
	frog.combat_stats.apply_poise_damage(frog.combat_stats.poise)
	check(frog.poise_broken and frog.break_empower_available, "poise deplete opens break window with E empower available")
	check(frog.can_offer_break_empower(), "can_offer_break_empower true at break open")
	check(frog.short_stun_remaining > 0.0, "break open applies a short hitch, not a long lock")
	check(frog.is_poise_damage_immune(), "broken boss is immune to poise damage")
	check(is_equal_approx(frog.stagger_remaining, CombatTuning.FROGGER_DEFEAT_STAGGER_DURATION), "frogger teaching break keeps its own duration")

	# After open hitch drains, boss can start an attack while still broken.
	frog.short_stun_remaining = 0.0
	frog.start_action(&"tongue")
	check(frog.poise_broken and frog.action == &"tongue", "broken boss can still choose/execute an attack")
	check(frog.can_offer_break_empower(), "E empower remains available while boss attacks in break window")

	# Player hit interrupts into short stun; window stays; poise damage is ignored.
	var before_window := frog.stagger_remaining
	var poise_before_spam := frog.combat_stats.poise
	frog.receive_attack_hit(LanAttackEffectCatalog.attack_1x().attack_hit_context, player.global_position)
	check(frog.poise_broken and frog.short_stun_remaining >= CombatTuning.BOSS_BREAK_HIT_STAGGER - 0.001, "hit during break applies short stagger")
	check(frog.attack_hitbox.attack == null, "hit during break interrupts current attack")
	check(is_equal_approx(frog.stagger_remaining, before_window) or frog.stagger_remaining <= before_window, "break window continues after pressure hit")
	check(frog.combat_stats.poise >= poise_before_spam, "normals deal no poise damage during break (immune)")

	# Spam hits: still immune; window countdown is what ends the break.
	for _i in 12:
		frog.receive_attack_hit(LanAttackEffectCatalog.attack_3x(25.0).attack_hit_context, player.global_position)
		var skill := SkillHitContext.new(&"lan_special", CombatTuning.LAN_SPECIAL_CHARGED_DAMAGE)
		skill.poise_damage = CombatTuning.LAN_SPECIAL_CHARGED_POISE_DAMAGE
		frog.receive_skill_hit(skill, player.global_position)
	check(frog.poise_broken, "continuous attacks during break do not cancel the window early")
	check(frog.combat_stats.poise >= 0, "poise stays non-negative under spam")

	# Tick the break window under continuous pressure: always ends, poise regenerates.
	frog.short_stun_remaining = 0.0
	var ticks := 0
	while frog.poise_broken and ticks < 400:
		frog.combat_stats.restore_health()
		frog.receive_attack_hit(LanAttackEffectCatalog.attack_1x().attack_hit_context, player.global_position)
		frog.tick_combat(1.0 / 60.0)
		ticks += 1
	check(not frog.poise_broken, "break window ends after countdown even under continuous attacks")
	check(frog.combat_stats.poise == frog.combat_stats.max_poise, "break end restores full poise (regen completed under immunity)")
	check(ticks * (1.0 / 60.0) >= CombatTuning.FROGGER_DEFEAT_STAGGER_DURATION - 0.05, "window lasted about the locked duration")

	# Standard BossBase path (crystal crab): fixed 5s window.
	var crab := CrystalCrabBoss.new()
	crab.combat_target = player
	crab.manual_control = true
	crab.world_min_x = -1000.0
	crab.world_max_x = 1000.0
	crab.position = Vector2(300, 500)
	world.add_child(crab)
	crab.set_physics_process(false)
	await process_frame
	crab.combat_stats.apply_poise_damage(crab.combat_stats.max_poise)
	check(crab.poise_broken and is_equal_approx(crab.stagger_remaining, CombatTuning.BOSS_BREAK_WINDOW_DURATION), "standard boss opens fixed 5s break window")
	var crab_poise_mid := crab.combat_stats.poise
	crab.receive_attack_hit(LanAttackEffectCatalog.attack_3x(25.0).attack_hit_context, player.global_position)
	check(crab.combat_stats.poise >= crab_poise_mid, "standard boss ignores poise damage during break")
	# Advance ~half the window and expect partial regen.
	for _j in 150:
		crab.tick_combat(1.0 / 60.0)
	check(crab.poise_broken and crab.combat_stats.poise > 0, "poise regenerates continuously during break window")
	check(crab.combat_stats.poise < crab.combat_stats.max_poise or crab.stagger_remaining < 0.1, "mid-window poise is rising toward full")
	while crab.poise_broken:
		crab.combat_stats.restore_health()
		crab.receive_attack_hit(LanAttackEffectCatalog.attack_1x().attack_hit_context, player.global_position)
		crab.tick_combat(1.0 / 60.0)
	check(crab.combat_stats.poise == crab.combat_stats.max_poise, "standard boss leaves break with full poise despite spam")

	# E empower once per phase: Lan gates on can_offer, and consume closes the offer.
	frog.combat_stats.apply_poise_damage(frog.combat_stats.poise)
	check(frog.break_empower_available and frog.can_offer_break_empower(), "new break after recovery restores E empower once")
	var target := player.find_throw_target()
	check(target == frog, "find_throw_target sees broken frog with empower available")
	# Mimic perform_special_attack's consume path without driving the full max-form animation.
	check(frog.has_method(&"consume_break_empower"), "boss exposes consume_break_empower")
	frog.consume_break_empower()
	check(not frog.break_empower_available, "consume marks empower used")
	check(not frog.can_offer_break_empower(), "second E empower blocked in same break phase")
	check(player.find_throw_target() == null, "find_throw_target empty after empower consumed")

	# New break phase restores empower.
	frog.finish_stagger()
	check(not frog.poise_broken and not frog.break_empower_available, "finish_stagger closes window and clears empower")
	check(frog.combat_stats.poise == frog.combat_stats.max_poise, "finish_stagger restores full poise")
	frog.combat_stats.apply_poise_damage(frog.combat_stats.poise)
	check(frog.break_empower_available and frog.can_offer_break_empower(), "new break phase restores E empower once")

	crab.queue_free()
	frog.queue_free()
	player.queue_free()
	world.queue_free()
	progress.free()
	root.add_child(original)
	await process_frame
	print("POISE BREAK REWORK CHECKS: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
