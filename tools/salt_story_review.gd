extends SceneTree
## Isolated manual review; no production save file is read or written.
class ReviewSave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var field: Chapter2SaltField
var progress: ReviewSave
class ReviewInput extends Node:
	var review
	func _input(event: InputEvent) -> void: review.handle_input(event)
func _initialize() -> void: start.call_deferred()
func start() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	progress = ReviewSave.new(); progress.name = "SaveProgress"; root.add_child(progress)
	var input := ReviewInput.new(); input.review = self; root.add_child(input)
	_enter(Vector2(600,1510))
func _enter(feet: Vector2) -> void:
	if is_instance_valid(current_scene): current_scene.free()
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field); current_scene = field
	field.feet = feet
	field._sync_view(0)
func handle_input(event: InputEvent) -> void:
	if paused or not current_scene is Chapter2SaltField: return
	field = current_scene
	if field.crab_encounter.active or field.crab_encounter.session_active: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	var index := [KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F7,KEY_F8].find(event.physical_keycode)
	if index < 0: return
	root.set_input_as_handled()
	var kinds := ["shed", "apu", "road"]
	if index < 4:
		field.feet = field.shibo.POINT + Vector2(-60,0) if index == 0 else field.salt_story.points[kinds[index-1]].ground + Vector2(-42,5)
		field._sync_view(0)
	else:
		progress.try_complete_fact(&"chapter_2_salt_crab_defeated")
		if index == 5:
			progress._config.set_value("cinematics", "salt_to_mirror_lake", SaveProgressService.CinematicStatus.UNHANDLED)
			progress._config.set_value("progress", "salt_crab_departure_dialogue", false)
		_enter(Vector2(5760,1470))
		if index == 5:
			field.crab_encounter._start_departure()
