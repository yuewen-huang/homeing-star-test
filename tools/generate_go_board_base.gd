extends SceneTree
## Procedural rice-paper base for the panda go board (no grid: lines and stones are drawn in code).
## Tint is sampled from the Mirror Lake paper layer so the board sits in the same ink style.
## Usage: godot --headless --path <game> --script <this>
## Output: res://assets/bosses/panda/board/go_board_base.png (640x640, deckled alpha edge).

const SIZE := 640
const SOURCE := "res://assets/levels/mirror_lake/environment/01_paper.png"
const OUTPUT := "res://assets/bosses/panda/board/go_board_base.png"

func _initialize() -> void:
	var tint := Color(0.93, 0.89, 0.79)
	var src := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if src != null and not src.is_empty():
		var acc := Vector3.ZERO
		var n := 0
		for y in range(0, src.get_height(), 37):
			for x in range(0, src.get_width(), 37):
				var c := src.get_pixel(x, y)
				acc += Vector3(c.r, c.g, c.b)
				n += 1
		acc /= float(n)
		tint = Color(acc.x, acc.y, acc.z).lerp(Color(0.95, 0.91, 0.82), 0.45)
	var fine := FastNoiseLite.new()
	fine.seed = 17
	fine.frequency = 0.09
	var cloud := FastNoiseLite.new()
	cloud.seed = 5
	cloud.frequency = 0.006
	cloud.fractal_octaves = 4
	var fibre := FastNoiseLite.new()
	fibre.seed = 23
	fibre.frequency = 0.035
	var edge := FastNoiseLite.new()
	edge.seed = 41
	edge.frequency = 0.05
	var ink := Color(0.10, 0.09, 0.09)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var c := tint
			c = c.darkened(0.05 * (cloud.get_noise_2d(x, y) * 0.5 + 0.5))
			c = c.lightened(0.035 * fine.get_noise_2d(x, y))
			# long horizontal fibres of hand-made paper
			var f := fibre.get_noise_2d(x * 0.12, y * 2.6)
			if f > 0.55: c = c.darkened((f - 0.55) * 0.18)
			# ink wash pooling toward the border
			var d := maxf(absf(x - half), absf(y - half)) / half
			var wash := smoothstep(0.72, 1.0, d) * (0.10 + 0.06 * cloud.get_noise_2d(x + 300, y))
			c = c.lerp(ink, clampf(wash, 0.0, 1.0))
			# deckled edge: alpha bites with noise
			var bite := 1.0 - (half - maxf(absf(x - half), absf(y - half))) / 14.0
			var a := 1.0 - clampf(bite + edge.get_noise_2d(x, y) * 0.6, 0.0, 1.0)
			c.a = a
			img.set_pixel(x, y, c)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var err := img.save_png(ProjectSettings.globalize_path(OUTPUT))
	print("saved ", OUTPUT, " err=", err, " tint=", tint)
	quit(err)
