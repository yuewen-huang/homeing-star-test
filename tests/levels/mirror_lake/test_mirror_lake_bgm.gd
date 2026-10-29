extends SceneTree
## 镜湖 BGM：进关播放 moonlight_on_the_ink（Music 总线、循环）/ 熊猫开战淡出 / 淡出后熊猫 BGM steel_at_the_jade_gate 循环。
## 用法：homeing-star-test/run-tests.ps1 -Test test_mirror_lake_bgm
class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + label)
func run() -> void:
	var old := root.get_node_or_null("SaveProgress")
	if old != null: old.name = "SaveProgressOld"
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var t := root.get_node("SceneTransition") as SceneTransitionService
	check(MirrorLakeMusic.EXPLORE.resource_path == "res://assets/levels/mirror_lake/audio/moonlight_on_the_ink.mp3", "explore BGM path")
	check(MirrorLakeMusic.PANDA_FIGHT.resource_path == "res://assets/levels/mirror_lake/audio/steel_at_the_jade_gate.mp3", "panda fight BGM path")
	var scene := load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	await process_frame
	var mp := t.music_player
	check(mp.playing and t.current_music_path == MirrorLakeMusic.EXPLORE.resource_path, "explore BGM plays on entering")
	check(mp.bus == &"Music" and is_equal_approx(mp.volume_db, SceneTransitionService.MUSIC_MIX_VOLUME_DB), "Music bus, mix volume")
	check(mp.stream is AudioStreamMP3 and (mp.stream as AudioStreamMP3).loop, "explore BGM loops")
	var player := scene.player as LanPlayer
	player.position = Vector2(PandaGoArena.TRIGGER_X + 50, MirrorLake.STAND_Y)
	scene.panda_arena.tick(0.016)
	check(scene.panda_arena.active, "encounter started")
	await create_timer(MirrorLakeMusic.FIGHT_FADE_OUT * 0.5).timeout
	check(mp.playing and mp.volume_db < SceneTransitionService.MUSIC_MIX_VOLUME_DB - 1.0, "fading out mid-way")
	await create_timer(MirrorLakeMusic.FIGHT_FADE_OUT * 0.5 + 0.4).timeout
	check(mp.playing and t.current_music_path == MirrorLakeMusic.PANDA_FIGHT.resource_path, "panda fight BGM plays after fade")
	check(mp.bus == &"Music" and is_equal_approx(mp.volume_db, SceneTransitionService.MUSIC_MIX_VOLUME_DB), "fight BGM: Music bus, mix volume")
	check(mp.stream is AudioStreamMP3 and (mp.stream as AudioStreamMP3).loop, "fight BGM loops")
	print("RESULT %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(failures)