extends SceneTree
## Run with the Studio project as --path and the game FX directory after --.

const SOURCE := "res://combos/sunken_general_phase_two/combo.json"
const RENDERER := "res://vfx/sunken_general_fire/"
const Fire := preload("res://vfx/sunken_general_fire/attack_fire.gd")
const RUNTIME_KEYS := ["form", "duration", "heat", "haze", "size", "deep", "ember", "mid", "flame", "edge",
	"tongues", "continuous_wake", "ground_fire_delay", "ground_fire_duration", "ground_fire_width"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not DirAccess.dir_exists_absolute(args[0]):
		push_error("Pass the destination studio_fire directory after --")
		quit(1)
		return
	var events := ComboStage.load_timeline(SOURCE)
	var profiles := {}
	for event: Dictionary in events:
		if event.get("stroke") != "general_fire":
			continue
		var spec := Fire.normalized(event)
		var form := String(spec.form)
		if not Fire.FORMS.has(form):
			push_error("Unknown fire form: " + form)
			quit(1)
			return
		var data := {}
		for key in RUNTIME_KEYS:
			if spec.has(key):
				data[key] = spec[key]
		if not profiles.has(form):
			profiles[form] = []
		profiles[form].append(data)
	for form: String in Fire.FORMS:
		var count := 3 if form == "chop" else 1
		if profiles.get(form, []).size() != count:
			push_error("Expected %d Studio event(s) for %s" % [count, form])
			quit(1)
			return
	for filename in ["attack_fire.gd", "fire_material.gd", "fire_material.gdshader", "sweep_fire.gdshader", "reverse_fire.gdshader",
			"combustion.gdshaderinc", "heat_tail.gd", "haze.gdshader", "ground_fire.gd", "ground_fire.gdshader"]:
		var result := DirAccess.copy_absolute(ProjectSettings.globalize_path(RENDERER + filename), args[0].path_join(filename))
		if result != OK:
			push_error("Cannot export " + filename)
			quit(result)
			return
	var output := FileAccess.open(args[0].path_join("profiles.json"), FileAccess.WRITE)
	if output == null:
		quit(FileAccess.get_open_error())
		return
	output.store_string(JSON.stringify(profiles, "\t") + "\n")
	output.close()
	quit()
