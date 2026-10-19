extends SceneTree

## Generates scenes/sideview/chapter_1_root_room.tscn (root water cavern) from
## the layout tables below. After generation the .tscn is the source of truth:
## adjust nodes in the editor. Re-running this tool OVERWRITES manual edits.
##
##   "<godot>" --headless --path ../homeing-star-game --script <本文件的绝对路径>
##
## Coordinates: y grows downwards. Water levels LOW 1910 / MID 1240 / HIGH 700.

const OUT := "res://scenes/sideview/chapter_1_root_room.tscn"
const ROOM_SCRIPT := preload("res://scripts/sideview/chapter_1_root_room.gd")
const WATER_SCRIPT := preload("res://scripts/sideview/root_water.gd")
const SHELL_SCRIPT := preload("res://scripts/sideview/root_cave_shell.gd")
const BLOCK_SCRIPT := preload("res://scripts/sideview/root_rock_block.gd")
const LOG_SCRIPT := preload("res://scripts/sideview/root_float_log.gd")
const WINCH_SCRIPT := preload("res://scripts/sideview/root_water_winch.gd")
const STELE_SCRIPT := preload("res://scripts/sideview/minigame_stele.gd")
const FUNGUS_SCENE := preload("res://scenes/sideview/terrain_parts/root_light_fungus.tscn")
const GATE_SCENE := preload("res://scenes/sideview/terrain_parts/root_light_gate.tscn")
const FAR_ART := preload("res://assets/sideview/environment/chapter_1_root/layers/01_far_cavern.png")
const MID_ART := preload("res://assets/sideview/environment/chapter_1_root/layers/02_mid_root_arch.png")
const FRONT_ART := preload("res://assets/sideview/environment/chapter_1_root/layers/04_foreground_roots.png")

## name, x, y, width, height, flags ("checkpoint", "hanging")
const BLOCKS := [
	# Ceiling. The gap at x 4880..5060 is the shaft up to the vine region.
	["CeilingWest", 0, 0, 1200, 130, ""],
	["CeilingBasin", 1200, 0, 2560, 250, ""],
	["StalactiteWest", 1330, 250, 200, 60, ""],
	["StalactiteMiddle", 2560, 250, 300, 90, ""],
	["CeilingEast", 3760, 0, 1120, 300, ""],
	["CeilingEdge", 5060, 0, 60, 300, ""],
	# Root-heart vestibule (inner corner of the 2×2 chapter map) and its ledge.
	["VestibuleWall", 0, 130, 120, 250, ""],
	["VestibuleFloor", 0, 380, 1300, 90, "checkpoint"],
	["HeartLedgeLip", 1200, 380, 100, 160, ""],
	["WestStep", 1250, 540, 250, 80, ""],
	# Low entrance tunnel from the mist region, then steps down to the west shore.
	["EntranceFloor", 0, 640, 760, 1520, "checkpoint"],
	["StepOne", 760, 760, 140, 1400, ""],
	["StepTwo", 900, 900, 140, 1260, ""],
	["StepThree", 1040, 1040, 140, 1120, ""],
	["WestShore", 1180, 1180, 380, 980, "checkpoint"],
	# Basin floor: ridges and shallow pools at the low level.
	["BasinFloorWest", 1560, 1880, 340, 280, "checkpoint"],
	["BasinPoolWest", 1900, 1935, 400, 225, ""],
	# Stone held up by roots: an island at the middle level, walk under it at the low one.
	["StonePillar", 2300, 1190, 180, 420, "hanging"],
	["BasinUnderStone", 2300, 1935, 180, 225, ""],
	["BasinRidge", 2480, 1890, 420, 270, ""],
	["BasinPoolEast", 2900, 1935, 400, 225, ""],
	["BasinFloorEast", 3300, 1890, 500, 270, ""],
	# Hanging knots reached only at the high level.
	["CrownKnot", 2100, 540, 300, 70, "hanging"],
	["RootBridgeKnot", 2990, 560, 300, 60, "hanging"],
	# East shore over the low tunnel and the sunken cave.
	["EastShore", 3800, 1180, 350, 540, "checkpoint"],
	["EastShoreOverCave", 4150, 1180, 730, 240, "checkpoint"],
	["TunnelFloor", 3800, 1890, 350, 270, ""],
	["SunkenFloor", 4150, 1890, 970, 270, "checkpoint"],
	# Shortcut shaft from the sunken cave back up to the east shore.
	["ShaftLedge1", 5010, 1760, 110, 40, ""],
	["ShaftLedge2", 4880, 1630, 90, 40, ""],
	["ShaftLedge3", 5010, 1500, 110, 40, ""],
	["ShaftLedge4", 4880, 1380, 90, 40, ""],
	["ShaftLedge5", 5010, 1270, 110, 40, ""],
	# Upper gallery towards the vine exit.
	["UpperGallery", 3760, 560, 1360, 100, "checkpoint"],
]

## name, x (left end), resting walk-line y (floor - 34: the log body is 34 px
## thick), tether height, show tether
const LOGS := [
	["LogWest", 1650, 1846, 1200, false],
	["LogPoolWest", 2050, 1901, 901, true],
	["LogMiddle", 2560, 1856, 1200, false],
	["LogPoolEast", 3030, 1901, 901, true],
	["LogEast", 3480, 1856, 1200, false],
]

## name, x, y, lower level, upper level
const WINCHES := [
	["WinchWestShore", 1500, 1180, 0, 1],
	["WinchBasinFloor", 1600, 1880, 0, 1],
	["WinchEastShore", 3900, 1180, 1, 2],
	["WinchUpperGallery", 3900, 560, 1, 2],
]


func _init() -> void:
	var room := Node2D.new()
	room.name = "Chapter1RootRoom"
	room.set_script(ROOM_SCRIPT)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	_add(room, room, camera)

	_build_backdrop(room)

	var water := Node2D.new()
	water.name = "Water"
	water.set_script(WATER_SCRIPT)
	water.set("regions", [Rect2(760, 0, 3040, 1960), Rect2(3800, 0, 1320, 1960)] as Array[Rect2])
	water.set("level_heights", PackedFloat32Array([1910.0, 1240.0, 700.0]))
	_add(room, room, water)

	var cave := Node2D.new()
	cave.name = "Cave"
	cave.set_script(SHELL_SCRIPT)
	cave.set("water_path", NodePath("../Water"))
	_add(room, room, cave)
	for data in BLOCKS:
		var block := Node2D.new()
		block.name = data[0]
		block.set_script(BLOCK_SCRIPT)
		block.position = Vector2(data[1], data[2])
		block.set("size", Vector2(data[3], data[4]))
		block.set("checkpoint", "checkpoint" in data[5])
		block.set("hanging", "hanging" in data[5])
		_add(room, cave, block)

	var logs := _group(room, "Logs")
	for data in LOGS:
		var float_log := Node2D.new()
		float_log.name = data[0]
		float_log.set_script(LOG_SCRIPT)
		float_log.position = Vector2(data[1], data[2])
		float_log.set("water_path", NodePath("../../Water"))
		float_log.set("tether_height", float(data[3]))
		float_log.set("show_tether", data[4])
		_add(room, logs, float_log)

	var winches := _group(room, "Winches")
	for data in WINCHES:
		var winch := Node2D.new()
		winch.name = data[0]
		winch.set_script(WINCH_SCRIPT)
		winch.position = Vector2(data[1], data[2])
		winch.set("water_path", NodePath("../../Water"))
		winch.set("lower_level", data[3])
		winch.set("upper_level", data[4])
		_add(room, winches, winch)

	var mechanisms := _group(room, "Mechanisms")
	var outer := _fungus(room, mechanisms, "TunnelFungusOuter", Vector2(3870, 1890))
	var inner := _fungus(room, mechanisms, "TunnelFungusInner", Vector2(4230, 1890))
	var tunnel_gate := GATE_SCENE.instantiate()
	tunnel_gate.name = "TunnelRootWall"
	tunnel_gate.position = Vector2(3960, 1720)
	_add(room, mechanisms, tunnel_gate)
	tunnel_gate.set("size", Vector2(100, 170))
	tunnel_gate.set("fungus_path", NodePath("../" + outer.name))
	tunnel_gate.set("second_fungus_path", NodePath("../" + inner.name))

	var lamps := _group(room, "VeinLamps")
	for data in [["LampLow", Vector2(3380, 1890)], ["LampMiddle", Vector2(2390, 1190)], ["LampHigh", Vector2(2250, 540)]]:
		var lamp := _fungus(room, lamps, data[0], data[1])
		lamp.set("latch", true)

	var steles := _group(room, "Steles")
	_stele(room, steles, "PuzzleStele", Vector2(1250, 1180), 0, &"root_puzzle_water_veins", false, "根区 · 水脉碑")
	_stele(room, steles, "CombatStele", Vector2(4520, 1890), 1, &"root_combat_sunken_roots", true, "根区 · 沉根碑")

	var portals := _group(room, "Portals")
	for data in [["MistGate", Vector2(150, 640)], ["VineGate", Vector2(4960, 560)], ["HeartGate", Vector2(300, 380)]]:
		var marker := Marker2D.new()
		marker.name = data[0]
		marker.position = data[1]
		_add(room, portals, marker)

	_build_foreground(room)

	var packed := PackedScene.new()
	var error := packed.pack(room)
	if error == OK:
		error = ResourceSaver.save(packed, OUT)
	print("Root water cavern saved: %s" % error_string(error))
	room.free()
	quit(0 if error == OK else 1)


func _add(room: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = room


func _group(room: Node, group_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = group_name
	_add(room, room, node)
	return node


func _fungus(room: Node, parent: Node, fungus_name: String, at: Vector2) -> Node2D:
	var fungus := FUNGUS_SCENE.instantiate() as Node2D
	fungus.name = fungus_name
	fungus.position = at
	_add(room, parent, fungus)
	return fungus


func _stele(room: Node, parent: Node, stele_name: String, at: Vector2, kind: int, id: StringName,
		challenge: bool, travel: String) -> void:
	var stele := Node2D.new()
	stele.name = stele_name
	stele.set_script(STELE_SCRIPT)
	stele.position = at
	stele.set("stele_kind", kind)
	stele.set("stele_id", id)
	stele.set("challenge_available", challenge)
	stele.set("region_title", "根区")
	stele.set("travel_title", travel)
	stele.set("region_stele_ids", [&"root_puzzle_water_veins", &"root_combat_sunken_roots"] as Array[StringName])
	_add(room, parent, stele)


func _build_backdrop(room: Node) -> void:
	var backdrop := _group(room, "Backdrop")
	var far_layer := CanvasLayer.new()
	far_layer.name = "FarCavern"
	far_layer.layer = -100
	_add(room, backdrop, far_layer)
	var far := TextureRect.new()
	far.name = "FarArt"
	far.texture = FAR_ART
	far.set_anchors_preset(Control.PRESET_FULL_RECT)
	far.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	far.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	far.mouse_filter = Control.MOUSE_FILTER_IGNORE
	far.modulate = Color(0.72, 0.8, 0.8)
	_add(room, far_layer, far)
	# Giant root arches between the far layer and the rock; they drift slowly.
	for data in [
		["MidArchBasin", Vector2(1450, 180), 1.35, Color(0.46, 0.58, 0.56, 0.85), 0.18],
		["MidArchDeep", Vector2(2200, 1150), 0.95, Color(0.3, 0.42, 0.42, 0.8), 0.25],
		["MidArchEast", Vector2(3850, 640), 0.7, Color(0.42, 0.54, 0.52, 0.8), 0.15],
	]:
		var sprite := Sprite2D.new()
		sprite.name = data[0]
		sprite.texture = MID_ART
		sprite.centered = false
		sprite.position = data[1]
		sprite.scale = Vector2.ONE * data[2]
		sprite.modulate = data[3]
		sprite.z_index = -20
		sprite.set_meta(&"parallax", data[4])
		sprite.add_to_group(&"root_parallax", true)
		_add(room, backdrop, sprite)


func _build_foreground(room: Node) -> void:
	var front := _group(room, "Foreground")
	for data in [
		["EdgeRootsWest", Vector2(60, 1950), 0.45, false],
		["EdgeRootsBasin", Vector2(2600, 2010), 0.45, true],
		["EdgeRootsCeiling", Vector2(3900, 330), 0.4, false],
	]:
		var sprite := Sprite2D.new()
		sprite.name = data[0]
		sprite.texture = FRONT_ART
		sprite.centered = false
		sprite.position = data[1]
		sprite.scale = Vector2.ONE * data[2]
		sprite.flip_h = data[3]
		# The ceiling piece hangs upside down from the rock above the gallery.
		sprite.flip_v = data[0] == "EdgeRootsCeiling"
		if sprite.flip_v:
			sprite.position.y -= FRONT_ART.get_height() * data[2]
		sprite.z_index = SideviewLayers.FOREGROUND
		sprite.modulate = Color(0.55, 0.62, 0.58, 0.9)
		_add(room, front, sprite)
