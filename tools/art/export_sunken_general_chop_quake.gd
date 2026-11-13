extends SceneTree
## Run against Combat VFX Studio with an output .tres path after --.

const SOURCE := "res://combos/sunken_general_chop_quake"
const FIRE_SOURCE := "res://combos/sunken_general_fire_chops"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var fire := args.size() == 2 and args[0] == "--fire"
	if args.size() != 1 and not fire:
		push_error("Pass the output .tres path, or --fire followed by the output path")
		quit(1)
		return
	var source := FIRE_SOURCE if fire else SOURCE
	var combo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("combo.json")))
	var style: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("style.json")))
	var look := {
		"quake_style": style.get("quake_style", "real"),
		"quake_detail": style.get("quake_detail", "ultimate"),
	}
	var recipe := JSON.new()
	if fire:
		var events: Array = combo.events
		if events.size() != 3 or not events.all(func(event: Dictionary) -> bool:
			return (event.get("do") == "quake" and event.get("unit") == "sword"
				and event.get("form") == "guandao_wave" and event.get("trail") == "flame")):
			push_error("The fire chops must use three quake sword events with flame trails")
			quit(1)
			return
		recipe.data = events.map(func(event: Dictionary) -> Dictionary: return event.merged(look))
	else:
		var event: Dictionary = combo["_flow"]["nodes"][0]["data"]["events"][0]
		recipe.data = event.merged(look)
	quit(ResourceSaver.save(recipe, args[-1]))
