extends SceneTree

## The four forest maps mark route forks with wooden signposts instead of floating
## text, and portals carry no sign of their own. With a visible window (-Visual)
## every signpost is captured to HOMING_STAR_TEST_OUTPUT.
class TestProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

const E := ForestSignBoard.Emblem
## Signpost path → {board name: [direction_degrees, emblem]}.
const ROOMS := {
	"res://scenes/levels/chapter_1/chapter_1_mist_room.tscn": {
		"Signs/StairFork": {"ToWind": [-40.0, E.WIND], "ToRoot": [0.0, E.ROOT]},
	},
	"res://scenes/levels/chapter_1/chapter_1_root_room.tscn": {
		"Signs/WestShoreFork": {"ToVine": [0.0, E.VINE], "ToBasin": [35.0, E.NONE]},
		"Signs/EastShoreFork": {"ToVine": [-60.0, E.VINE], "ToHeart": [-120.0, E.ROOT]},
		"Signs/SunkenShaft": {"ToEastShore": [-55.0, E.VINE]},
		"Signs/GalleryFork": {"ToVine": [0.0, E.VINE], "ToHeart": [180.0, E.ROOT]},
	},
	"res://scenes/levels/chapter_1/chapter_1_wind_room.tscn": {
		"Signs/WestRestFork": {"ToPuzzle": [-130.0, E.NONE], "ToVine": [-50.0, E.VINE]},
		"Signs/CoreFork": {"ToVine": [-45.0, E.VINE], "ToCore": [45.0, E.WIND]},
		"Signs/CoreReturn": {"ToVine": [-30.0, E.VINE]},
	},
	"res://scenes/levels/chapter_1/chapter_1_vine_room.tscn": {
		"Signs/EntryFork": {"ToFinal": [0.0, E.BOSS], "ToRoot": [35.0, E.ROOT]},
		"Signs/MiddleWestFork": {"ToCore": [150.0, E.VINE], "ToRoot": [30.0, E.ROOT]},
		"Signs/LowerWestFork": {"ToCore": [180.0, E.VINE], "ToRoot": [0.0, E.ROOT]},
	},
}
## Interaction/UI text that stays text: stele inscriptions, winch and E-key prompts, HUD.
const KEPT_LABELS := ["StateInscription", "ProgressHint", "WinchHint", "InteractKeycap"]

var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var save := TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	save.load_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT") if DisplayServer.get_name() != "headless" else ""
	check_board_geometry()
	for path: String in ROOMS:
		await check_room(path, ROOMS[path])
	(root.get_node("SceneTransition") as SceneTransitionService).music_player.stop()
	if failures == 0:
		print("PASS: forest forks carry signposts with upright tip emblems; no portal signs or floating route text")
	quit(1 if failures else 0)

## Leftward boards are mirrored rather than upside down; the emblem sits on the tip half and stays upright.
func check_board_geometry() -> void:
	var post := ForestSignpost.new()
	var board := ForestSignBoard.new()
	post.add_child(board)
	root.add_child(post)
	board.emblem = E.WIND
	for degrees in [0.0, -45.0, 60.0, 120.0, 180.0, -135.0]:
		board.direction_degrees = degrees
		var art := board.get_node("Board") as Sprite2D
		var emblem := board.get_node("Emblem") as Sprite2D
		check(absf(art.rotation) <= PI * 0.5 + 0.001, "board at %d° is not upside down" % degrees)
		check(is_zero_approx(emblem.global_rotation), "emblem at %d° stays upright" % degrees)
		check(emblem.position.dot(board.direction()) > art.position.dot(board.direction()),
			"emblem at %d° sits on the arrow-tip half" % degrees)
	var plate := board.get_node("EmblemPlate") as Node2D
	var emblem_sprite := board.get_node("Emblem") as Sprite2D
	check(plate.visible and plate.position == emblem_sprite.position and plate.get_index(true) < emblem_sprite.get_index(true),
		"light plate sits behind the emblem")
	board.emblem = E.NONE
	check(not plate.visible, "boards without an emblem have no plate")
	check(post.get_node("Post").scale.x > 1.0 and is_equal_approx(board.get_node("Board").scale.x, 1.0),
		"stake is drawn thicker than the 1.0-scale boards")
	post.free()

func check_room(path: String, expected: Dictionary) -> void:
	var room: Node2D = load(path).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	var room_name := path.get_file().get_basename()
	var found := 0
	for node in room.find_children("*", "", true, false):
		if node is ForestSignpost:
			found += 1
			check(not node.get_parent() is Marker2D, "%s %s is not a portal-side sign" % [room_name, room.get_path_to(node)])
	check(found == expected.size(), "%s has %d signposts (expected %d)" % [room_name, found, expected.size()])
	for sign_path: String in expected:
		var signpost := room.get_node_or_null(sign_path) as ForestSignpost
		check(signpost != null, "%s %s exists" % [room_name, sign_path])
		if signpost == null:
			continue
		var want: Dictionary = expected[sign_path]
		check(signpost.boards().size() == want.size(), "%s %s has %d boards" % [room_name, sign_path, want.size()])
		for board_name: String in want:
			var board := signpost.get_node_or_null(board_name) as ForestSignBoard
			check(board != null and is_equal_approx(board.direction_degrees, want[board_name][0])
				and board.emblem == want[board_name][1], "%s %s/%s points %s" % [room_name, sign_path, board_name, want[board_name]])
			if board != null:
				var tip := board.global_position + board.tip_position()
				check(tip.y < signpost.global_position.y - 20.0, "%s %s/%s stays above the ground" % [room_name, sign_path, board_name])
		check(_stands_on_walkway(room, signpost), "%s %s stands on a walkway at %s" % [room_name, sign_path, signpost.global_position])
		await capture(room, signpost, "%s_%s" % [room_name, sign_path.get_file()])
	for label in room.find_children("*", "Label", true, false):
		if _in_canvas_layer(label) or label.name in KEPT_LABELS or label.get_parent().name in KEPT_LABELS:
			continue
		check(false, "%s keeps floating text %s: %s" % [room_name, room.get_path_to(label), (label as Label).text])
	room.queue_free()
	await process_frame
	await process_frame

## A signpost must stand on a platform top: terrain pieces, root cave rock or the mist floor.
func _stands_on_walkway(room: Node2D, signpost: ForestSignpost) -> bool:
	var at := signpost.global_position
	if room.scene_file_path.ends_with("chapter_1_mist_room.tscn"):
		return is_equal_approx(at.y, SideviewMapLayout.GROUND_BASELINE_Y)
	for node in room.find_children("*", "", true, false):
		var start := Vector2.INF
		var width := 0.0
		if node is TerrainPiece:
			start = node.global_position
			width = node._walk_length()
		elif node is RootRockBlock:
			start = node.global_position
			width = node.size.x
		if width > 0.0 and absf(at.y - start.y) < 1.0 and at.x > start.x + 30.0 and at.x < start.x + width - 30.0:
			return true
	return false

func _in_canvas_layer(node: Node) -> bool:
	while node != null:
		if node is CanvasLayer:
			return true
		node = node.get_parent()
	return false

func capture(room: Node2D, signpost: ForestSignpost, filename: String) -> void:
	if output.is_empty():
		return
	var player := room.get("player") as LanPlayer
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.global_position = signpost.global_position + Vector2(-110, 0)
	for i in 4:
		await process_frame
	var camera := room.get_viewport().get_camera_2d()
	camera.reset_smoothing()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))
