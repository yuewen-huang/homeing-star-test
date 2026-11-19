extends SunkenCavern

class WideArt extends CavernEntranceArt:
	const ENVIRONMENT := "res://assets/levels/chapter_2_underwater/cavern/environment/"

	func setup_wide(bell: Vector2) -> void:
		name = "WideCavernArt"
		add_landmark(GATE, Vector2(460, 4700), 700.0)
		add_landmark(preload(ENVIRONMENT + "trade_street/eroded_trading_gallery_2172x724.png"), Vector2(2190, 4700), 1610.0)
		add_landmark(preload(ENVIRONMENT + "pool_branch/eroded_drain_alcove_1536x1024.png"), Vector2(400, 5590), 310.0)
		add_landmark(preload(ENVIRONMENT + "archive/eroded_archive_wall_1774x887.png"), Vector2(5100, 4380), 780.0)
		add_landmark(preload(ENVIRONMENT + "west_crypt/eroded_crypt_gallery_2172x724.png"), Vector2(3910, 5460), 1120.0)
		add_landmark(preload(ENVIRONMENT + "east_street/eroded_east_gallery_1536x1024.png"), Vector2(5950, 4350), 580.0)
		bell_tower = BELL_TOWER.new()
		bell_tower.position = bell - Vector2(2240, 670)
		add_child(bell_tower)

	func add_landmark(texture: Texture2D, foot: Vector2, width: float) -> void:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * (width / texture.get_width())
		sprite.position = foot - Vector2(width * 0.5, texture.get_height() * sprite.scale.y)
		sprite.modulate = Color(0.67, 0.73, 0.75, 0.8)
		add_child(sprite)

	func drip_origin(point: Vector2, _kind: String) -> Vector2:
		return point + Vector2(0, 1.2)

	func _process(_delta: float) -> void:
		pass


const RockLayout := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_rock_layout.gd")
var source: Dictionary

func _load_layout() -> Dictionary:
	var area := rect(source.bounds)
	var remaining: Array[Rect2] = [area]
	for space: Dictionary in source.spaces:
		for values: Array in space.rects:
			var cut := rect(values)
			var next: Array[Rect2] = []
			for rock in remaining:
				carve(rock, cut, next)
			remaining = next
	var walls: Array = []
	for rock in remaining:
		walls.append([rock.position.x, rock.position.y, rock.size.x, rock.size.y])
	walls.append_array(source.rock_insets)
	var geometry := RockLayout.rebuild(walls, area)
	source.walls = walls
	source.floors = geometry.floors
	source.visual_contours = geometry.contours
	source.terrain_air = geometry.air
	return source

func _make_entrance_art() -> CavernEntranceArt:
	var art := WideArt.new()
	art.setup_wide(vector(layout.mechanisms.bell))
	return art

func carve(rock: Rect2, opening: Rect2, remaining: Array[Rect2]) -> void:
	var cut := rock.intersection(opening)
	if not cut.has_area():
		remaining.append(rock)
		return
	var parts := [
		Rect2(rock.position, Vector2(rock.size.x, cut.position.y - rock.position.y)),
		Rect2(rock.position.x, cut.end.y, rock.size.x, rock.end.y - cut.end.y),
		Rect2(rock.position.x, cut.position.y, cut.position.x - rock.position.x, cut.size.y),
		Rect2(cut.end.x, cut.position.y, rock.end.x - cut.end.x, cut.size.y),
	]
	for part: Rect2 in parts:
		if part.has_area():
			remaining.append(part)

