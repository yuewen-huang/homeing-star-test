extends SceneTree

class SaveFixture extends SaveProgressService:
	var fail_write := false
	var writes := 0
	func save_progress() -> bool:
		writes += 1
		return not fail_write

const DEER := &"test_final_deer_victory"
const CORE := &"test_vine_core_victory"
const REWARD := &"test_single_reward"
const MOVIE := &"test_once_movie"
var checks := 0
var failures := 0
var progress_events := 0
var inventory_events := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func run() -> void:
	var fixture := SaveFixture.new()
	fixture._loaded = true
	fixture.progress_changed.connect(func(): progress_events += 1)
	fixture.inventory_changed.connect(func(): inventory_events += 1)
	fixture._config.set_value("unrelated_old_section", "keep_me", "old data")
	check(fixture.get_cinematic_status(MOVIE) == SaveProgressService.CinematicStatus.UNHANDLED, "Missing cinematic means unhandled")
	check(not fixture.has_completed(DEER) and not fixture.has_claimed_reward(REWARD), "Missing facts do not invent completion")
	check(fixture.try_complete_fact(DEER), "Independent final victory may commit without prerequisites")
	check(fixture.has_completed(DEER) and not fixture.has_completed(CORE), "Final victory does not imply core victory")
	check(fixture.get_stele_state(&"mist_combat_01") == 0 and fixture.get_stele_state(&"mist_puzzle_entry") == 0, "Final victory does not complete optional steles")
	check(not fixture.has_completed(SaveProgressService.STORY_C1_YUPO_MET) and not fixture.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED), "Victory does not meet NPCs or accept quests")
	check(fixture.get_cinematic_status(MOVIE) == SaveProgressService.CinematicStatus.UNHANDLED, "Victory does not mark a cinematic watched")
	var writes := fixture.writes
	check(fixture.try_complete_fact(DEER) and fixture.writes == writes, "Repeated fact settlement is idempotent")
	check(fixture._config.get_value("unrelated_old_section", "keep_me") == "old data", "Legacy unknown keys survive new fact write")

	fixture.fail_write = true
	var snapshot := fixture._config.encode_to_text()
	var events := progress_events
	check(not fixture.try_complete_fact(CORE), "Failed fact write reports failure")
	check(not fixture.has_completed(CORE) and fixture._config.encode_to_text() == snapshot, "Failed fact write rolls back in-memory state")
	check(progress_events == events, "Failed write never announces completion")
	check(not fixture.finish_cinematic(MOVIE), "Failed cinematic write reports failure")
	check(fixture.get_cinematic_status(MOVIE) == SaveProgressService.CinematicStatus.UNHANDLED, "Failed viewing remains available for retry")
	check(not fixture.claim_unique_reward(REWARD, ItemCatalog.CHILD_KITE, 2), "Failed unique reward reports failure")
	check(not fixture.has_claimed_reward(REWARD) and fixture.get_item_count(ItemCatalog.CHILD_KITE) == 0, "Claim flag and inventory roll back together")
	check(inventory_events == 0 and progress_events == events, "Failed reward emits no success signals")

	fixture.fail_write = false
	check(fixture.finish_cinematic(MOVIE, true), "Explicit skip commits separately")
	check(fixture.get_cinematic_status(MOVIE) == SaveProgressService.CinematicStatus.SKIPPED, "Skipped remains distinct from watched")
	writes = fixture.writes
	check(fixture.finish_cinematic(MOVIE, false) and fixture.writes == writes \
		and fixture.get_cinematic_status(MOVIE) == SaveProgressService.CinematicStatus.SKIPPED, "Revisit preserves original skip outcome")
	check(fixture.finish_cinematic(&"test_second_movie") and fixture.get_cinematic_status(&"test_second_movie") == SaveProgressService.CinematicStatus.WATCHED, "Natural completion records watched")
	check(fixture.claim_unique_reward(REWARD, ItemCatalog.CHILD_KITE, 2), "Reward succeeds on retry")
	check(fixture.has_claimed_reward(REWARD) and fixture.get_item_count(ItemCatalog.CHILD_KITE) == 2, "Reward count and claim flag commit together")
	writes = fixture.writes
	check(fixture.claim_unique_reward(REWARD, ItemCatalog.CHILD_KITE, 2) and fixture.writes == writes \
		and fixture.get_item_count(ItemCatalog.CHILD_KITE) == 2 and inventory_events == 1, "Repeated claim never duplicates item or signals")
	check(not fixture.try_complete_fact(&"") and not fixture.finish_cinematic(&"") \
		and not fixture.claim_unique_reward(&"", ItemCatalog.CHILD_KITE), "Empty IDs rejected")
	check(not fixture.claim_unique_reward(&"bad", &"unknown_item") \
		and not fixture.claim_unique_reward(&"bad", ItemCatalog.CHILD_KITE, 0), "Invalid item and counts rejected")
	check(fixture.set_stele_state(&"mist_combat_01", 2) and fixture.set_stele_state(&"mist_combat_01", 1) \
		and fixture.get_stele_state(&"mist_combat_01") == 2, "Existing independent stele completion remains monotonic")
	var log_fixture := QuestLogService.new()
	log_fixture._save = fixture
	check(not log_fixture.get_track_view().is_empty(), "Before prologue completion old teaching guidance remains")
	fixture.try_complete_fact(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED)
	check(log_fixture.get_track_view().is_empty(), "First chapter hides stale prologue objectives without clearing their facts")
	check(not fixture.has_completed(SaveProgressService.TUTORIAL_CLIMB), "Hiding old guidance does not complete unfinished kite quest")
	fixture.try_complete_fact(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED)
	var view := log_fixture.get_track_view()
	check(view.quests.is_empty() and view.side_quests.size() == 1, "Free exploration keeps only explicitly accepted optional quest")
	log_fixture.free()
	fixture.free()
	print("OPEN PROGRESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
