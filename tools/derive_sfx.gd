extends SceneTree
## 从真实录音「种子」派生音效变体：变调、EQ、加厚、失真、混响、倒放、叠加。
## 在 homeing-star-test 目录运行：
##   <Godot> --headless --path ../homeing-star-game --script <本文件的绝对路径> -- [--preview <html 路径>]
## 种子与配方写在 RECIPES 里；输出 44.1kHz/16bit WAV 到 OUT_DIR，单声道种子输出单声道。
## 种子可以是 PCM WAV，也可以是游戏里已导入的 QOA 压缩 AudioStreamWAV（.res），工具自行解码。

const SR := 44100
const OUT_DIR := "res://assets/shared/audio/sfx/derived/"
const ACTIONS := "res://assets/shared/audio/actions/"
const SEEDS := {
	"swing": "res://assets/shared/audio/combat/parry_prepare.wav",
	"ring": "res://assets/shared/audio/combat/parry_success.wav",
	"call_far": ACTIONS + "deer_call_far.res",
	"call_near": ACTIONS + "deer_call_near.res",
	"gallop": ACTIONS + "deer_run.res",
	"warn": ACTIONS + "deer_charge_warning.res",
	"land": ACTIONS + "forest_land.res",
	"step_a": ACTIONS + "forest_run_01.res",
	"step_b": ACTIONS + "forest_run_02.res",
	"jump": ACTIONS + "player_jump.res",
	"djump": ACTIONS + "player_double_jump.res",
}
const SEED_LABELS := {
	"swing": "挥剑（parry_prepare）", "ring": "鸣响（parry_success）", "call_far": "鹿鸣·远", "call_near": "鹿鸣·近",
	"gallop": "鹿奔跑", "warn": "鹿冲刺预警", "land": "森林落地", "step_a": "森林奔跑 1", "step_b": "森林奔跑 2",
	"jump": "主角起跳", "djump": "主角二段跳",
}
const QOA_DEQUANT := [0.75, -0.75, 2.5, -2.5, 4.5, -4.5, 7.0, -7.0]
## Each op list runs in order. Keys:
##   pitch (semitones), hp / lp (Hz), low (bass boost amount), drive (saturation),
##   tail (keep this fraction of the length, fading its last 40%), reverse, reverb (wet mix),
##   fade_in (sec), gain_db, layer: {seed, at, gain_db, pitch, lp}
const RECIPES := [
	{"group": "挥剑", "name": "swing/swing_01", "label": "挥剑 -2", "seed": "swing", "ops": {"pitch": -2.0}},
	{"group": "挥剑", "name": "swing/swing_02", "label": "挥剑 -1", "seed": "swing", "ops": {"pitch": -1.0, "lp": 9000.0}},
	{"group": "挥剑", "name": "swing/swing_03", "label": "挥剑 +1", "seed": "swing", "ops": {"pitch": 1.0}},
	{"group": "挥剑", "name": "swing/swing_04", "label": "挥剑 +2", "seed": "swing", "ops": {"pitch": 2.0, "lp": 10000.0}},
	{"group": "挥剑", "name": "swing/swing_light_01", "label": "轻挥 1", "seed": "swing", "ops": {"pitch": 3.0, "hp": 300.0, "tail": 0.5}},
	{"group": "挥剑", "name": "swing/swing_light_02", "label": "轻挥 2", "seed": "swing", "ops": {"pitch": 4.5, "hp": 350.0, "tail": 0.45}},
	{"group": "挥剑", "name": "swing/swing_heavy_01", "label": "重挥 1", "seed": "swing", "ops": {"pitch": -4.0, "low": 0.8, "drive": 1.6}},
	{"group": "挥剑", "name": "swing/swing_heavy_02", "label": "重挥 2", "seed": "swing", "ops": {"pitch": -6.0, "low": 1.0, "drive": 1.8}},
	{"group": "挥剑", "name": "swing/swing_distant", "label": "远处挥剑", "seed": "swing", "ops": {"lp": 2200.0, "reverb": 0.4, "gain_db": -8.0}},
	{"group": "挥剑", "name": "swing/charge", "label": "蓄力（倒放）", "seed": "swing", "ops": {"reverse": true, "pitch": -2.0, "fade_in": 0.15}},
	{"group": "金属鸣响", "name": "ring/ring_01", "label": "鸣响 -2", "seed": "ring", "ops": {"pitch": -2.0}},
	{"group": "金属鸣响", "name": "ring/ring_02", "label": "鸣响 -1", "seed": "ring", "ops": {"pitch": -1.0}},
	{"group": "金属鸣响", "name": "ring/ring_03", "label": "鸣响 +1", "seed": "ring", "ops": {"pitch": 1.0}},
	{"group": "金属鸣响", "name": "ring/ring_04", "label": "鸣响 +2", "seed": "ring", "ops": {"pitch": 2.0}},
	{"group": "金属鸣响", "name": "ring/ring_short", "label": "短促碰撞", "seed": "ring", "ops": {"pitch": 1.0, "tail": 0.25}},
	{"group": "金属鸣响", "name": "ring/ring_big", "label": "沉重鸣响（红反）", "seed": "ring", "ops": {"pitch": -5.0, "low": 0.5, "reverb": 0.3}},
	{"group": "金属鸣响", "name": "ring/ring_dull", "label": "闷响（弹反失败）", "seed": "ring", "ops": {"lp": 1800.0, "tail": 0.2, "pitch": -1.0}},
	{"group": "金属鸣响", "name": "ring/ring_reverse", "label": "反向鸣响", "seed": "ring", "ops": {"reverse": true, "fade_in": 0.2}},
	{"group": "叠加", "name": "layer/slash_ring", "label": "挥剑 + 鸣响", "seed": "swing",
		"ops": {"layer": {"seed": "ring", "at": 0.08, "gain_db": -4.0, "pitch": 0.0}}},
	{"group": "叠加", "name": "layer/heavy_slash", "label": "重斩", "seed": "swing",
		"ops": {"pitch": -4.0, "low": 0.6, "layer": {"seed": "ring", "at": 0.09, "gain_db": -3.0, "pitch": -5.0}, "drive": 1.4}},
	# Manual action recordings (2026-10-11).
	{"group": "鹿鸣", "name": "deer/call_root", "label": "根阶段·厚重", "seed": "call_far", "ops": {"pitch": -2.0, "low": 0.6, "lp": 6000.0}},
	{"group": "鹿鸣", "name": "deer/call_wind", "label": "风阶段·空灵", "seed": "call_far", "ops": {"pitch": 2.0, "hp": 300.0, "reverb": 0.35}},
	{"group": "鹿鸣", "name": "deer/call_vine", "label": "藤阶段·狂暴", "seed": "call_near", "ops": {"pitch": -3.0, "low": 0.5, "drive": 1.6}},
	{"group": "鹿鸣", "name": "deer/call_death", "label": "倒地哀鸣", "seed": "call_near", "ops": {"pitch": -5.0, "lp": 2500.0, "tail": 0.7}},
	{"group": "鹿鸣", "name": "deer/call_fog", "label": "雾中远鸣（听声辨位）", "seed": "call_far", "ops": {"lp": 1500.0, "reverb": 0.5, "gain_db": -8.0}},
	{"group": "鹿鸣", "name": "beast/roar_giant", "label": "巨兽咆哮（其他 BOSS）", "seed": "call_near", "ops": {"pitch": -7.0, "low": 0.8, "drive": 1.3}},
	{"group": "奔跑蹄声", "name": "beast/gallop_heavy", "label": "重型兽类奔跑", "seed": "gallop", "ops": {"pitch": -3.0, "low": 0.6}},
	{"group": "奔跑蹄声", "name": "beast/boar_run", "label": "野猪冲锋", "seed": "gallop", "ops": {"pitch": 4.0}},
	{"group": "奔跑蹄声", "name": "beast/scurry", "label": "小动物窜动", "seed": "gallop", "ops": {"pitch": 8.0, "hp": 400.0, "gain_db": -4.0}},
	{"group": "奔跑蹄声", "name": "deer/gallop_fog", "label": "雾中蹄声", "seed": "gallop", "ops": {"lp": 1800.0, "reverb": 0.4, "gain_db": -6.0}},
	{"group": "预警", "name": "warn/gold_high", "label": "金色预警·高", "seed": "warn", "ops": {"pitch": 3.0}},
	{"group": "预警", "name": "warn/red_heavy", "label": "红色预警·沉", "seed": "warn", "ops": {"pitch": -3.0, "low": 0.4}},
	{"group": "预警", "name": "warn/alert_short", "label": "界面警示", "seed": "warn", "ops": {"pitch": 5.0, "tail": 0.4}},
	{"group": "落地", "name": "land/heavy", "label": "重落地", "seed": "land", "ops": {"pitch": -4.0, "low": 0.8, "drive": 1.3}},
	{"group": "落地", "name": "land/soft", "label": "轻落地", "seed": "land", "ops": {"pitch": 2.0, "hp": 200.0, "gain_db": -5.0}},
	{"group": "落地", "name": "land/beast", "label": "大型怪物落地", "seed": "land", "ops": {"pitch": -6.0, "low": 0.6}},
	{"group": "落地", "name": "land/log_drop", "label": "木头倒地", "seed": "land", "ops": {"pitch": -8.0, "low": 1.0, "reverb": 0.2}},
	{"group": "脚步", "name": "steps/walk_01", "label": "走路 1", "seed": "step_a", "ops": {"pitch": -1.0, "lp": 4000.0, "gain_db": -6.0}},
	{"group": "脚步", "name": "steps/walk_02", "label": "走路 2", "seed": "step_b", "ops": {"pitch": -1.0, "lp": 4000.0, "gain_db": -6.0}},
	{"group": "脚步", "name": "steps/child", "label": "小孩脚步", "seed": "step_a", "ops": {"pitch": 4.0, "gain_db": -4.0}},
	{"group": "脚步", "name": "steps/heavy", "label": "重型角色脚步", "seed": "step_b", "ops": {"pitch": -4.0, "low": 0.6}},
	{"group": "脚步", "name": "steps/sneak", "label": "潜行", "seed": "step_a", "ops": {"lp": 2500.0, "gain_db": -10.0}},
	{"group": "跳跃与位移", "name": "move/wall_jump", "label": "蹬墙跳", "seed": "jump", "ops": {"pitch": 1.0, "tail": 0.8}},
	{"group": "跳跃与位移", "name": "move/ledge_grab", "label": "抓崖边", "seed": "jump", "ops": {"pitch": -2.0, "tail": 0.5}},
	{"group": "跳跃与位移", "name": "move/npc_jump", "label": "NPC 跳跃", "seed": "jump", "ops": {"pitch": 3.0}},
	{"group": "跳跃与位移", "name": "move/glide_start", "label": "滑翔起飞", "seed": "djump", "ops": {"pitch": -2.0, "reverb": 0.25}},
	{"group": "跳跃与位移", "name": "move/dash", "label": "瞬步", "seed": "djump", "ops": {"pitch": 3.0, "tail": 0.6}},
	{"group": "跳跃与位移", "name": "move/dodge", "label": "后闪", "seed": "djump", "ops": {"pitch": -1.0, "hp": 250.0}},
	{"group": "跳跃与位移", "name": "wind/gust", "label": "风阶段·阵风", "seed": "djump", "ops": {"pitch": -6.0, "lp": 2500.0, "reverb": 0.4}},
]

var preview_path := ""
var seeds: Dictionary = {}
var mono_seeds: Dictionary = {}
var _last_channels := 2


class Biquad:
	## RBJ cookbook biquad (low-pass / high-pass), transposed direct form II.
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var z1 := 0.0
	var z2 := 0.0

	func _init(high_pass: bool, freq: float, q := 0.707) -> void:
		var w := TAU * clampf(freq, 20.0, 44100.0 * 0.45) / 44100.0
		var cw := cos(w)
		var alpha := sin(w) / (2.0 * q)
		var a0 := 1.0 + alpha
		if high_pass:
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
		else:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
		b2 = b0
		b0 /= a0
		b1 /= a0
		b2 /= a0
		a1 = -2.0 * cw / a0
		a2 = (1.0 - alpha) / a0

	func tick(x: float) -> float:
		var y := b0 * x + z1
		z1 = b1 * x - a1 * y + z2
		z2 = b2 * x - a2 * y
		return y


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--preview" and i + 1 < args.size():
			preview_path = args[i + 1]
	for key in SEEDS:
		seeds[key] = _read_seed(SEEDS[key])
		mono_seeds[key] = _last_channels == 1
	for recipe in RECIPES:
		var out := _apply(seeds[recipe.seed], recipe.ops)
		var path: String = OUT_DIR + recipe.name + ".wav"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		_write_wav(path, [out[0]] if mono_seeds[recipe.seed] else out)
	if not preview_path.is_empty():
		_write_preview()
	print("derive_sfx: %d variants from %d seeds" % [RECIPES.size(), SEEDS.size()])
	quit()


## Channels are processed independently; `stereo` is [left, right].
func _apply(stereo: Array, ops: Dictionary) -> Array:
	var seed_peak := _peak(stereo)
	var out: Array = []
	for ch in stereo:
		out.append((ch as PackedFloat32Array).duplicate())
	if ops.get("reverse", false):
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array:
			var res := ch.duplicate()
			res.reverse()
			return res)
	if ops.has("pitch"):
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array: return _pitch(ch, ops.pitch))
	if ops.has("layer"):
		var layer: Dictionary = ops.layer
		var other := _apply(seeds[layer.seed], {"pitch": layer.get("pitch", 0.0)})
		var gain := db_to_linear(layer.get("gain_db", 0.0))
		var at := int(layer.get("at", 0.0) * SR)
		for c in 2:
			out[c] = _mix(out[c], other[c], at, gain)
	if ops.has("hp"):
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array: return _filter(ch, true, ops.hp))
	if ops.has("lp"):
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array: return _filter(ch, false, ops.lp))
	if ops.has("low"):
		# Bass boost: blend a low-passed copy back in.
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array:
			return _mix(ch, _filter(ch, false, 180.0), 0, ops.low))
	if ops.has("drive"):
		var drive: float = ops.drive
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array:
			var peak := maxf(_peak([ch]), 0.0001)
			var res := ch.duplicate()
			for i in res.size():
				res[i] = tanh(res[i] / peak * drive) / tanh(drive) * peak
			return res)
	if ops.has("reverb"):
		var wet: float = ops.reverb
		out = [_reverb(out[0], wet, 0), _reverb(out[1], wet, 1)]
	if ops.has("fade_in"):
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array: return _fade(ch, ops.fade_in, 0.0, 2.0))
	if ops.has("tail"):
		out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array:
			var cut := ch.slice(0, int(ch.size() * ops.tail))
			return _fade(cut, 0.0, cut.size() * 0.4 / SR, 1.0))
	# Match the seed's peak level, then apply the recipe gain.
	var scale := seed_peak / maxf(_peak(out), 0.0001) * db_to_linear(ops.get("gain_db", 0.0))
	out = _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array: return _scale(ch, scale))
	return _map(out, func(ch: PackedFloat32Array) -> PackedFloat32Array: return _fade(ch, 0.0, 0.005, 1.0))


func _map(stereo: Array, op: Callable) -> Array:
	return [op.call(stereo[0]), op.call(stereo[1])]


## Tape-style pitch shift (duration changes with pitch), with an anti-alias low-pass when raising.
func _pitch(src: PackedFloat32Array, semitones: float) -> PackedFloat32Array:
	var ratio := pow(2.0, semitones / 12.0)
	var data := src
	if ratio > 1.0:
		data = _filter(_filter(src, false, SR * 0.45 / ratio), false, SR * 0.45 / ratio)
	var length := int(data.size() / ratio)
	var out := PackedFloat32Array()
	out.resize(length)
	for i in length:
		var pos := i * ratio
		var k := int(pos)
		var frac := pos - k
		var next := data[k + 1] if k + 1 < data.size() else 0.0
		out[i] = data[k] * (1.0 - frac) + next * frac
	return out


func _filter(src: PackedFloat32Array, high_pass: bool, freq: float) -> PackedFloat32Array:
	var bq := Biquad.new(high_pass, freq)
	var out := src.duplicate()
	for i in out.size():
		out[i] = bq.tick(src[i])
	return out


## Small Schroeder room: four combs and two all-passes; per-channel delays differ for width.
func _reverb(src: PackedFloat32Array, wet: float, channel: int) -> PackedFloat32Array:
	var tail := int(0.6 * SR)
	var dry := src.duplicate()
	dry.resize(src.size() + tail)
	for i in range(src.size(), dry.size()):
		dry[i] = 0.0
	var spread := 23 * channel
	var acc := PackedFloat32Array()
	acc.resize(dry.size())
	acc.fill(0.0)
	for delay_ms in [29.7, 37.1, 41.1, 43.7]:
		var d := int(delay_ms * 0.001 * SR) + spread
		var buf := PackedFloat32Array()
		buf.resize(dry.size())
		for i in dry.size():
			var fb := buf[i - d] if i >= d else 0.0
			buf[i] = dry[i] + fb * 0.72
			acc[i] += buf[i] * 0.25
	for delay_ms in [5.0, 1.7]:
		var d := int(delay_ms * 0.001 * SR) + spread / 4
		var res := acc.duplicate()
		for i in acc.size():
			var delayed := res[i - d] if i >= d else 0.0
			var x := acc[i - d] if i >= d else 0.0
			res[i] = -0.7 * acc[i] + x + 0.7 * delayed
		acc = res
	for i in dry.size():
		dry[i] = dry[i] * (1.0 - wet * 0.5) + acc[i] * wet
	return dry


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> PackedFloat32Array:
	var out := dst.duplicate()
	if at + src.size() > out.size():
		var old := out.size()
		out.resize(at + src.size())
		for i in range(old, out.size()):
			out[i] = 0.0
	for i in src.size():
		out[at + i] += src[i] * gain
	return out


func _scale(src: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	var out := src.duplicate()
	for i in out.size():
		out[i] *= gain
	return out


## Fade in over in_sec and out over out_sec; `curve` > 1 makes the fade-in swell late.
func _fade(src: PackedFloat32Array, in_sec: float, out_sec: float, curve: float) -> PackedFloat32Array:
	var out := src.duplicate()
	var n := out.size()
	var fi := mini(int(in_sec * SR), n)
	var fo := mini(int(out_sec * SR), n)
	for i in fi:
		out[i] *= pow(float(i) / fi, curve)
	for i in fo:
		out[n - 1 - i] *= float(i) / fo
	return out


func _peak(stereo: Array) -> float:
	var top := 0.0
	for ch in stereo:
		for v in ch:
			top = maxf(top, absf(v))
	return top


## Reads a seed as [left, right]; sets _last_channels so mono seeds can stay mono on output.
func _read_seed(path: String) -> Array:
	if not path.ends_with(".res"):
		return _read_wav(path)
	var stream := load(path) as AudioStreamWAV
	assert(stream != null and not stream.stereo and stream.mix_rate == SR, "Seed must be a mono 44.1kHz AudioStreamWAV: " + path)
	var samples := PackedFloat32Array()
	if stream.format == AudioStreamWAV.FORMAT_QOA:
		samples = _decode_qoa(stream.data)
	else:
		assert(stream.format == AudioStreamWAV.FORMAT_16_BITS, "Unsupported seed format: " + path)
		samples.resize(stream.data.size() / 2)
		for i in samples.size(): samples[i] = stream.data.decode_s16(i * 2) / 32768.0
	_last_channels = 1
	return [samples, samples.duplicate()]


func _be(bytes: PackedByteArray, at: int, count: int) -> int:
	var value := 0
	for i in count: value = (value << 8) | bytes[at + i]
	return value


## Mono QOA decoder (qoaformat.org): file header, then frames of an 8-byte header,
## LMS history/weights and 64-bit slices of a 4-bit scalefactor plus 20 3-bit residuals.
func _decode_qoa(bytes: PackedByteArray) -> PackedFloat32Array:
	assert(bytes.slice(0, 4).get_string_from_ascii() == "qoaf", "Not a QOA stream")
	var table := []
	for s in 16:
		var scale := roundf(pow(s + 1, 2.75))
		table.append(QOA_DEQUANT.map(func(v: float) -> int: return int(round(scale * v))))
	var total := _be(bytes, 4, 4)
	var out := PackedFloat32Array()
	var p := 8
	while out.size() < total and p + 8 <= bytes.size():
		assert(bytes[p] == 1, "Only mono QOA seeds are supported")
		var frame_samples := _be(bytes, p + 4, 2)
		p += 8
		var history: Array[int] = []
		var weights: Array[int] = []
		for k in 4:
			history.append(_signed16(_be(bytes, p + k * 2, 2)))
			weights.append(_signed16(_be(bytes, p + 8 + k * 2, 2)))
		p += 16
		var done := 0
		while done < frame_samples:
			var hi := _be(bytes, p, 4)
			var lo := _be(bytes, p + 4, 4)
			p += 8
			var scalefactor := hi >> 28
			for i in mini(20, frame_samples - done):
				# Residual i sits in bits 59-3i..57-3i of the 64-bit slice.
				var shift := 57 - 3 * i
				var q := 0
				if shift >= 32: q = (hi >> (shift - 32)) & 7
				elif shift <= 29: q = (lo >> shift) & 7
				else: q = ((hi << (32 - shift)) | (lo >> shift)) & 7
				var predicted := (history[0] * weights[0] + history[1] * weights[1] + history[2] * weights[2] + history[3] * weights[3]) >> 13
				var dequantized: int = table[scalefactor][q]
				var sample := clampi(predicted + dequantized, -32768, 32767)
				var delta := dequantized >> 4
				for k in 4: weights[k] += -delta if history[k] < 0 else delta
				history.pop_front()
				history.append(sample)
				out.append(sample / 32768.0)
			done += 20
	return out


func _signed16(value: int) -> int:
	return value - 65536 if value >= 32768 else value


## Minimal PCM16 reader: walks chunks to find fmt/data; mono input is duplicated to stereo.
func _read_wav(path: String) -> Array:
	var bytes := FileAccess.get_file_as_bytes(path)
	assert(bytes.size() > 44, "Cannot read " + path)
	var pos := 12
	var channels := 2
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if id == "fmt ":
			assert(bytes.decode_u16(pos + 8) == 1 and bytes.decode_u16(pos + 22) == 16, "Seed must be PCM16: " + path)
			assert(bytes.decode_u32(pos + 12) == SR, "Seed must be 44.1kHz: " + path)
			channels = bytes.decode_u16(pos + 10)
		elif id == "data":
			var frames := size / (2 * channels)
			left.resize(frames)
			right.resize(frames)
			for f in frames:
				var base := pos + 8 + f * 2 * channels
				left[f] = bytes.decode_s16(base) / 32768.0
				right[f] = bytes.decode_s16(base + 2) / 32768.0 if channels == 2 else left[f]
			break
		pos += 8 + size + (size & 1)
	_last_channels = channels
	return [left, right]


## Writes one channel (mono) or two (stereo) as interleaved PCM16.
func _write_wav(path: String, channels: Array) -> void:
	var count := channels.size()
	var frames: int = channels[0].size()
	for ch in channels: frames = mini(frames, ch.size())
	var block := 2 * count
	var bytes := PackedByteArray()
	bytes.resize(44 + frames * block)
	bytes.encode_u32(0, 0x46464952)  # "RIFF"
	bytes.encode_u32(4, 36 + frames * block)
	bytes.encode_u32(8, 0x45564157)  # "WAVE"
	bytes.encode_u32(12, 0x20746d66)  # "fmt "
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, count)
	bytes.encode_u32(24, SR)
	bytes.encode_u32(28, SR * block)
	bytes.encode_u16(32, block)
	bytes.encode_u16(34, 16)
	bytes.encode_u32(36, 0x61746164)  # "data"
	bytes.encode_u32(40, frames * block)
	for i in frames:
		for c in count:
			bytes.encode_s16(44 + i * block + c * 2, int(clampf(channels[c][i], -1.0, 1.0) * 32767.0))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Cannot write " + path)
	file.store_buffer(bytes)


func _write_preview() -> void:
	var to_url := func(res_path: String) -> String:
		return "file:///" + ProjectSettings.globalize_path(res_path).replace("\\", "/").trim_prefix("/")
	# Browsers cannot play Godot .res seeds, so decoded copies sit beside the preview page.
	var seed_dir := preview_path.get_base_dir().path_join("derived_sfx_seeds")
	DirAccess.make_dir_recursive_absolute(seed_dir)
	var originals: Array = []
	for key in SEEDS:
		var url: String = to_url.call(SEEDS[key])
		if SEEDS[key].ends_with(".res"):
			var copy := seed_dir.path_join(key + ".wav")
			_write_wav(copy, [seeds[key][0]])
			url = "file:///" + copy.replace("\\", "/").trim_prefix("/")
		originals.append({"label": "原始：" + SEED_LABELS[key], "url": url})
	var groups: Array = [{"group": "原始种子", "sounds": originals}]
	for recipe in RECIPES:
		if groups.back().group != recipe.group:
			groups.append({"group": recipe.group, "sounds": []})
		groups.back().sounds.append({"label": recipe.label, "url": to_url.call(OUT_DIR + recipe.name + ".wav")})
	var html := PREVIEW_TEMPLATE.replace("__DATA__", JSON.stringify(groups))
	var file := FileAccess.open(preview_path, FileAccess.WRITE)
	assert(file != null, "Cannot write preview " + preview_path)
	file.store_string(html)


const PREVIEW_TEMPLATE := """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>派生音效试听</title>
<style>
:root { --bg:#f4f2ee; --panel:#ffffff; --text:#1d1f23; --muted:#6a6f76; --accent:#9a6a1c; --play:#cfe6d6; }
@media (prefers-color-scheme: dark) { :root { --bg:#16181c; --panel:#1f2228; --text:#e6e6e6; --muted:#9aa0a8; --accent:#d9a441; --play:#3d6b4f; } }
body { margin:0; padding:24px 16px 64px; background:var(--bg); color:var(--text); font:15px/1.5 system-ui, "Microsoft YaHei", sans-serif; }
h1 { font-size:22px; margin:0 auto 6px; max-width:900px; }
p { color:var(--muted); font-size:13px; margin:0 auto 16px; max-width:900px; }
section { max-width:900px; margin:0 auto 16px; background:var(--panel); border-radius:10px; padding:12px 14px; }
h2 { font-size:16px; margin:0 0 10px; color:var(--accent); }
.grid { display:flex; flex-wrap:wrap; gap:8px; }
button { cursor:pointer; padding:7px 12px; border-radius:6px; border:1px solid transparent; background:var(--bg); color:var(--text); font:inherit; }
button:hover { border-color:var(--accent); }
button.playing { background:var(--play); }
</style></head><body>
<h1>派生音效试听</h1>
<p>最上面是原始种子，下面按用途分组的是派生变体。数字是变调的半音数，负数更低更沉，正数更高更轻。</p>
<main id="list"></main>
<script>
const DATA = __DATA__;
const list = document.getElementById("list");
for (const block of DATA) {
  const sec = document.createElement("section");
  sec.innerHTML = `<h2>${block.group}</h2><div class="grid"></div>`;
  for (const s of block.sounds) {
    const b = document.createElement("button");
    b.textContent = s.label;
    b.onclick = () => { const a = new Audio(s.url); b.classList.add("playing"); a.onended = () => b.classList.remove("playing"); a.play(); };
    sec.querySelector(".grid").appendChild(b);
  }
  list.appendChild(sec);
}
</script></body></html>
"""
