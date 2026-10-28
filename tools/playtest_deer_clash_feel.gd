extends SceneTree
## Controlled real-room playtest: actual input, movement, parry feedback and recoil.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var player: LanPlayer
var active := false
var clock := 0.0
var began := 0.0
var slot := -1
var pressed := false
var release := false
var output := ""
var records: Array[Dictionary] = []
var runs: Array[Dictionary] = []
var delay := 0.0
var saw_clash := false
var hard := false
var plans := [&"deer_phase3_forest_five", &"deer_phase3_return_four", &"deer_phase3_mountain_six"]

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	hard = "--hard" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("setup")

func setup() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD if hard else BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	if room.story.comic != null: room.story._close_intro()
	boss = room.deer
	player = room.player
	boss.manual_control = true
	for phase in [1, 2]:
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		while boss.phase_transition.active or boss.phase != phase + 1:
			player.combat_stats.restore_health()
			await physics_frame
	while boss.state not in [DeerBoss.State.IDLE, DeerBoss.State.WALK]: await physics_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(on_parry)
	active = true
	next_run()

func next_run() -> void:
	slot += 1
	if slot >= plans.size():
		finish()
		return
	boss.manual_control = true
	boss._recover(0)
	boss.poise_broken = false
	boss.combat_stats.restore_poise()
	boss.combat_stats.restore_health()
	boss.clash_phase.parry_streak = 0
	boss.position.x = 1500
	player.reset_after_map_fall(Vector2(1330, boss.position.y))
	player.facing_direction = 1
	player.apply_facing_direction()
	player.combat_stats.restore_health()
	player.combat_stats.restore_stamina(player.combat_stats.max_stamina)
	began = clock
	pressed = false
	saw_clash = false
	delay = 0
	boss.manual_control = false
	boss.start_clash(plans[slot], player.position.x)
	runs.append({"combo": plans[slot], "start": began, "hp": player.combat_stats.health, "source_events": [5, 4, 6][slot]})
	print("START ", plans[slot])

func _physics_process(delta: float) -> bool:
	if not active: return false
	clock += delta
	if release:
		Input.action_release(&"parry")
		release = false
	if boss.state == DeerBoss.State.CLASH:
		saw_clash = true
		if not pressed:
			var next := boss.clash_phase.next_parry_contact_in()
			if next >= 0 and next <= 0.14:
				Input.action_press(&"parry")
				pressed = true
				release = true
				records.append({"combo": plans[slot], "event": "K", "t": clock - began, "lead": next})
	else:
		boss.manual_control = true
		if saw_clash: delay += delta
		if delay >= 1.0 or clock - began > 18:
			runs.back().end = clock - began
			runs.back().damage = int(runs.back().hp) - player.combat_stats.health
			runs.back().parries = records.filter(func(r: Dictionary) -> bool: return r.combo == plans[slot] and r.event == "parry").size()
			print("RESULT ", JSON.stringify(runs.back()))
			next_run()
	return false

func on_parry(source: DamageReceiver2D, attack: CombatAttackData, contact: Vector2, red: bool) -> void:
	if source != boss or not active: return
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var event := {"combo": plans[slot], "event": "parry", "t": clock - began, "attack": attack.attack_id,
		"gap": absf(boss.position.x - player.position.x), "chain": feedback.parry_chain, "visual_chain": player.clash_visual.chain,
		"hit_stop": CombatFeedbackService.parry_hit_stop(feedback.parry_chain), "red": red,
		"contact": [contact.x, contact.y]}
	records.append(event)
	if hard: pressed = false
	if RenderingServer.get_rendering_device() != null or DisplayServer.get_name() != "headless":
		var path := output.path_join("%d_%02d.png" % [slot, records.size()])
		RenderingServer.frame_post_draw.connect(func() -> void: root.get_texture().get_image().save_png(path), CONNECT_ONE_SHOT)

func finish() -> void:
	active = false
	Input.action_release(&"parry")
	var expected := [5, 3 if hard else 4, 6]
	var passed := runs.size() == expected.size()
	for i in runs.size(): passed = passed and int(runs[i].damage) == 0 and int(runs[i].parries) == expected[i]
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify({"runs": runs, "events": records}, "\t"))
	current_scene = null
	room.free()
	await process_frame
	print("PLAYTEST PASS" if passed else "PLAYTEST FAILED")
	quit(0 if passed else 1)
