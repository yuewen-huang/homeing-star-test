extends "../support/harness.gd"

func run() -> void:
	use_memory_progress()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CombatLessonCatalog.ROOT + "manifest.json"))
	for id: StringName in CombatLessonCatalog.LESSONS:
		var master := id in CombatLessonCatalog.MASTER_ONLY
		verify_clip(CombatLessonCatalog.video_path(id, master), "tutorial" if master else "back_alley", manifest)
	verify_clip(CombatLessonCatalog.video_path(&"poise_throw", true), "tutorial", manifest)
	check(CombatLessonCatalog.record_id(&"poise_throw", true) != CombatLessonCatalog.record_id(&"poise_throw"), "Throw viewing records follow scene context")
	check(CombatLessonCatalog.record_id(&"normal_attack") != &"combat_lesson_normal_attack", "Old wrong-scene recording cannot suppress the corrected lesson")
	check(not CombatLessonCatalog.text(&"spirit").contains("变身"), "First-drink dialogue does not reveal transformation")
	expect_save_untouched()
	finish("COMBAT LESSON CONTEXT")

func verify_clip(path: String, scene: String, manifest: Dictionary) -> void:
	var file := path.get_file()
	check(manifest.has(file), "Recording provenance exists: %s" % file)
	if not manifest.has(file): return
	var clip: Dictionary = manifest[file]
	check(clip.scene == scene, "Recorded scene matches trigger: %s" % file)
	if file.begins_with("phase_2_") or file == "ultimate.ogv":
		check(int(clip.get("phase", 0)) == 2, "Second-form lesson uses the second-form body")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(FileAccess.get_file_as_bytes(path))
	check(hash.finish().hex_encode() == clip.sha256, "Shipped video matches verified footage: %s" % file)
	if scene == "back_alley":
		check(not "master" in clip.enemies, "Alley video does not expose the master")
		check(not "ultimate" in clip.unlocked and not "parry" in clip.unlocked, "Alley HUD hides future abilities")
		check(clip.hit_verified, "Current-wave attack actually lands")
