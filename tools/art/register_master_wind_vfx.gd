extends SceneTree
## Inventory the master's baked wind ribbons used by real combat (press-return draft and the
## phase-one 拼刀 rhythms). User arg: the recipe list to update
## (tools/art/production_combat_vfx_recipes.jsonl). Existing keys are left untouched.
## [profile, palette, asset path]
const RECIPES := [
	[&"down_cut", &"master_wind", "master_boss/press_return/down_cut/master_wind_down_cut"],
	[&"return_lift", &"master_wind", "master_boss/press_return/return_lift/master_wind_return_lift"],
	[&"flip_chop", &"master_wind", "master_boss/clash_rhythm/flip_chop/master_wind_flip_chop"],
	[&"flip_chop", &"master_red", "master_boss/clash_rhythm/flip_chop/master_red_flip_chop"],
	[&"front_cut", &"master_wind", "master_boss/clash_rhythm/front_cut/master_wind_front_cut"],
	[&"flat_spin", &"master_wind", "master_boss/clash_rhythm/flat_spin/master_wind_flat_spin"],
	[&"blink_spin", &"master_wind", "master_boss/clash_rhythm/blink_spin/master_wind_blink_spin"],
	[&"heavy_chop", &"master_wind", "master_boss/clash_rhythm/heavy_chop/master_wind_heavy_chop"],
	[&"sword_qi", &"master_wind", "master_boss/clash_rhythm/sword_qi/master_wind_sword_qi"],
	[&"push_gust", &"master_wind", "master_boss/clash_rhythm/push_gust/master_wind_push_gust"],
	[&"plunge_crash", &"master_gold", "master_boss/clash_rhythm/plunge_crash/master_gold_plunge_crash"],
]

func _initialize() -> void:
	var destination: String = OS.get_cmdline_user_args()[0]
	var text := FileAccess.get_file_as_string(destination)
	for recipe: Array in RECIPES:
		var effect := PixelSlash.new().configure(MasterWindVFX.spec(recipe[0], recipe[1]))
		var identity := CombatVFXRecipe.describe(effect)
		effect.free()
		if text.contains(identity.key): continue
		identity.asset_path = recipe[2]
		text += JSON.stringify(identity, "", true) + "\n"
		print("REGISTERED ", identity.asset_path, " ", identity.key)
	FileAccess.open(destination, FileAccess.WRITE).store_string(text)
	quit()
