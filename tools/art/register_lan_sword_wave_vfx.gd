extends SceneTree
## Inventory the baked effects of Lan's sword wave (LanSwordWaveFX). User arg: the recipe
## list to update (tools/art/production_combat_vfx_recipes.jsonl). Existing keys are kept.
const WINDS := [
	[&"lan_gather", "lan/sword_wave/gather/lan_sword_wave_gather"],
	[&"lan_cut1", "lan/sword_wave/cut1/lan_sword_wave_cut1"],
	[&"lan_cut2", "lan/sword_wave/cut2/lan_sword_wave_cut2"],
	[&"lan_cut3", "lan/sword_wave/cut3/lan_sword_wave_cut3"],
]

func _initialize() -> void:
	var destination: String = OS.get_cmdline_user_args()[0]
	var text := FileAccess.get_file_as_string(destination)
	var specs: Array = []
	for wind: Array in WINDS: specs.append([LanSwordWaveFX.spec(wind[0]), wind[1]])
	for entry: Array in specs:
		var effect := PixelSlash.new().configure(entry[0])
		var identity := CombatVFXRecipe.describe(effect)
		effect.free()
		if text.contains(identity.key): continue
		identity.asset_path = entry[1]
		text += JSON.stringify(identity, "", true) + "\n"
		print("REGISTERED ", identity.asset_path, " ", identity.key)
	FileAccess.open(destination, FileAccess.WRITE).store_string(text)
	quit()
