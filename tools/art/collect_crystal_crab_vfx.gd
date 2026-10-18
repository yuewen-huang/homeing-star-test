extends SceneTree
## Collect only the actual ground attack recipes used by CrystalCrabQuakeRhythm.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var existing := FileAccess.get_file_as_string(path)
	var keys := {}
	for line in existing.split("\n", false):
		var record: Dictionary = JSON.parse_string(line)
		keys[record.key] = true
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(existing.trim_suffix("\n")+"\n")
	for id in CrystalCrabQuakeRhythm.ORDER:
		var score := CrystalCrabQuakeRhythm.new(id)
		for beat in score.beats:
			var effect := PixelSlash.new().configure(score.effect_spec(beat.radius, beat.danger))
			var record := CombatVFXRecipe.describe(effect)
			effect.free()
			if keys.has(record.key): continue
			keys[record.key] = true
			record.asset_path = "crystal_crab_boss/ground_quake/quake_%s_%d" % [["salt", "red", "gold"][int(beat.danger)], int(beat.radius)*2]
			file.store_line(JSON.stringify(record, "", true))
	for danger in [1,2]:
		for spec in CrystalCrabQuakeVFX.danger_specs(danger):
			var effect := PixelSlash.new().configure(spec)
			var record := CombatVFXRecipe.describe(effect)
			effect.free()
			if keys.has(record.key): continue
			keys[record.key] = true
			record.asset_path = "combat_shared/danger_cue/%s/combat_danger_%s_%s" % [["", "red", "gold"][danger],["", "red", "gold"][danger], spec.shape]
			file.store_line(JSON.stringify(record, "", true))
	# This boss's consecutive AOE parries reach the two existing shared growth stages
	# absent from the old atlas. Inventory the actual shared effect, not a replica.
	for entry in [[CombatImpactEffect.Kind.PARRY,4],[CombatImpactEffect.Kind.PARRY,5],
		[CombatImpactEffect.Kind.RED_PARRY,0],[CombatImpactEffect.Kind.RED_PARRY,1],
		[CombatImpactEffect.Kind.RED_PARRY,2],[CombatImpactEffect.Kind.RED_PARRY,3],
		[CombatImpactEffect.Kind.RED_PARRY,4],[CombatImpactEffect.Kind.RED_PARRY,5]]:
		var kind: CombatImpactEffect.Kind = entry[0]
		var chain: int = entry[1]
		var impact := CombatImpactEffect.new()
		impact.setup(kind, 1, Vector2.ZERO, chain)
		root.add_child(impact)
		for effect in impact.pieces:
			var record := CombatVFXRecipe.describe(effect)
			if keys.has(record.key): continue
			keys[record.key] = true
			var prefix := "red_parry" if kind==CombatImpactEffect.Kind.RED_PARRY else "parry"
			record.asset_path = "combat_shared/impact/%s_chain_%02d/combat_%s_chain_%02d_%s" % [prefix,chain+1,prefix,chain+1,effect.shape]
			file.store_line(JSON.stringify(record, "", true))
		impact.free()
	file.close()
	print("Collected production crab ground VFX recipes")
	quit()
