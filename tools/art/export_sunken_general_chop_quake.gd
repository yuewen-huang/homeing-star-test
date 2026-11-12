extends SceneTree
## Run against Combat VFX Studio with an output .tres path after --.

const SOURCE := "res://combos/sunken_general_chop_quake"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass the output .tres path after --")
		quit(1)
		return
	var combo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE.path_join("combo.json")))
	var style: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE.path_join("style.json")))
	var event: Dictionary = combo["_flow"]["nodes"][0]["data"]["events"][0]
	var recipe := JSON.new()
	recipe.data = event.merged({
		"quake_style": style.get("quake_style", "real"),
		"quake_detail": style.get("quake_detail", "ultimate"),
	})
	quit(ResourceSaver.save(recipe, args[0]))
