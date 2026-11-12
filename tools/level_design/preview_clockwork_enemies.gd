extends "../../tests/support/harness.gd"

const ROOM := preload("clockwork_enemy_room.gd")
const NAMES := ["机关牛", "机关鸟", "机关蛇"]

var _room: Node2D
var _index := 0


func run() -> void:
	use_memory_progress()
	root.window_input.connect(_on_window_input)
	var arguments := OS.get_cmdline_user_args()
	if "--bird" in arguments:
		_index = 1
	elif "--snake" in arguments:
		_index = 2
	_open_room(_index)


func _on_window_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode
	if key == KEY_NONE:
		key = event.keycode
	if key == KEY_R:
		_open_room.call_deferred(_index)
	elif key >= KEY_1 and key <= KEY_3:
		_open_room.call_deferred(int(key) - int(KEY_1))


func _open_room(index: int) -> void:
	if is_instance_valid(_room):
		root.remove_child(_room)
		_room.queue_free()
	_index = index
	_room = ROOM.new()
	root.add_child(_room)
	current_scene = _room
	_room.build(index)
	root.title = "归航星 · 沉没古城 · " + NAMES[index]
	print("CLOCKWORK_PREVIEW_READY ", index)
