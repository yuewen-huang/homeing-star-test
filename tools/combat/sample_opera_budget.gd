extends "../../tests/support/harness.gd"
## Paired input policies for the same formal encounter. Pass -- mixed to alternate
## dodge and guard at the same cues; neither policy forces boss moves or refills.
const CITY := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const S := preload("res://scripts/bosses/opera_dancer/opera_single_moves.gd")
var held := {}

func press(action: String, down: bool) -> void:
	if held.get(action,false) == down: return
	held[action] = down
	if action in ["J","L"]:
		var event := InputEventKey.new()
		event.keycode = KEY_J if action == "J" else KEY_L
		event.physical_keycode = event.keycode
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	elif down: Input.action_press(action)
	else: Input.action_release(action)

func run() -> void:
	use_memory_progress()
	var args := OS.get_cmdline_user_args()
	var guard_every := 3 if args.has("one_in_three") else (2 if args.has("mixed") else 1)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	seed(2245)
	print("OPERA_PROFILE guard_every=",guard_every," seed=2245")
	var city: SunkenCavern = CITY.instantiate()
	root.add_child(city)
	current_scene = city
	await wait_frames(5)
	var stage = city.gate_stage
	var lan := city.player
	lan.reset_after_map_fall(city.to_local(stage.to_global(Vector2(1000,669))))
	city.snap_camera()
	for i in 4: await physics_frame
	var boss = stage.dancer
	var previous_cue := false
	var cues := 0
	for tick in 10800:
		await physics_frame
		if not is_instance_valid(stage.dancer) or lan.combat_stats.health <= 0 or not lan.pulse_duel: break
		var move: int = boss.singles.move
		var age: float = boss.age
		var dx: float = boss.position.x-lan.position.x
		var gap := absf(dx)
		var seeking_heal := guard_every>1 and lan.heal.charges==0 and lan.combat_stats.health<=65 and lan.pulse_duel.player_energy>=60
		var retreat := tick<260 or (tick>1110 and tick<1330) or seeking_heal
		var dir := signf(dx)
		if retreat and gap<720: dir = -dir
		elif gap<65 or retreat: dir = 0
		if move==S.Move.ULTIMATE and age<5.4:
			dir = 1.0 if lan.position.x<boss.arena_right-220 else -1.0
		press("ui_left",dir<0 and lan.position.x>boss.arena_left+45)
		press("ui_right",dir>0 and lan.position.x<boss.arena_right-45)
		var cue := lan.parry_cue.is_visible_in_tree() and lan.parry_cue.time_to_contact<0.20
		if move==S.Move.BIND and age>2.80 and age<2.91: cue=true
		if cue and not previous_cue: cues+=1
		previous_cue=cue
		var dodge := cues%guard_every!=0
		press("parry",cue and not dodge)
		press("L",cue and dodge)
		var jump := move==S.Move.MOON and age>4.29 and age<4.65 or move==S.Move.BIND and age>1.73 and age<2.12
		if move==S.Move.ULTIMATE and age>3.3 and age<5.3: jump=fmod(age-3.3,0.84)<0.3
		press("jump",jump)
		press("heal",lan.combat_stats.health<=60 and not lan.heal.healing and tick%18<4 and (lan.heal.charges>0 or guard_every>1))
		var can_throw := lan.get_ready_throw_target()!=null and guard_every==1
		press("interact",can_throw and tick%4<2)
		press("J",not seeking_heal and gap<155 and not cue and not can_throw and (move!=S.Move.ULTIMATE or age>5.5) and tick%24<4)
	for action in held.keys(): press(action,false)
	print("OPERA_CUES ",cues)
	if is_instance_valid(stage.dancer): assist.end_boss_attempt(stage)
	city.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("OPERA BUDGET SAMPLE")
