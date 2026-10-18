extends SceneTree
## Inventory only the two effects used by the real master's press-return action.
func _initialize() -> void:
	var destination := "D:/HomingStar/homeing-star-test/tools/art/production_combat_vfx_recipes.jsonl"
	var text := FileAccess.get_file_as_string(destination)
	for profile: StringName in [&"down_cut", &"return_lift"]:
		var effect := PixelSlash.new().configure(MasterWindVFX.spec(profile))
		var identity := CombatVFXRecipe.describe(effect)
		effect.free()
		if text.contains(identity.key): continue
		identity.asset_path = "master_boss/press_return/%s/master_wind_%s" % [profile,profile]
		text += JSON.stringify(identity, "", true) + "\n"
		print("REGISTERED ", identity.asset_path, " ", identity.key)
	FileAccess.open(destination, FileAccess.WRITE).store_string(text)
	quit()
