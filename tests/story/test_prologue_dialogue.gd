extends "../support/harness.gd"

const DIALOGUE := preload("res://scripts/story/prologue_dialogue.gd")
const STAGED_VIEW := preload("res://scripts/ui/main_story_dialogue.gd")
const TOWN := "res://scenes/levels/town/homeward_town.tscn"

func press_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"Capture " + label)


func verify_dialogue(dialogue: TutorialDialogue, scene: String, player: LanPlayer) -> bool:
	var active := dialogue != null and dialogue is STAGED_VIEW and dialogue.opened
	check(active, scene + " uses the new dialogue through the actual interaction")
	if not active:
		return false
	check(player.input_frozen, scene + " freezes controls")
	check(dialogue._lines.size() == DIALOGUE.TEXT[scene].size(), scene + " presents every line")
	for index in dialogue._lines.size():
		var source: Dictionary = DIALOGUE.TEXT[scene][index]
		var shown: Dictionary = dialogue._lines[index]
		check(shown["text"] == source["text"] and shown["name"] == source["name"],
			"%s line %d retains source wording" % [scene, index + 1])
	for actor: Variant in dialogue._actors.values():
		check(actor.current.texture != null, scene + " loads its authored portraits")
	return true


func run() -> void:
	var save := use_memory_progress()
	(root.get_node("QuestLog") as QuestLogService)._save = save
	for fact: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP]:
		save.mark_completed(fact)
	var town: Node2D = load(TOWN).instantiate()
	root.add_child(town)
	current_scene = town
	await create_timer(0.75).timeout
	var player := town.get("player") as LanPlayer
	var stats := player.combat_stats
	check(stats.health < stats.max_health, "Lan starts hungry")
	player.position.x = town.maidashu.position.x
	await wait_frames(8)
	press_e()
	var dialogue := town.opening_guide.get("_dialogue") as TutorialDialogue
	if not verify_dialogue(dialogue, "breakfast", player):
		finish("PROLOGUE DIALOGUE")
		return
	check(not town.player.get_node("PlayerStatusHUD").visible, "The staged scene hides the gameplay HUD")
	check(dialogue._label.visible_characters < dialogue._label.text.length(), "The first line types in")
	press_e()
	check(dialogue.get_line_progress() == Vector2i(0, 7), "E completes the text before moving on")
	await capture("01-breakfast-guests")
	press_e()
	check(dialogue.get_line_progress() == Vector2i(1, 7), "Next E advances exactly one line")
	for index in 3:
		dialogue.advance()
	var listener = dialogue._actors[&"maidashu"]
	check(listener.current.texture.resource_path.ends_with("serves_soup.png"),
		"Maida is initially at ease with Lan")
	check(not save.has_completed(DIALOGUE.BREAKFAST_SEEN), "A partially read scene is still pending")
	var trigger := dialogue._label.text.length()
	dialogue._reveal(trigger - 1)
	check(listener.current.texture.resource_path.ends_with("serves_soup.png"),
		"The listener holds his pose before hearing about the fire")
	dialogue._reveal(trigger)
	check(listener.current.texture.resource_path.ends_with("worried.png"),
		"The listener reacts on the purple-fire line before the next input")
	await create_timer(0.22).timeout
	await capture("02-breakfast-purple-fire")
	while dialogue.opened:
		dialogue.advance()
	check(town.player.get_node("PlayerStatusHUD").visible, "Closing the scene restores the gameplay HUD")
	check(not player.input_frozen and stats.health == stats.max_health,
		"Breakfast restores health and returns control")
	check(save.has_completed(DIALOGUE.BREAKFAST_SEEN)
		and save.has_completed(SaveProgressService.TUTORIAL_BREAKFAST)
		and save.has_completed(SaveProgressService.STORY_EATING_TALK),
		"Breakfast settles the new story fact and both existing steps")

	for fact: StringName in [SaveProgressService.TUTORIAL_CLIMB, SaveProgressService.QUEST_CHILD_KITE_PICKED,
			SaveProgressService.QUEST_FIRST_SIGHT_STEP, SaveProgressService.QUEST_LAN_AND_WIND_STEP]:
		save.mark_completed(fact)
	current_scene = null
	town.queue_free()
	await wait_frames(4)
	town = load(TOWN).instantiate()
	root.add_child(town)
	current_scene = town
	player = town.get("player") as LanPlayer
	check(not save.has_completed(DIALOGUE.STAR_OBSERVED) and town.wind_npc != null,
		"Legacy hall progress can still reach Wind without reshowing breakfast or the star")
	if town.wind_npc == null:
		finish("PROLOGUE DIALOGUE")
		return
	player.position.x = town.wind_npc.position.x
	await wait_frames(4)
	press_e()
	dialogue = town.wind_npc.get("_dialogue") as TutorialDialogue
	if not verify_dialogue(dialogue, "wind_day", player):
		finish("PROLOGUE DIALOGUE")
		return
	dialogue._complete_line()
	await capture("03-wind-day")
	dialogue.advance()
	dialogue.advance()
	check(dialogue._actors[&"wind"].current.texture.resource_path.ends_with("day_serious.png"),
		"Wind becomes serious when he mentions changes in town")
	dialogue.advance()
	check(dialogue._actors[&"lan"].current.texture.resource_path.ends_with("caught_off_guard.png"),
		"Lan is surprised when Wind already understands the problem")
	dialogue._complete_line()
	await create_timer(0.22).timeout
	await capture("03b-wind-listener")
	while dialogue.opened:
		dialogue.advance()
	check(save.has_completed(DIALOGUE.WIND_DISAGREEMENT_HEARD)
		and save.has_completed(SaveProgressService.STORY_LAN_AND_WIND_TALK),
		"Wind opens the magic shop quest")

	player.position.x = town.magic_shop_owner.position.x
	await create_timer(3.1).timeout
	press_e()
	var quest: Node = town.back_alley_quest
	dialogue = quest.get("_dialogue") as TutorialDialogue
	if not verify_dialogue(dialogue, "shop", player):
		finish("PROLOGUE DIALOGUE")
		return
	dialogue.advance()
	dialogue.advance()
	dialogue._complete_line()
	await create_timer(0.22).timeout
	await capture("04-shop-bead")
	while dialogue.opened:
		dialogue.advance()
	check(save.has_completed(DIALOGUE.SHOP_ANOMALIES_HEARD)
		and save.has_completed(SaveProgressService.STORY_MAGIC_SHOP_TALK),
		"The shop settles both new and legacy quest facts")
	check(save.get_item_count(ItemCatalog.HANGOVER_PILL) == 1
		and ItemCatalog.get_item(ItemCatalog.HANGOVER_PILL)["name"] == "醒酒珠",
		"The bead retains its inventory ID and uses the agreed display name")
	check(save.try_complete_facts([DIALOGUE.SHOP_ANOMALIES_HEARD], ItemCatalog.HANGOVER_PILL)
		and save.get_item_count(ItemCatalog.HANGOVER_PILL) == 1,
		"Retrying the item settlement cannot increase its count")
	check(save.equip_special_item(ItemCatalog.HANGOVER_PILL), "The existing item can equip to Q")
	await wait_frames(3)
	check(save.has_completed(SaveProgressService.STORY_HANGOVER_PILL_EQUIPPED),
		"Equipping the item retains the existing alley milestone")
	expect_save_untouched()
	finish("PROLOGUE DIALOGUE")
