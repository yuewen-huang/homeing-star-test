extends SceneTree

## Real E-key round trips with in-memory progress; never writes the user's save.
class TestProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

const CASES := [
	["wind","HeartGate","chapter_1_wind_boss_room",&"wind_puzzle_directed_bells",&"wind_combat_high_branches"],
	["vine","DeerGate","chapter_1_special_boss_upper_right_room",&"vine_puzzle_high_swing",&"vine_combat_branch_arena"],
	["mist","PortalToSpecialBoss","chapter_1_special_boss_lower_left_room",&"mist_puzzle_entry",&"mist_combat_01"],
	["root","HeartGate","chapter_1_root_heart_room",&"root_puzzle_water_veins",&"root_combat_sunken_roots"],
	["vine","HeartGate","chapter_1_deer_boss_room",&"",&""],
]
var save: TestProgress
var transition: SceneTransitionService
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok:
		failures += 1

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func press_e() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	key = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	Input.parse_input_event(key)

func travel(marker: Node2D) -> bool:
	if current_scene is Chapter1DeerBossRoom and current_scene.story.comic != null:
		current_scene.story.comic._request_finish(true)
		await frames(2)
	var player := current_scene.get_node("Lan") as LanPlayer
	player.set_physics_process(false)
	player.position = marker.global_position
	await frames(3)
	await press_e()
	if not transition.is_transitioning:
		check(false,"E starts transition from %s" % marker.name)
		return false
	var start := Time.get_ticks_msec()
	while transition.is_transitioning and Time.get_ticks_msec()-start<10000:
		await process_frame
	check(not transition.is_transitioning,"Transition finishes")
	return not transition.is_transitioning

func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--visual-dir")
	if index<0:
		return
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(args[index+1].path_join(name+".png"))

func run() -> void:
	var user_save := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	transition = root.get_node("SceneTransition") as SceneTransitionService
	var music := AudioStreamWAV.new()
	music.format = AudioStreamWAV.FORMAT_16_BITS
	music.mix_rate = 8000
	var silence := PackedByteArray()
	silence.resize(8000*60*2)
	music.data = silence
	transition.music_player.stream = music
	transition.music_player.play(0.7)
	Engine.time_scale = 8
	for data in CASES:
		if current_scene:
			var old_room := current_scene
			current_scene = null
			root.remove_child(old_room)
			old_room.free()
		save.load_progress()
		transition.set_scene_entry_position(Vector2(-1,-1))
		var region_path := "res://scenes/levels/chapter_1/chapter_1_%s_room.tscn" % data[0]
		var origin := load(region_path).instantiate() as Node2D
		root.add_child(origin)
		current_scene = origin
		var marker_path := NodePath(data[1] if data[0]=="mist" else "Portals/"+data[1])
		check(not origin.has_node("Mechanisms/HeartSeal"),"%s has no core blocking seal" % data[0])
		var marker := origin.get_node(marker_path) as Node2D
		if data[0] == "mist": marker = origin._portals[2].anchor
		if not await travel(marker):
			continue
		var boss := current_scene as Chapter1BossRoom
		check(boss!=null and current_scene.scene_file_path.ends_with(data[2]+".tscn"),"%s opens correct boss room with zero puzzle progress" % data[0])
		if boss==null:
			continue
		boss.player.set_physics_process(false)
		check(absf(boss.player.position.y-Chapter1BossRoom.FLOOR_Y)<3,"Boss arrival is on safe floor")
		check(boss.core_invulnerable==(data[3]!=&""),"Core immunity reflects incomplete corresponding puzzle; deer BOSS has no regional gate")
		check(transition.current_music_path==Chapter1Music.boss_music_for_scene(boss.scene_file_path).resource_path and transition.music_player.playing,"Boss entry selects designated boss BGM")
		await capture(data[2])
		if data[3]!=&"":
			check(boss.gold_shield_active and boss.blue_shield_active,"Both independent layers protect an uncleared region")
			save.set_stele_state(data[4],2)
			check(boss.core_invulnerable,"Completing combat alone does not remove core immunity")
			check(not boss.gold_shield_active and boss.blue_shield_active,"Combat completion removes only deep gold")
			save.set_stele_state(&"unrelated_puzzle",2)
			check(boss.core_invulnerable,"Unrelated puzzle does not remove core immunity")
			save._config.set_value("steles",String(data[4]),0)
			save.set_stele_state(data[3],2)
			check(boss.core_invulnerable and boss.gold_shield_active and not boss.blue_shield_active,"Puzzle completion removes only light blue; uncleared combat still protects core")
			save.set_stele_state(data[4],2)
			check(not boss.core_invulnerable and not boss.gold_shield_active and not boss.blue_shield_active,"Completing both regional challenges removes protection immediately")
		if boss is Chapter1DeerBossRoom:
			if boss.story.comic != null:
				boss.story.comic._request_finish(true)
				await frames(2)
			check(not boss.get_node("ReturnGate").visible and not boss._return_prompt.available,"Deer battle closes the return portal")
			# Resume a completed encounter for this travel fixture; actual combat
			# defeat/phase gating is covered by test_deer_battle_portal.
			save.try_complete_fact(SaveProgressService.STORY_C1_DEER_DEFEATED)
			save.try_complete_fact(DeerStory.REWARD_PRESENTED_ID)
			boss.story._restore_victory()
		if not await travel(boss.get_node("ReturnGate")):
			continue
		check(current_scene.scene_file_path==region_path,"Boss return reaches original region")
		var returned := current_scene.get_node("Lan") as LanPlayer
		returned.set_physics_process(false)
		var return_marker: Node2D = current_scene._portals[2].anchor if data[0] == "mist" else current_scene.get_node(marker_path)
		check(returned.global_position.distance_to(return_marker.global_position)<6,"Return lands at matching current portal anchor")
		check(transition.current_music_path==Chapter1Music.FOREST.resource_path and transition.music_player.playing,"Boss return restores forest BGM")
	Engine.time_scale = 1
	check(user_save==FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH),"User save remains untouched")
	print("BOSS ROOM CHECKS: ",failures," failures")
	quit(1 if failures else 0)
