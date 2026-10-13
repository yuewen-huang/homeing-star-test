extends Node2D
## Isolated rendering experiment. Reuses RootCaveShell's textured triangle strip;
## existing tangent poses drive the curve without bones or frame redraws.

const BARK_SHADER = """
shader_type canvas_item;
uniform float ground_line = 555.0;
varying vec4 paint_tint;
varying vec2 world_point;
void vertex() {
    paint_tint = COLOR;
    world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
    // Reflected repeats make the two ends continuous even for a painted tile
    // whose first and last rows differ. Only UVs repeat, not the whole picture.
    float row = 1.0 - abs(1.0 - mod(UV.y, 2.0));
    if (world_point.y > ground_line + 2.0) { discard; }
    COLOR = paint_tint * texture(TEXTURE, vec2(UV.x, row));
}
"""
const ROOT_SHEET = preload("res://assets/sideview/characters/xiujiao_ranger/human/vfx/vine_ground_lash.png")
const STEPS := 96
var data: Dictionary
var bark: Texture2D
var root_art: AtlasTexture
var origin := Vector2.ZERO
var direction := 1.0
var reach := 1280.0
var thickness := 56.0
var age := -1.0
var show_geometry := false
var paths: Array[PackedVector2Array] = []
var _meshes: Array[ArrayMesh] = []
var _gain := 1.0
var _frame_starts := PackedFloat32Array()

func setup(asset_dir: String, root_position: Vector2, facing: float, sweep: float, width := 56.0) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(asset_dir.path_join("motion.json")))
	bark = ImageTexture.create_from_image(Image.load_from_file(asset_dir.path_join("vine_bark_tile.png")))
	origin = root_position
	direction = facing
	reach = sweep
	thickness = width
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var shader := Shader.new()
	shader.code = BARK_SHADER
	var painted := ShaderMaterial.new()
	painted.shader = shader
	painted.set_shader_parameter("ground_line", origin.y)
	# Keep the soil outside the bark shader.
	var skin := Node2D.new()
	skin.name = "RepeatedBark"
	skin.material = painted
	skin.show_behind_parent = true
	skin.draw.connect(_draw_skin.bind(skin))
	add_child(skin)
	root_art = AtlasTexture.new()
	root_art.atlas = ROOT_SHEET
	root_art.region = Rect2(0, 0, 224, 224)
	var elapsed := 0.0
	for duration in data.duration_ms:
		_frame_starts.append(elapsed)
		elapsed += float(duration) / 1000.0
	_frame_starts.append(elapsed)
	# Length comes from the authored curve. Width is a separate new design
	# parameter; the material is repeated along the length at a fixed density.
	var widest := 0.0
	for frame in range(11, 21):
		for p in _native_path(float(frame), false): widest = maxf(widest, p.x)
	_gain = (reach - thickness * 0.5) / widest

func total_time() -> float:
	return _frame_starts[-1]

func sample(seconds: float) -> void:
	age = seconds
	paths.clear()
	if seconds >= 0.0 and seconds < total_time():
		var pose := pose_at(seconds)
		for secondary in [true, false]:
			var native := _native_path(pose, secondary)
			if native[-1].length() < 0.01: continue
			var path := PackedVector2Array()
			for p in native:
				var point := origin + Vector2(p.x * direction, p.y) * _gain
				var u := float(path.size()) / STEPS
				var skin_radius := thickness * (0.76 if secondary else 1.0) * (0.02 + 0.98 * pow(1.0-u,0.65)) * 0.5
				# The old small-canvas sweep lets the middle pass underground.
				# Keep the new continuous skin resting on the floor instead of
				# clipping it into disconnected visible pieces.
				if path.size() > 0: point.y = minf(point.y, origin.y - skin_radius)
				path.append(point)
			_round_root(path, thickness * (0.76 if secondary else 1.0))
			paths.append(path)
	get_node("RepeatedBark").queue_redraw()
	queue_redraw()

## A planted root begins underground and rises with a vertical tangent before
## joining the moving stem. A cubic joins both positions and tangents, rather
## than using the first floor-clamped segment as an angular elbow.
func _round_root(path: PackedVector2Array, width: float) -> void:
	var distance := 0.0
	var join := 0
	var collar := width * 2.8
	for i in range(1, path.size()):
		distance += path[i - 1].distance_to(path[i])
		join = i
		if distance >= collar: break
	if join < 3: return
	var start := origin + Vector2(0, width * 0.6)
	var end := path[join]
	var tangent := (path[mini(join + 1, path.size() - 1)] - path[join - 1]).normalized()
	var handle := minf(distance * 0.42, start.distance_to(end) * 0.65)
	var control_a := start + Vector2.UP * handle
	var control_b := end - tangent * handle
	for i in range(join + 1):
		var t := float(i) / join
		var inverse := 1.0 - t
		path[i] = inverse*inverse*inverse*start + 3*inverse*inverse*t*control_a + 3*inverse*t*t*control_b + t*t*t*end

func pose_at(seconds: float) -> float:
	for i in data.duration_ms.size():
		if seconds < _frame_starts[i + 1]:
			return float(i) + clampf((seconds - _frame_starts[i]) / (_frame_starts[i + 1] - _frame_starts[i]), 0, 1)
	return float(data.duration_ms.size() - 1)

func _hermite(values: Array, fraction: float) -> float:
	var t := clampf(fraction, 0, 1) * (values.size() - 1)
	var index := mini(values.size() - 2, int(t))
	t -= index
	var a := float(values[maxi(0, index - 1)])
	var b := float(values[index])
	var c := float(values[index + 1])
	var d := float(values[mini(values.size() - 1, index + 2)])
	return 0.5 * ((2*b) + (-a+c)*t + (2*a-5*b+4*c-d)*t*t + (-a+3*b-3*c+d)*t*t*t)

func _native_path(pose: float, secondary: bool) -> PackedVector2Array:
	var length_pose := pose
	if secondary and pose >= 11.0 and pose < 24.0: pose = maxf(10, pose - 2.0)
	var frame := clampi(int(pose), 0, data.poses.size() - 1)
	var next := mini(frame + 1, data.poses.size() - 1)
	var blend := pose - frame
	var angles := []
	for k in 6:
		var angle := lerpf(float(data.poses[frame][k]), float(data.poses[next][k]), blend)
		if secondary: angle += 5.0 * sin(k * 1.7)
		angles.append(angle)
	var length_frame := clampi(int(length_pose), 0, data.lengths.size() - 1)
	var length_ := lerpf(float(data.lengths[length_frame]), float(data.lengths[mini(length_frame + 1, data.lengths.size() - 1)]), length_pose - length_frame)
	if secondary: length_ *= 0.91
	var path := PackedVector2Array([Vector2.ZERO])
	for i in STEPS:
		var angle := deg_to_rad(_hermite(angles, (float(i) + 0.5) / STEPS))
		path.append(path[-1] + Vector2(sin(angle), -cos(angle)) * length_ / STEPS)
	# Authored landing clamp, with the small skin thickness staying above soil.
	if (not secondary and length_pose >= 16 and length_pose < 19) or (secondary and length_pose >= 18 and length_pose < 21):
		for i in path.size(): path[i].y = minf(-2, path[i].y) if i > 0 else 0.0
	return path

func _draw_skin(canvas: Node2D) -> void:
	_meshes.clear()
	for strand in paths.size():
		var path := paths[strand]
		if path[0].distance_to(path[-1]) < 0.5: continue
		var width := thickness * (0.76 if strand == 0 else 1.0)
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var distances := PackedFloat32Array()
		var length_ := 0.0
		var tile_length := float(bark.get_height()) * thickness / bark.get_width()
		for i in path.size():
			if i > 0: length_ += path[i - 1].distance_to(path[i])
			distances.append(length_)
			var tangent := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
			var normal := Vector2(-tangent.y, tangent.x)
			var u := float(i) / STEPS
			var radius := width * (0.02 + 0.98 * pow(1.0 - u, 0.65)) * 0.5
			for edge in [-1.0, 1.0]:
				var p: Vector2 = path[i] + normal * radius * float(edge)
				vertices.append(Vector3(p.x, p.y, 0))
				uvs.append(Vector2((edge + 1) * 0.5, length_ / tile_length + (0.7 if strand == 0 else 0.0)))
				colors.append(Color(0.82,0.89,0.74) if strand == 0 else Color.WHITE)
		for i in path.size() - 1:
			var base := i * 2
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
		_add_bristles(path, distances, width, tile_length, strand, vertices, uvs, colors, indices)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes.append(mesh)
		canvas.draw_mesh(mesh, bark)

## Small hooked bark splinters use the same material and attach at fixed
## distances along the stem, so they travel with its bend instead of flickering.
func _add_bristles(path: PackedVector2Array, distances: PackedFloat32Array, width: float,
		tile_length: float, strand: int, vertices: PackedVector3Array, uvs: PackedVector2Array,
		colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var length_ := distances[-1]
	for side in [-1.0, 1.0]:
		var facing: float = side
		for slot in 24:
			var seed_ := float(slot * 17 + strand * 31) + facing * 7.0
			var jitter := sin(seed_ * 2.13)
			var at := width * 2.7 + slot * 72.0 + facing * 24.0 + jitter * 13.0
			if at > length_ - 18.0: break
			var index := 1
			while index < distances.size() - 1 and distances[index] < at: index += 1
			var blend := (at - distances[index - 1]) / maxf(0.001, distances[index] - distances[index - 1])
			var center := path[index - 1].lerp(path[index], blend)
			var tangent := (path[mini(index + 1,path.size() - 1)] - path[maxi(index - 2,0)]).normalized()
			var normal := Vector2(-tangent.y,tangent.x) * facing
			var u := (float(index - 1) + blend) / STEPS
			var radius := width * (0.02 + 0.98 * pow(1.0-u,0.65)) * 0.5
			var anchor := center + normal * radius * 0.94
			var size := width * (0.15 + 0.12 * (jitter + 1.0) * 0.5) * pow(1.0-u,0.35)
			size *= smoothstep(18.0,45.0,length_ - at)
			var half_base := maxf(1.2,size * 0.23)
			var points := PackedVector2Array([
				anchor + tangent * half_base,
				anchor + normal * size * 0.44 + tangent * size * 0.03,
				anchor + normal * size - tangent * size * 0.38,
				anchor + normal * size * 0.48 - tangent * size * 0.37,
				anchor - tangent * half_base
			])
			var base := vertices.size()
			for i in points.size():
				vertices.append(Vector3(points[i].x,points[i].y,0))
				uvs.append(Vector2(0.28 + float(i) * 0.1, at / tile_length + (0.7 if strand == 0 else 0.0)))
				colors.append(Color(0.82,0.89,0.74) if strand == 0 else Color.WHITE)
			indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3,base,base+3,base+4]))

func _draw() -> void:
	if age < 0 or age >= total_time(): return
	# Native F00 contains soil only; it stays a small root detail.
	draw_set_transform(origin, 0, Vector2(1.4 * direction, 1.4))
	draw_texture_rect(root_art, Rect2(Vector2(-48,-196), Vector2(224,224)), false)
	draw_set_transform(Vector2.ZERO)
	if show_geometry:
		for path in paths: draw_polyline(path, Color(0.9,0.8,0.3,0.8), 1.5, true)
