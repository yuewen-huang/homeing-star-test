extends "../../tests/support/harness.gd"
## Map-only preview of the replacement layout for The Last Lamp.

const LAN := preload("res://scenes/player/lan/lan_player.tscn")
const OUTER := Rect2(0, 0, 3456, 720)
const INNER := Rect2(4800, 0, 3840, 720)
const GATE_ART_VIEW := Rect2(2176, 0, 1280, 720)
const GATE_ART_SCENE := "res://scenes/levels/chapter_2_underwater/cavern/cavern_zhenxi_gate_art.tscn"
const ARRIVAL := Vector2(310, 590)
const GATE_FRONT := Vector2(2860, 502)
const GATE_BACK := Vector2(4970, 548)
const ARCHIVE := Vector2(8230, 555)
const SIDE_DOOR := Vector2(8500, 555)
const SIDE_DOOR_LANDING := Vector2(3280, 502)
const FLOORS := [
	Vector4(0, 590, 820, 590), Vector4(820, 590, 1180, 540),
	Vector4(1180, 540, 1920, 540), Vector4(1920, 540, 2180, 502),
	Vector4(2180, 502, 3456, 502),
	Vector4(4800, 548, 6120, 548), Vector4(6120, 548, 6360, 500),
	Vector4(6360, 500, 7180, 500), Vector4(7180, 500, 7500, 555),
	Vector4(7500, 555, 8640, 555),
]

var _world := Node2D.new()
var _guides := Node2D.new()
var _player: LanPlayer
var _camera := Camera2D.new()
var _prompt := Label.new()
var _camera_area := OUTER
var _gate_art: Node2D
var _contact_shadow: Sprite2D


func run() -> void:
	use_memory_progress()
	root.title = "归航星 · 镇西门路线灰盒"
	root.add_child(_world)
	current_scene = _world
	_world.add_child(_guides)
	_player = LAN.instantiate() as LanPlayer
	_player.fallback_ground_y = 900
	_player.world_min_x = OUTER.position.x + 20
	_player.world_max_x = OUTER.end.x - 20
	_world.add_child(_player)
	_world.add_child(_camera)
	_camera.make_current()
	_build_map()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override(&"font_size", 22)
	_prompt.add_theme_constant_override(&"outline_size", 5)
	_world.add_child(_prompt)
	if "--gate-art" in OS.get_cmdline_user_args():
		root.title = "归航星 · 镇西门战坪美术"
		_gate_art = (load(GATE_ART_SCENE) as PackedScene).instantiate() as Node2D
		_gate_art.position = GATE_ART_VIEW.position
		_world.add_child(_gate_art)
		_contact_shadow = _gate_art.get_node("ContactShadow")
		_move_to(Vector2(2470, GATE_FRONT.y), GATE_ART_VIEW)
	else:
		_move_to(ARRIVAL, OUTER)
	physics_frame.connect(_update_controls)
	process_frame.connect(_update_view)
	print("ZHENXI_LAYOUT_READY")


func _build_map() -> void:
	_paint(PackedVector2Array([Vector2(0, 0), Vector2(3456, 0), Vector2(3456, 720),
		Vector2(0, 720)]), Color("31262b"), -5)
	_paint(PackedVector2Array([Vector2(4800, 0), Vector2(8640, 0), Vector2(8640, 720),
		Vector2(4800, 720)]), Color("28252b"), -5)
	for floor in FLOORS:
		var start := Vector2(floor.x, floor.y)
		var end := Vector2(floor.z, floor.w)
		var shape := PackedVector2Array([start, end, Vector2(end.x, 800), Vector2(start.x, 800)])
		var solid := StaticBody2D.new()
		var collision := CollisionPolygon2D.new()
		collision.polygon = shape
		solid.add_child(collision)
		_world.add_child(solid)
		_paint(shape, Color("443b40"), -2)
		var line := Line2D.new()
		line.points = PackedVector2Array([start, end])
		line.width = 3.0
		line.default_color = Color("887178")
		_guides.add_child(line)
		if is_equal_approx(start.y, end.y):
			_player.register_ground_surface(Rect2(start.x, start.y, end.x - start.x, 1))
		else:
			_player.register_sloped_ground(start, end)
	_block(Rect2(0, 0, 815, 344), Color("211d24"))
	_block(Rect2(1180, 425, 620, 115), Color("66513d"))
	_block(Rect2(2690, 170, 390, 332), Color("6a5556"))
	_block(Rect2(2788, 304, 170, 198), Color("231e24"))
	_block(Rect2(3208, 360, 144, 142), Color("51444b"))
	_block(Rect2(4800, 0, 590, 330), Color("201c24"))
	_block(Rect2(5410, 220, 690, 328), Color("51444b"))
	_block(Rect2(6360, 249, 820, 251), Color("54414a"))
	_block(Rect2(8065, 267, 575, 288), Color("4e4550"))
	_label("水道出口", Vector2(260, 480))
	_label("残田 · 初见镇西门", Vector2(1510, 375))
	_label("镇西门", Vector2(2860, 227))
	_label("门前战坪", Vector2(2360, 368))
	_label("旧灯座", Vector2(2635, 447))
	_label("侧门出口", Vector2(SIDE_DOOR_LANDING.x, 335))
	_label("城墙内的门道", Vector2(5050, 374))
	_label("军屯库 · 军屯簿", Vector2(5700, 430))
	_label("守军营房 · 守城令", Vector2(6650, 380))
	_label("夜哨回廊 · 最后一夜", Vector2(7530, 405))
	_label("档案室 · 史册残页", Vector2(ARCHIVE.x, 420))
	_label("侧门回灯座", Vector2(SIDE_DOOR.x, 484))


func _block(area: Rect2, color: Color) -> void:
	_paint(PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
		area.end, Vector2(area.position.x, area.end.y)]), color, -3)


func _paint(outline: PackedVector2Array, color: Color, depth: int) -> void:
	var face := Polygon2D.new()
	face.polygon = outline
	face.color = color
	face.z_index = depth
	_guides.add_child(face)


func _label(value: String, center: Vector2) -> void:
	var label := Label.new()
	label.position = center - Vector2(190, 12)
	label.size.x = 380
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 26)
	label.add_theme_color_override(&"font_color", Color("ead5c7"))
	label.text = value
	_guides.add_child(label)


func _move_to(at: Vector2, area: Rect2) -> void:
	_camera_area = area
	_guides.visible = area != GATE_ART_VIEW
	if _gate_art:
		_gate_art.visible = area == GATE_ART_VIEW
	_player.world_min_x = area.position.x + 20
	_player.world_max_x = area.end.x - 20
	_player.reset_after_map_fall(at)
	_camera.limit_left = int(area.position.x)
	_camera.limit_right = int(area.end.x)
	_update_view()
	_camera.reset_smoothing()


func _update_view() -> void:
	var target_x := clampf(_player.position.x, _camera_area.position.x + 640, _camera_area.end.x - 640)
	_camera.position = Vector2(target_x, 360)
	if _gate_art and _gate_art.visible:
		_contact_shadow.position = Vector2(_player.position.x - GATE_ART_VIEW.position.x, GATE_FRONT.y + 1.0)
		var lift := clampf((GATE_FRONT.y - _player.position.y) / 120.0, 0.0, 1.0)
		_contact_shadow.modulate.a = lerpf(0.72, 0.12, lift)
	var portal := _near_portal()
	_prompt.visible = not portal.is_empty()
	if _prompt.visible:
		_prompt.text = "E · " + portal[2]
		_prompt.position = _player.position + Vector2(-126, -120)
		_prompt.size.x = 252


func _near_portal() -> Array:
	var court := GATE_ART_VIEW if _gate_art else OUTER
	if _camera_area == court and _player.position.distance_to(GATE_FRONT) < 104:
		return [GATE_BACK + Vector2(135, 0), INNER, "穿过镇西门"]
	if _camera_area == INNER:
		if _player.position.distance_to(GATE_BACK) < 104:
			return [GATE_FRONT - Vector2(130, 0), court, "回门前"]
		if _player.position.distance_to(SIDE_DOOR) < 104:
			return [SIDE_DOOR_LANDING, court, "从侧门回到战坪"]
	return []


func _update_controls() -> void:
	if not Input.is_action_just_pressed(&"interact"):
		return
	var portal := _near_portal()
	if not portal.is_empty():
		_move_to(portal[0], portal[1])
