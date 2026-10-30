extends "../support/harness.gd"
## SavePathMigration (restructure P3, 2026-10-19): saves written before scenes moved name
## old scene paths as checkpoint keys, `last_scene` and record values. Loading must map
## them to the new paths, keep everything else, let newer entries win, and point every
## mapped path at a real scene. Works on an in-memory ConfigFile; the real save is untouched.

const OLD_MIST := "res://scenes/sideview/chapter_1_mist_room.tscn"
const NEW_MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
const OLD_FINAL := "res://scenes/sideview/chapter_1_final_boss_room.tscn"
const NEW_FINAL := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"
const OLD_WIND := "res://scenes/sideview/chapter_1_wind_room.tscn"
const NEW_WIND := "res://scenes/levels/chapter_1/chapter_1_wind_room.tscn"

func run() -> void:
	use_memory_progress()
	var config := ConfigFile.new()
	config.set_value("checkpoints", OLD_MIST, {"stele_id": "mist_puzzle_entry", "position": Vector2(10, 20)})
	config.set_value("checkpoints", "last_scene", OLD_FINAL)
	config.set_value("records", "mist_puzzle_entry", {"scene_path": OLD_MIST, "title": "雾碑", "history": [OLD_WIND, "kept"]})
	config.set_value("facts", "chapter_1_started", true)
	# Both the old and the new key: the newer (new-path) entry wins.
	config.set_value("checkpoints", OLD_WIND, {"stele_id": "old"})
	config.set_value("checkpoints", NEW_WIND, {"stele_id": "new"})

	var count := SavePathMigration.migrate(config)
	check(not config.has_section_key("checkpoints", OLD_MIST) and config.has_section_key("checkpoints", NEW_MIST), "A checkpoint keyed by an old scene path moves to the new key")
	check(config.get_value("checkpoints", NEW_MIST, {}).get("position") == Vector2(10, 20), "The checkpoint's data comes along unchanged")
	check(config.get_value("checkpoints", "last_scene") == NEW_FINAL, "last_scene follows the renamed deer BOSS room")
	var record: Dictionary = config.get_value("records", "mist_puzzle_entry")
	check(record.scene_path == NEW_MIST and record.title == "雾碑", "Paths inside record dictionaries are rewritten, other fields kept")
	check(record.history == [NEW_WIND, "kept"], "Paths inside arrays are rewritten")
	check(config.get_value("facts", "chapter_1_started") == true, "Unrelated progress is untouched")
	check(config.get_value("checkpoints", NEW_WIND).stele_id == "new" and not config.has_section_key("checkpoints", OLD_WIND), "When both keys exist the newer entry wins and the old key goes")
	check(count == 5, "Every rewritten path is counted (%d)" % count)
	check(SavePathMigration.migrate(config) == 0, "Migrating again changes nothing")

	var missing: Array[String] = []
	for old_path: String in SavePathMigration.LEGACY_SCENE_PATHS:
		var new_path: String = SavePathMigration.LEGACY_SCENE_PATHS[old_path]
		if not ResourceLoader.exists(new_path, "PackedScene") or ResourceLoader.exists(old_path):
			missing.append(old_path)
	check(missing.is_empty(), "Every legacy path is gone and maps to an existing scene (bad: %s)" % str(missing))

	# The real loader runs the migration on what it reads (read only: nothing is saved).
	var loader := SaveProgressService.new()
	loader.load_progress()
	var legacy_left := 0
	for section in loader._config.get_sections():
		for key: String in loader._config.get_section_keys(section):
			var text := key + var_to_str(loader._config.get_value(section, key))
			for old_path: String in SavePathMigration.LEGACY_SCENE_PATHS:
				if text.contains(old_path): legacy_left += 1
	check(legacy_left == 0, "load_progress() leaves no legacy scene path in the loaded save (%d left)" % legacy_left)
	loader.free()
	expect_save_untouched()
	finish("SAVE PATH MIGRATION")
