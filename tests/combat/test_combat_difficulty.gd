extends SceneTree
## Combat difficulty v0.1 (2026-10-16): normal / hard / nightmare replace the contact parry
## prompt. Normal: a manual parry auto-parries the rest of that combo (red without PLUS) and
## a blue cue marks the hit Lan must parry herself; nightmare hides the shared range warnings.
## Design: ../homeing-star-doc/docs/design/combat_difficulty_v0_1.md.

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

class KeyedSource extends Node2D:
	var key: StringName = &"combo_a"
	func get_parry_chain_key() -> StringName: return key

var failures := 0
var checks := 0
var assist: BattleAssistSettingsService

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	test_difficulty_switch()
	test_chain_rules()
	await test_lan_chain_parry()
	await test_telegraph_gate()
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	check((FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if FileAccess.file_exists(SaveProgressService.SAVE_PATH) else PackedByteArray()) == saved, "difficulty changes never write story progress")
	print("COMBAT_DIFFICULTY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_difficulty_switch() -> void:
	var modes := BattleAssistSettingsService.Difficulty
	assist.set_difficulty(modes.EASY)
	check(assist.player_invincible and assist.uses_parry_chain_assist() and assist.shows_attack_telegraphs(), "easy preserves normal combat cues and enables lethal refill")
	var changes: Array = []
	assist.difficulty_changed.connect(func(d: int) -> void: changes.append(d))
	assist.set_difficulty(modes.HARD)
	check(not assist.player_invincible and not assist.uses_parry_chain_assist() and assist.shows_attack_telegraphs(), "hard keeps warnings and manual parries")
	assist.set_difficulty(modes.NIGHTMARE)
	check(not assist.player_invincible and not assist.uses_parry_chain_assist() and not assist.shows_attack_telegraphs(), "nightmare hides range warnings")
	assist.set_difficulty(modes.NORMAL)
	check(not assist.player_invincible and assist.uses_parry_chain_assist() and assist.shows_attack_telegraphs(), "normal keeps the parry assist without lethal refill")
	check(changes == [modes.HARD, modes.NIGHTMARE, modes.NORMAL], "difficulty changes report each selected mode")

func test_chain_rules() -> void:
	var chain := ParryChainAssist.new()
	var plain := Node2D.new()
	var other := Node2D.new()
	var keyed := KeyedSource.new()
	check(not chain.covers(plain, 0.0), "no chain before a manual parry")
	chain.begin(plain, 10.0)
	check(chain.covers(plain, 10.0 + ParryChainAssist.FALLBACK_GAP), "unkeyed source: next contact within the gap is covered")
	check(not chain.covers(plain, 10.0 + ParryChainAssist.FALLBACK_GAP + 0.01), "unkeyed source: a longer gap ends the combo")
	check(not chain.covers(other, 10.2), "another unkeyed source is a different combo")
	chain.touch(10.9)
	check(chain.covers(plain, 11.8), "an automatic parry extends the chain from its contact")
	chain.begin(keyed, 20.0)
	check(chain.covers(keyed, 20.0 + ParryChainAssist.KEYED_GAP), "keyed source: whole combo covered up to the safety gap")
	check(not chain.covers(keyed, 20.0 + ParryChainAssist.KEYED_GAP + 0.01), "keyed source: safety gap still ends it")
	keyed.key = &"combo_b"
	check(not chain.covers(keyed, 20.5), "keyed source: a new combo key needs a new manual parry")
	keyed.key = &"combo_a"
	chain.cancel()
	check(not chain.covers(keyed, 20.5) and not chain.active, "cancel ends the chain")
	for node in [plain, other, keyed]: node.free()

func test_lan_chain_parry() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	var room: Chapter1DeerBossRoom = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	if is_instance_valid(room.story.comic): room.story._close_intro()
	room.deer.set_physics_process(false)
	room.player.set_physics_process(false)
	room.deer.manual_control = true
	assist.set_player_invincible(false)
	var lan := room.player
	var reset := func() -> void:
		lan.reset_after_map_fall(Vector2(600, 555))
		lan.combat_stats.restore_health()
		lan.velocity = Vector2.ZERO
		lan.defense_state = LanPlayer.DefenseState.NONE
	var hit := func(danger: CombatAttackData.DangerType) -> CombatAttackData:
		return CombatAttackData.new(&"chain_hit", room.deer, 20, 12, 180, 0, danger)
	check(room.deer.get_parry_chain_key() != &"", "production deer groups attacks by its current combo key")

	reset.call()
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.NORMAL_HIT, "normal: the first hit still needs a manual parry")
	reset.call()
	lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.PARRY_SUCCESS and lan.parry_chain.active, "normal: a manual parry starts the chain")
	lan.defense_state = LanPlayer.DefenseState.NONE
	lan.combat_clock += 0.5
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.PARRY_SUCCESS \
		and lan.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS and lan.combat_stats.health == lan.combat_stats.max_health, "normal: the next combo hit is parried automatically")
	lan.combat_clock += 0.5
	var red: CombatAttackData = hit.call(CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(lan.receive_combat_hit(red) == CombatHitResult.Type.PARRY_SUCCESS and lan.defense_state == LanPlayer.DefenseState.PARRY_SUCCESS \
		and red.danger_type == CombatAttackData.DangerType.NORMAL, "normal: an auto-parried red hit settles as an ordinary parry (no PLUS)")
	lan.combat_clock += 0.5
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.UNPARRYABLE_DANGER)) == CombatHitResult.Type.NORMAL_HIT and not lan.parry_chain.active, "normal: gold hits are never auto-parried and end the chain")
	reset.call()
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.NORMAL_HIT, "normal: after a missed hit the next one needs a manual parry again")

	reset.call()
	lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var manual_red: CombatAttackData = hit.call(CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(lan.receive_combat_hit(manual_red) == CombatHitResult.Type.PARRY_SUCCESS and lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS \
		and manual_red.danger_type == CombatAttackData.DangerType.COUNTERABLE_DANGER and lan.parry_chain.active, "normal: a manual red parry keeps its PLUS and starts the chain")
	lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL))
	check(lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "normal: a running red counter is not interrupted by an auto-parry")

	reset.call()
	lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL))
	lan.defense_state = LanPlayer.DefenseState.NONE
	lan.non_parry_action_requested.emit()
	check(not lan.parry_chain.active and lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.NORMAL_HIT, "normal: jumping / attacking / dodging ends the chain")

	reset.call()
	lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL))
	lan.defense_state = LanPlayer.DefenseState.NONE
	lan.combat_clock += ParryChainAssist.KEYED_GAP + 0.1
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.NORMAL_HIT, "normal: a long pause between hits ends the keyed chain")

	for d in [BattleAssistSettingsService.Difficulty.HARD, BattleAssistSettingsService.Difficulty.NIGHTMARE]:
		assist.set_difficulty(d)
		reset.call()
		lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
		check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.PARRY_SUCCESS, "difficulty %d: manual parry works" % d)
		lan.defense_state = LanPlayer.DefenseState.NONE
		check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.NORMAL_HIT, "difficulty %d: every parry stays manual" % d)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)

	# A chain started under normal stops covering once the player switches difficulty.
	reset.call()
	lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL))
	lan.defense_state = LanPlayer.DefenseState.NONE
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(lan.receive_combat_hit(hit.call(CombatAttackData.DangerType.NORMAL)) == CombatHitResult.Type.NORMAL_HIT, "switching to hard ends an open chain")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	await test_deer_cue(room)
	assist.set_player_invincible(true)
	room.queue_free()
	await process_frame; await process_frame

func test_telegraph_gate() -> void:
	var owner := Node2D.new()
	root.add_child(owner)
	var warning := AttackTelegraph.create_for(owner)
	var draw := func() -> int:
		warning.begin()
		warning.rectangle(Rect2(0, 0, 100, 40), 0, 0.5)
		warning.oval(Vector2(50, 0), Vector2(30, 10), 1, 0.5)
		warning.strip(Vector2.ZERO, Vector2(120, 0), 20, 2, 0.5)
		warning.end()
		var shown := 0
		for mark in warning.get_children(): if (mark as CanvasItem).visible: shown += 1
		return shown
	for d in [BattleAssistSettingsService.Difficulty.NORMAL, BattleAssistSettingsService.Difficulty.HARD]:
		assist.set_difficulty(d)
		check(draw.call() == 3, "difficulty %d shows range warnings" % d)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	check(draw.call() == 0, "nightmare hides every range warning, including ones already up")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	check(draw.call() == 3, "warnings return when leaving nightmare")
	owner.queue_free()
	await process_frame

func test_deer_cue(room: Chapter1DeerBossRoom) -> void:
	var deer := room.deer
	var lan := room.player
	deer.manual_control = false
	lan.parry_chain.cancel()
	deer.position.x = 820.0
	lan.global_position.x = 600.0
	deer.start_move(2, lan.position.x)
	deer._report_duel_cue()
	check(lan.parry_cue.source == deer and lan.parry_cue.should_show(), "the production sweep shows the cue on normal")
	lan.parry_cue._process(0.0)
	check(lan.parry_cue._display.is_visible_in_tree(), "the baked blue cue sprite is actually visible, not only its parent")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.EASY)
	check(lan.parry_cue.should_show(), "easy retains the normal blue cue")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	check(not lan.parry_cue.should_show(), "no blue cue on hard")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	lan.parry_chain.begin(deer, lan.combat_clock)
	check(not lan.parry_cue.should_show(), "no blue cue while the chain will parry this combo")
	lan.parry_chain.cancel()
	await physics_frame; await physics_frame; await physics_frame
	check(not lan.parry_cue.should_show(), "the cue drops once the deer stops reporting")
	lan.parry_cue.report(deer, ParryCueVisual.APPEAR_LEAD + 0.1)
	check(not lan.parry_cue.should_show(), "hits further out than the lead are not cued")
	lan.global_position.x = deer.position.x - 480.0
	deer._report_duel_cue()
	check(not lan.parry_cue.should_show(), "a sweep that cannot reach the target gets no cue")
