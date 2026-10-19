extends SceneTree
const MIX := preload("res://scripts/audio/sfx_mix.gd")
var failures := 0
var checks := 0
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",label_)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sideview/audio/sfx/mix_profile.json"))
	var groups := {"/swing/":&"swing","/lan_voice/":&"hurt_voice","/crystal_crab/":&"ground_impact","ui_pop.wav":&"ui","roar_giant.wav":&"boss_roar"}
	for uri in profile.sounds:
		var row: Dictionary = profile.sounds[uri]
		for fragment in groups:
			if not fragment in uri: continue
			var sound := load(uri) as AudioStream
			var gain: float = MIX.gain(sound,groups[fragment])
			check(float(row.peak_dbfs)+gain<=-2.999,"Calibrated peak stays below ceiling: "+uri.get_file())
			check(absf(float(row.active_weighted_db)+gain-(-22+float(MIX.ROLES[groups[fragment]])))<0.1,"Source loudness aligned within category: "+uri.get_file())
	var light := load("res://assets/sideview/audio/sfx/derived/swing/swing_light_01.wav") as AudioStream
	check(is_equal_approx(MIX.gain(light,&"heavy_swing")-MIX.gain(light,&"swing"),3),"Heavy attacks retain a 3 dB emphasis")
	check(MIX.ROLES[&"ui"]<MIX.ROLES[&"hurt_voice"] and MIX.ROLES[&"walk"]<MIX.ROLES[&"swing"] and MIX.ROLES[&"ambient"]<MIX.ROLES[&"walk"],"Background and interface stay below combat feedback")
	var crab := CrystalCrabQuakeVFX.new()
	root.add_child(crab)
	for anchor in [&"left",&"right",&"double",&"burrow"]:
		var index: int = crab.voice_index
		crab.impact({"anchor":anchor,"center":Vector2.ZERO},&"test",0)
		var voice := crab.impact_voices[index]
		var body: float = profile.sounds[voice.stream.resource_path].active_weighted_db
		check(absf(body+voice.volume_db+21)<0.1,"Actual crab impact uses balanced gain: "+String(anchor))
	crab.free()
	print("SFX MIX: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
