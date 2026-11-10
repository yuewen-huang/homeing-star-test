extends Node2D
## Screenshot-only reference overlay; never attached to the production map.
const SOURCE := "res://../homeing-star-doc/docs/design/sunken_cavern/regions_a1_a27.json"
const OUTLINE := "res://../homeing-star-doc/docs/design/sunken_cavern/outline.json"
const OFFSET := Vector2(40,160)
const ECHO_COLOR := Color("a9ffee")
var picture: Texture2D
var bounds: Rect2
var zoom: float
var regions: Array
var spaces: Dictionary = {}
var echoes: Dictionary
var font := SystemFont.new()


func setup(image: Image,map_bounds: Rect2,map_zoom: float,echo_points: Dictionary) -> void:
	picture = ImageTexture.create_from_image(image)
	bounds = map_bounds
	zoom = map_zoom
	echoes = echo_points
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	regions = JSON.parse_string(FileAccess.get_file_as_string(SOURCE)).regions
	for space in JSON.parse_string(FileAccess.get_file_as_string(OUTLINE)).spaces:
		spaces[space.id] = space


func point(world: Vector2) -> Vector2:
	return OFFSET + picture.get_size()*0.5 + (world-bounds.get_center())*zoom


func tint(group: String) -> Color:
	return {"west":Color("f4c782"),"central":Color("81d6e9"),"east":Color("a9deb1"),"deep":Color("c7b3f5")}[group]


func badge(at: Vector2,id: String,color: Color) -> void:
	var box := Rect2(at-Vector2(40,25),Vector2(80,50))
	draw_rect(box,Color("101d26"))
	draw_rect(box,color,false,2.5)
	var size := font.get_string_size(id,HORIZONTAL_ALIGNMENT_LEFT,-1,30)
	draw_string(font,at+Vector2(-size.x*0.5,10),id,HORIZONTAL_ALIGNMENT_LEFT,-1,30,color)


func _draw() -> void:
	draw_rect(Rect2(0,0,4800,2560),Color("0b141c"))
	draw_texture(picture,OFFSET)
	draw_string(font,Vector2(70,79),"沉没古城 · 区域参照图",HORIZONTAL_ALIGNMENT_LEFT,-1,48,Color("edf4f5"))
	draw_string(font,Vector2(72,126),"当前实机布局  /  A1–A27 固定编号  /  机关初始状态",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("a3b7c3"))
	for region in regions:
		var color := tint(region.group)
		var cells: Dictionary = {}
		for space_id in region.spaces:
			for r in spaces[space_id].rects:
				for x in range(int(r[0]),int(r[0]+r[2])):
					for y in range(int(r[1]),int(r[1]+r[3])):
						cells[Vector2i(x,y)] = true
		for cell in cells:
			var corners := [Vector2(cell)*64,Vector2(cell+Vector2i(1,0))*64,Vector2(cell+Vector2i(1,1))*64,Vector2(cell+Vector2i(0,1))*64]
			var neighbors := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
			for side in 4:
				if not cells.has(cell+neighbors[side]):
					draw_line(point(corners[side]),point(corners[(side+1)%4]),Color(color,0.52),2,true)
	for index in regions.size():
		var region: Dictionary = regions[index]
		var color := tint(region.group)
		badge(point(Vector2(region.anchor[0],region.anchor[1])),region.id,color)
		var row_y := 235+index*77
		badge(Vector2(4020,row_y-10),region.id,color)
		draw_string(font,Vector2(4082,row_y),region.name,HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("e0eaed"))
	for echo: Array in echoes.values():
		_echo_mark(point(Vector2(echo[0],echo[1])))
	draw_line(Vector2(3940,180),Vector2(3940,2350),Color("344956"),2)
	draw_string(font,Vector2(3978,166),"区域编号 / 后续设计沟通用",HORIZONTAL_ALIGNMENT_LEFT,-1,29,Color("a3b7c3"))
	draw_string(font,Vector2(3978,2390),"W1、W2 保留原水路名称",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("a3b7c3"))
	_echo_mark(Vector2(3991,2444))
	draw_string(font,Vector2(4020,2454),"余音位置",HORIZONTAL_ALIGNMENT_LEFT,-1,25,ECHO_COLOR)
	draw_string(font,Vector2(70,2517),"细线沿现有空间轮廓标示范围；编号仅用于此参照图。深层远景使用总览专用投影。",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("a3b7c3"))


func _echo_mark(at: Vector2) -> void:
	draw_circle(at, 15, Color("0b141c"), true, -1.0, true)
	draw_circle(at, 11, ECHO_COLOR, false, 3, true)
	draw_circle(at, 4, ECHO_COLOR, true, -1.0, true)
