extends Node2D

const LAN := preload("res://scenes/player/lan/lan_player.tscn")
const ENEMIES: Array[PackedScene] = [
	preload("res://scenes/enemies/clockwork_ox/clockwork_ox.tscn"),
	preload("res://scenes/enemies/clockwork_bird/clockwork_bird.tscn"),
	preload("res://scenes/enemies/clockwork_snake/clockwork_snake.tscn"),
]
const BACKDROP := preload("res://assets/levels/chapter_2_underwater/cavern/environment/deep_cavern/deep_cavern_pool_1536x1024.png")
const STONE := preload("res://assets/levels/chapter_2_underwater/city/environment/terrain/stone_masonry_1254x1254.png")

var player: LanPlayer
var enemy: ClockworkEnemy


func build(index: int) -> void:
	var backdrop := Sprite2D.new()
	backdrop.texture = BACKDROP
	backdrop.position = Vector2(640.0, 348.0)
	backdrop.modulate = Color(0.65, 0.69, 0.76)
	backdrop.z_index = -5
	add_child(backdrop)
	var camera := Camera2D.new()
	camera.position = Vector2(640.0, 360.0)
	add_child(camera)

	var floor := Rect2(72, 584, 1136, 140)
	if index == 0:
		floor = Rect2(170, 584, 890, 140)
	var rocks: Array[Rect2] = [floor, Rect2(38, 220, 132, 364), Rect2(1110, 220, 132, 364)]
	if index == 2:
		rocks.append_array([Rect2(272, 174, 192, 410), Rect2(668, 122, 288, 462),
			Rect2(618, 485, 50, 22), Rect2(464, 324, 44, 21)])
	for area in rocks:
		_add_rock(area)

	player = LAN.instantiate() as LanPlayer
	player.world_min_x = floor.position.x + 12.0
	player.world_max_x = floor.end.x - 12.0
	player.fallback_ground_y = 900.0
	player.z_index = 12
	add_child(player)
	for area in rocks:
		player.register_ground_surface(Rect2(area.position, Vector2(area.size.x, 1.0)))
	var spawn := Vector2(423, 584) if index < 2 else Vector2(566, 584)
	player.reset_after_map_fall(spawn)

	enemy = ENEMIES[index].instantiate() as ClockworkEnemy
	enemy.position = [Vector2(654, 584), Vector2(654, 414), Vector2(464, 474)][index]
	add_child(enemy)


func _add_rock(area: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = area.get_center()
	var shape := RectangleShape2D.new()
	shape.size = area.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	var texture := Sprite2D.new()
	texture.texture = STONE
	texture.region_enabled = true
	texture.region_rect = Rect2(Vector2(180.0, 220.0), area.size)
	texture.modulate = Color(0.51, 0.60, 0.62)
	body.add_child(texture)
	add_child(body)
