extends "../../support/harness.gd"
var room: Node2D
var master: MasterBoss
var player: LanPlayer
var output := ""

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var save := use_memory_progress()
	save.add_item(ItemCatalog.HANGOVER_PILL)
	save.equip_special_item(ItemCatalog.HANGOVER_PILL)
	# The fifth drink is now the spirit-blade exam; the spirit test only checks layers,
	# so keep Lan alive through it instead of asking her to parry six full-arena cuts.
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	master = room.get_node("MasterBoss") as MasterBoss
	player = room.get_node("Lan") as LanPlayer
	master.manual_control = true
	player.set_physics_process(false)
	master.position = Vector2(140, 555)
	player.position = Vector2(-10, 555)
	await process_frame
	var teaching := room.get_node("MasterCombatTeaching")
	master.spirit_aura.update_visual(0)
	check(not master.spirit_aura.visible, "Zero spirit has no blue aura")
	check(not master.use_sobering_item(), "Sobering item refuses phase one")
	for i in range(1, master.CHARGED_POWER_MAX + 1):
		var id: StringName = &"return_chain" if i % 2 else &"inertia_combo"
		master.start_clash_rhythm(id)
		# Finish the real rhythm without needing to let its hardest hit injure Lan.
		master.clash_rhythm.advance(master.clash_rhythm.played_time_at(master.clash_rhythm.duration) + 0.01)
		check(master.pending_drink, "%s completion queues its drink even without a landed hit" % id)
		check(master.recovery_remaining >= 0.0, "Authored recovery has a valid remaining opening")
		master._update_recovery(master.recovery_remaining + 0.01)
		check(master.state == MasterBoss.State.DRINK, "Recovery actually starts the drink")
		check(CombatLessonCatalog.text(&"spirit").contains("蓝色") and not CombatLessonCatalog.text(&"spirit").contains("变身"), "First-drink dialogue describes only the visible spirit")
		var ticks := 0
		# The fifth drink runs the full spirit-blade exam before the layer lands.
		while master.state == MasterBoss.State.DRINK and ticks < 1100:
			await physics_frame
			ticks += 1
		check(master.charged_power == i, "Finishing drink %d grants exactly one spirit layer" % i)
		master.spirit_aura.update_visual(0)
		if i < master.CHARGED_POWER_MAX:
			check(is_equal_approx(master.spirit_aura.strength, float(i)/float(master.CHARGED_POWER_MAX)), "Blue aura increases with layer %d" % i)
			check(master.spirit_aura.spirit_material.get_shader_parameter("aura_colour") == Color("248cff"), "Phase-one aura is blue")
			master.play_idle()
			await capture("spirit_blue_%d" % i)
	check(master.phase == 2 and master.state == MasterBoss.State.TRANSFORM, "Six completed drinks enter phase two")
	check(master.charged_power == master.CHARGED_POWER_MAX, "Phase two starts with the full six layers")
	check(is_zero_approx(master.phase_2_buff_remaining), "Layers alone never grant the phase-two buff")
	while master.state == MasterBoss.State.TRANSFORM: await physics_frame
	master._start_phase_2_howl()
	master.spirit_aura.update_visual(0)
	check(master.spirit_aura.spirit_material.get_shader_parameter("aura_colour") == Color("ff352f"), "Phase-two aura is red")
	check(is_equal_approx(master.spirit_aura.strength, 1.0), "Howl carries strong red spirit")
	teaching._process(0.0)
	check(teaching.key_hint.pending_labels == ["Q"], "Equipped item has an overhead Q hint during howl")
	await capture("spirit_red_howl")
	room._on_special_item_use_requested(ItemCatalog.VINE_SNARE)
	check(master.state == MasterBoss.State.PHASE_2_HOWL, "An unrelated item cannot clear the howl")
	save.equip_special_item(&"")
	check(CombatLessonCatalog.text(&"sobering").contains("装配"), "Sobering video explains the loadout")
	room._on_special_item_use_requested(ItemCatalog.HANGOVER_PILL)
	check(master.state == MasterBoss.State.PHASE_2_HOWL, "Unequipped item cannot be used")
	save.equip_special_item(ItemCatalog.HANGOVER_PILL)
	master.phase_2_buff_remaining = 3.0
	master.phase_2_finale_active = true
	room._on_special_item_use_requested(ItemCatalog.HANGOVER_PILL)
	check(master.phase_2_buff_remaining == 0 and not master.phase_2_finale_active and not master.howl_aura.active, "Real Q handler cancels howl, buff and gold finale")
	check(master.sobering_remaining == master.SOBERING_OPENING and master.state == MasterBoss.State.PHASE_2_IDLE, "Successful use grants a real recovery opening")
	check(not master.spirit_aura.visible and master.spirit_aura.strength == 0.0, "Red spirit visibly collapses after sobering")
	check(room._sobering_notice.is_toast_visible(), "Successful use has brief confirmation")
	check(room._sobering_notice._toast_label.text == "醒酒成功", "Success confirmation stays short")
	await capture("spirit_sobering_success")
	check(not master.use_sobering_item(), "An inactive spirit cannot be cleared repeatedly")
	check(save.get_item_count(ItemCatalog.HANGOVER_PILL) == 1, "Existing infinite-use item stays owned")
	check(master.phase_2_howl_cooldown_remaining > 0, "Cleared spirit does not immediately restart its howl")
	expect_save_untouched()
	finish("MASTER SPIRIT")
