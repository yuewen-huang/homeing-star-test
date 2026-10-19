extends SceneTree
## Cuts the deer's human-form sheets (4×4 grids of 256 px cells) into named
## START / ING / END strips and writes the human action library.
## Run twice from the game project root (the second pass needs the imported PNGs):
##   <Godot> --headless --path ../homeing-star-game --script <本文件的绝对路径> -- <sheet dir>
##   <Godot> --headless --path . --import
##   <Godot> --headless --path ../homeing-star-game --script <本文件的绝对路径> -- --manifest
## Segment boundaries: ../homeing-star-doc/docs/design/chapter_1_deer_vine_phase_design.md, section 7.

const OUT := "res://assets/bosses/deer/body/human/"
const CELL := 256
## All sheets share one layout, so one foot pivot keeps the figure still across clips.
## x matches the deer's body centre in 变身 F00, so the transform starts where the deer stood.
const PIVOT := [66, 256]
## sheet file → {family: {segment: [first, last]}} in sheet frame order.
const SHEETS := {
	"变身.png": {"human_transform": {"START": [0, 3], "ING": [4, 11], "END": [12, 15]}},
	"待机.png": {"human_idle": {"ING": [0, 15]}},
	"轻施法.png": {"human_cast": {"START": [0, 5], "ING": [6, 7], "END": [8, 15]}},
	"重施法.png": {"human_channel": {"START": [0, 3], "ING": [4, 14], "END": [15, 15]}},
	"坠落并起飞.png": {"human_fall": {"START": [0, 6], "ING": [7, 10], "END": [11, 15]}},
}
const LOOPING := ["human_idle_ING", "human_fall_ING"]
## Sheets whose last frame flows back into the first; stabilizing treats them as a cycle.
const CYCLIC_SHEETS := ["待机.png"]
const HOLE_MAX_AREA := 256  # enclosed transparent regions up to this many pixels are cut-out holes
## Optional: also replace one-frame colour spikes. Off by default; the flicker came from
## the cut-out holes, and filling them keeps the painted colours untouched.
const REMOVE_SPIKES := false
## Spike removal (RGB distance is the sum of channel differences, 0–765). The sheets
## are painted per frame, so a few pixels pop for exactly one frame. Only those are
## fixed: holding colours across frames desynchronizes neighbouring pixels and
## makes the shimmer worse (tried and reverted).
const SPIKE_DISTANCE := 40  # a one-frame change at least this far from both neighbours is a spike
const SPIKE_SAME := 24      # ...when the neighbouring frames agree within this distance
const SPIKE_MAX_CLUSTER := 4  # spikes in a 3×3 block up to this count are noise, larger ones real motion

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(not args.is_empty(), "Pass the sheet directory, or --manifest")
	if args[0] == "--manifest": _write_manifest()
	else: _cut(args[0])
	quit()

func _cut(sheet_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var clips := {}
	var families := {}
	for file: String in SHEETS:
		var sheet := Image.load_from_file(sheet_dir.path_join(file))
		assert(sheet != null and sheet.get_width() == CELL * 4 and sheet.get_height() == CELL * 4, "Expected a 4×4 sheet: " + file)
		sheet.convert(Image.FORMAT_RGBA8)
		_fill_holes(sheet)
		if REMOVE_SPIKES: _stabilize(sheet, file in CYCLIC_SHEETS)
		for family: String in SHEETS[file]:
			families[family] = {}
			for segment: String in SHEETS[file][family]:
				var span: Array = SHEETS[file][family][segment]
				var id := "%s_%s" % [family, segment]
				var count: int = span[1] - span[0] + 1
				var strip := Image.create(CELL * count, CELL, false, Image.FORMAT_RGBA8)
				var core := []
				var staff := []
				for i in count:
					var index: int = span[0] + i
					var cell := Rect2i((index % 4) * CELL, (index / 4) * CELL, CELL, CELL)
					strip.blit_rect(sheet, cell, Vector2i(i * CELL, 0))
					var anchors := _anchors(sheet, cell)
					core.append(anchors[0])
					staff.append(anchors[1])
				strip.save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
				clips[id] = {"file": id + ".png", "count": count, "pivot": PIVOT, "fps": 12, "loop": id in LOOPING,
					"source": "%s F%02d–F%02d" % [file, span[0], span[1]], "anchors": {"core": core, "staff": staff}}
				families[family][segment] = id
				print("%-22s %2d frames  %s" % [id, count, clips[id].source])
	var json := JSON.stringify({"version": 1, "clips": clips, "families": families}, "  ")
	FileAccess.open(OUT + "library.json", FileAccess.WRITE).store_string(json)

## The background remover punched holes into the figure (alpha 0, colour cleared),
## different in every frame, so the backdrop flickers through. Transparent regions
## enclosed by the figure and no larger than HOLE_MAX_AREA are refilled from their
## rim inwards with the average of opaque neighbours. Gaps open to the outside stay.
func _fill_holes(sheet: Image) -> void:
	var filled := 0
	for index in 16:
		var cell := Rect2i((index % 4) * CELL, (index / 4) * CELL, CELL, CELL)
		var data := sheet.get_region(cell).get_data()
		var seen := PackedByteArray()
		seen.resize(CELL * CELL)
		var holes := PackedInt32Array()
		for start in CELL * CELL:
			if seen[start] == 1 or data[start * 4 + 3] >= 128: continue
			var stack := PackedInt32Array([start])
			var region := PackedInt32Array()
			var open := false
			seen[start] = 1
			while not stack.is_empty():
				var p := stack[stack.size() - 1]
				stack.remove_at(stack.size() - 1)
				region.append(p)
				var x := p % CELL
				var y := p / CELL
				if x == 0 or y == 0 or x == CELL - 1 or y == CELL - 1: open = true
				for q in [p - 1 if x > 0 else -1, p + 1 if x < CELL - 1 else -1, p - CELL, p + CELL]:
					if q < 0 or q >= CELL * CELL or seen[q] == 1 or data[q * 4 + 3] >= 128: continue
					seen[q] = 1
					stack.append(q)
			if not open and region.size() <= HOLE_MAX_AREA: holes.append_array(region)
		while not holes.is_empty():
			var rim := PackedInt32Array()
			var colours: Array[Color] = []
			var rest := PackedInt32Array()
			for p in holes:
				var x := p % CELL
				var y := p / CELL
				var sum := Vector3.ZERO
				var n := 0
				for dy in range(maxi(y - 1, 0), mini(y + 2, CELL)):
					for dx in range(maxi(x - 1, 0), mini(x + 2, CELL)):
						var o := (dy * CELL + dx) * 4
						if data[o + 3] >= 128: sum += Vector3(data[o], data[o + 1], data[o + 2]); n += 1
				if n > 0:
					rim.append(p)
					colours.append(Color8(roundi(sum.x / n), roundi(sum.y / n), roundi(sum.z / n)))
				else: rest.append(p)
			for i in rim.size():
				var o := rim[i] * 4
				data[o] = colours[i].r8; data[o + 1] = colours[i].g8; data[o + 2] = colours[i].b8; data[o + 3] = 255
			filled += rim.size()
			holes = rest
		sheet.blit_rect(Image.create_from_data(CELL, CELL, false, Image.FORMAT_RGBA8, data), Rect2i(0, 0, CELL, CELL), cell.position)
	print("filled %d hole pixels" % filled)

## Replaces one-frame spikes in sheet frame order: small clusters (pixels or edge
## pixels) that differ from both neighbouring frames while those two agree. Larger
## clusters are real motion and stay. A non-cyclic sheet keeps its first and last frame.
func _stabilize(sheet: Image, cyclic: bool) -> void:
	var src: Array[PackedByteArray] = []
	for index in 16:
		src.append(sheet.get_region(Rect2i((index % 4) * CELL, (index / 4) * CELL, CELL, CELL)).get_data())
	var spikes := 0
	for k in 16:
		if not cyclic and (k == 0 or k == 15): continue
		var frame := src[k].duplicate()
		var prev := src[(k + 15) % 16]
		var next := src[(k + 1) % 16]
		var mask := PackedByteArray()
		mask.resize(CELL * CELL)
		for p in CELL * CELL:
			var o := p * 4
			var ap := prev[o + 3] >= 128
			var ak := src[k][o + 3] >= 128
			var an := next[o + 3] >= 128
			if ap == an and ak != ap: mask[p] = 1
			elif ap and ak and an and _dist(prev, next, o) <= SPIKE_SAME \
					and _dist(src[k], prev, o) >= SPIKE_DISTANCE and _dist(src[k], next, o) >= SPIKE_DISTANCE:
				mask[p] = 1
		for p in CELL * CELL:
			if mask[p] == 0: continue
			var x := p % CELL
			var y := p / CELL
			var cluster := 0
			for dy in range(maxi(y - 1, 0), mini(y + 2, CELL)):
				for dx in range(maxi(x - 1, 0), mini(x + 2, CELL)):
					cluster += mask[dy * CELL + dx]
			if cluster <= SPIKE_MAX_CLUSTER:
				for c in 4: frame[p * 4 + c] = prev[p * 4 + c]
				spikes += 1
		var image := Image.create_from_data(CELL, CELL, false, Image.FORMAT_RGBA8, frame)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), Vector2i((k % 4) * CELL, (k / 4) * CELL))
	print("stabilized: %d one-frame spike pixels replaced" % spikes)

func _dist(a: PackedByteArray, b: PackedByteArray, o: int) -> int:
	return absi(a[o] - b[o]) + absi(a[o + 1] - b[o + 1]) + absi(a[o + 2] - b[o + 2])

## Bright green glow: the topmost glow is the staff gem (it sits highest whether
## the staff is upright or held overhead), the rest is the chest core. A frame
## with a single glow (the deer's chest while transforming) uses it for both.
func _anchors(sheet: Image, cell: Rect2i) -> Array:
	var glow: Array[Vector2] = []
	var top := CELL
	var right := 0
	var left := CELL
	for y in CELL:
		for x in CELL:
			var c := sheet.get_pixel(cell.position.x + x, cell.position.y + y)
			if c.a < 0.15: continue
			top = mini(top, y); right = maxi(right, x); left = mini(left, x)
			if c.g > 0.7 and c.g > c.r + 0.15 and c.g > c.b + 0.15: glow.append(Vector2(x, y))
	var core := Vector2((left + right) * 0.5, top + 80)
	var staff := Vector2(right - 8, top + 24)
	if glow.size() > 4:
		var highest := glow[0]
		for p in glow: if p.y < highest.y: highest = p
		var staff_sum := Vector2.ZERO
		var core_sum := Vector2.ZERO
		var staff_n := 0
		for p in glow:
			if p.distance_to(highest) <= 26.0: staff_sum += p; staff_n += 1
			else: core_sum += p
		staff = staff_sum / staff_n
		core = core_sum / (glow.size() - staff_n) if glow.size() - staff_n > 4 else staff
	return [[snappedf(core.x, 0.01), snappedf(core.y, 0.01)], [snappedf(staff.x, 0.01), snappedf(staff.y, 0.01)]]

func _write_manifest() -> void:
	var json := FileAccess.get_file_as_string(OUT + "library.json")
	var data: Dictionary = JSON.parse_string(json)
	var textures := {}
	for id: String in data.clips:
		textures[id] = load(OUT + data.clips[id].file)
		assert(textures[id] != null, "Import the PNGs before writing the manifest: " + id)
	var manifest := Resource.new()
	manifest.set_meta("library_json", json)
	manifest.set_meta("textures", textures)
	assert(ResourceSaver.save(manifest, OUT + "library.tres") == OK)
	print("human library: %d clips" % textures.size())
