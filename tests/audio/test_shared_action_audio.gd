extends SceneTree
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
const PROFILE := preload("res://assets/sideview/audio/sfx/mix_profile.gd")
func level(voice: Node) -> float:
	return float(PROFILE.DATA.sounds[voice.stream.resource_path].active_weighted_db)+voice.volume_db
var failures := 0
var checks := 0
var room: Chapter1DeerBossRoom
var player: LanPlayer
var boss: DeerBoss
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",label_)
func tick(seconds: float) -> void:
	for i in ceili(seconds*120):
		boss._physics_process(1.0/120)
		boss.vfx._process(1.0/120)
func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.clear_body_reaction(boss.animated_sprite)
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()
	for effect in room.find_children("*","Node2D",true,false):
		if effect.get_script()==load("res://scripts/sideview/lan_attack_effect.gd"): effect.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label_+".png"))
func run() -> void:
	var old := root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	if room.story.comic!=null: room.story._close_intro()
	player = room.player; boss = room.deer
	player.set_physics_process(false); boss.set_physics_process(false); boss.vfx.set_process(false)
	await process_frame
	await process_frame
	var audio = player.action_audio
	for move in [&"attack_1x",&"attack_2x",&"attack_2x_1",&"attack_2x_2",&"attack_3x"]:
		player.reset_after_map_fall(Vector2(800,555))
		var serial: int = audio.serial
		player.call(StringName("start_"+String(move)),1.0)
		for i in 90:
			player.combat_timeline.advance(1.0/60)
			if audio.serial>serial: break
		check(absf(level(audio.swings[serial%3])-(-22 if move==&"attack_3x" else -25))<0.1,"Actual swing uses calibrated category level: "+String(move))
		check(audio.serial==serial+1,"Real production timeline starts one swing for "+String(move))
		check(audio.swings[serial%3].stream==audio.SOUNDS[move],"Move chooses its assigned WAV: "+String(move))
	var selected := {}
	for sound in audio.SOUNDS.values(): selected[sound.resource_path] = true
	check(selected.size()==8,"All eight requested attack WAVs are mapped")
	player.reset_after_map_fall(Vector2(800,555))
	player.start_instant_dash(1)
	check(audio.breath.stream==audio.DASH and audio.breath.playing,"Real instant dash plays dash breath")
	player.reset_after_map_fall(Vector2(800,555))
	player.start_back_dodge(-1)
	check(audio.breath.stream==audio.DODGE and audio.breath.playing,"Real dodge plays dodge breath")
	var source := Node2D.new(); source.position = Vector2(500,555); room.add_child(source)
	for i in 3:
		player.reset_after_map_fall(Vector2(800,555))
		player.start_normal_hit(CombatAttackData.new(&"voice_test",source,2,0,0,0))
		check(absf(level(audio.hurt)+25)<0.1,"Actual hurt voice matches combat foreground level")
		check(audio.hurt.stream==audio.HURT[i] and audio.hurt.playing,"Actual health damage rotates hurt take %d" % (i+1))
	var hurt_count: int = audio.hurt_index
	player.combat_stats.restore_health()
	check(audio.hurt_index==hurt_count,"Healing never emits a hurt voice")
	Engine.time_scale = 0.25; audio._process(0)
	check(is_equal_approx(audio.hurt.pitch_scale,0.25),"Action voice follows global combat slow motion")
	Engine.time_scale = 1
	player.reset_after_map_fall(Vector2(800,555))
	player.input_frozen = false
	# Actual stage transition, original fall/getup and new full-length roar.
	boss.phase = 1; boss.reset_phase(); boss.position = Vector2(1000,555)
	boss.receive_skill_hit(SkillHitContext.new(&"finish",300),player.global_position)
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.hit_stop_serial += 1; Engine.time_scale = 1
	feedback.clear_body_reaction(boss.animated_sprite)
	tick(boss.phase_transition.duration(DeerPhaseTransition.FALL)+boss.phase_transition.duration(DeerPhaseTransition.RISE)+0.05)
	check(boss.phase_transition.stage==&"roar" and boss.phase==2,"Production fall and getup reach phase roar")
	check(absf(level(boss.vfx.call_audio)+20)<0.1,"Actual boss roar retains controlled emphasis")
	check(boss.vfx.call_audio.stream==DeerPhaseTransition.ROAR_SOUND,"Phase roar uses roar_giant rather than distant deer call")
	check(is_equal_approx(DeerPhaseTransition.ROAR_SOUND.get_length(),boss.phase_transition.roar_duration),"Animation duration matches full WAV length")
	check(boss.phase_transition.light_progress()<0.01,"Chest transition starts from the old light")
	await capture("phase_roar_early")
	tick(2.2)
	check(boss.phase_transition.light_progress()>0.3 and boss.phase_transition.light_progress()<0.8,"Chest light blends during the recorded roar")
	await capture("phase_roar_middle")
	tick(4.5)
	check(boss.phase_transition.active and boss.animated_sprite.animation==&"roar_END","Roar recovery waits for the complete audio tail")
	await capture("phase_roar_tail")
	tick(0.5)
	check(not boss.phase_transition.active and not player.boss_controlled and boss.phase==2,"Full roar ends and releases player control")
	# Global UI includes current scene and dynamically created custom controls.
	var ui := root.get_node("UIAudio")
	var button := Button.new(); room.add_child(button)
	ui.last_play = -1000; var before: int = ui.serial; button.pressed.emit()
	check(absf(level(ui.voice)+30)<0.1,"Global UI stays below combat foreground")
	check(ui.serial==before+1 and ui.voice.stream==ui.SOUND,"Future buttons automatically use the global UI WAV")
	var custom := Control.new(); room.add_child(custom)
	var click := InputEventMouseButton.new(); click.pressed = true; click.button_index = MOUSE_BUTTON_LEFT
	ui.last_play = -1000; before = ui.serial; custom.gui_input.emit(click)
	check(ui.serial==before+1,"Custom UI slots share mouse feedback")
	var option := OptionButton.new(); room.add_child(option)
	ui.last_play = -1000; before = ui.serial; option.item_selected.emit(0)
	check(ui.serial==before+1,"Dropdown selections share UI feedback")
	var settings := root.get_node("AudioSettings") as AudioSettingsService
	ui.last_play = -1000; before = ui.serial; settings.open_settings()
	check(ui.serial>before,"Settings popup open shares UI feedback")
	ui.last_play = -1000; before = ui.serial; settings.settings_panel.hide(); paused = settings.was_paused
	check(ui.serial>before,"Settings popup close shares UI feedback")
	check(ui.voice.bus==&"SFX" and audio.hurt.bus==&"SFX" and audio.breath.bus==&"SFX","UI and all player audio follow the SFX volume bus")
	var ambient := root.get_node("SceneTransition/ForestAmbientAudio")
	ambient.remaining = 0; ambient._process(0.1)
	check(not ambient.voice.playing,"Forest ambience never overlaps the active production boss")
	boss._change_state(DeerBoss.State.COMPLETE)
	ambient.remaining = 0; ambient._process(0.1)
	check(ambient.voice.playing and ambient.voice.stream==ambient.CALL and level(ambient.voice)<=-35.9 and level(ambient.voice)>=-40.1,"Forest can play the distant call at a subdued level")
	check(ambient.remaining>=45 and ambient.remaining<=90,"Distant calls use a sparse randomized interval")
	room.free(); current_scene = null
	await process_frame
	print("SHARED ACTION AUDIO: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
