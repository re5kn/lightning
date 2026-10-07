extends Node
## 効果音と BGM。たたき台の WebAudio 合成をそのまま音色ごとに再現し、起動時に PCM へ書き出して鳴らす。
## BGM はテクノ系の 4 小節ループを楽器ごとのレイヤーに分けて同時再生し、ギアが上がるほどレイヤーを重ねる。

const RATE := 22050
const MASTER := 0.55
const BPM := 128.0
const ROOTS := [55.0, 55.0, 43.65, 49.0]            # A A F G
const ARP := [0, 12, 7, 15, 12, 19, 7, 24]

var _sfx := {}                  # name -> AudioStreamPlayer
var _layers: Array[Dictionary] = []   # {player, min_gear, vol}
var _pending: Array[Callable] = []    # まだ書き出していない BGM レイヤー (1 フレームに 1 つずつ作る)
var _bgm_on := false
var _gear := -1
var _muted := false


func _ready() -> void:
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	_make_sfx()
	_pending = [
		_layer.bind(0, _bgm_base),
		_layer.bind(1, _bgm_hat),
		_layer.bind(2, _bgm_clap),
		_layer.bind(3, _bgm_arp),
		_layer.bind(4, _bgm_offhat),
	]


func _process(_dt: float) -> void:
	if not _pending.is_empty():
		_pending.pop_front().call()
		if _bgm_on and _pending.is_empty():
			_start_layers()


func play(name: StringName) -> void:
	var p: AudioStreamPlayer = _sfx.get(name)
	if p:
		p.play()


func set_muted(m: bool) -> void:
	_muted = m
	AudioServer.set_bus_mute(0, m)


func is_muted() -> bool:
	return _muted


func bgm_start() -> void:
	_bgm_on = true
	_gear = -1
	if _pending.is_empty():
		_start_layers()


func bgm_stop() -> void:
	_bgm_on = false
	for l in _layers:
		l.player.stop()


func bgm_pause(paused: bool) -> void:
	for l in _layers:
		l.player.stream_paused = paused


func set_gear(gear: int) -> void:
	if gear == _gear:
		return
	_gear = gear
	for l in _layers:
		var v: float = l.vol.call(gear) if l.vol is Callable else (1.0 if gear >= l.min_gear else 0.0)
		l.player.volume_db = linear_to_db(v) if v > 0.0 else -80.0


func _start_layers() -> void:
	_gear = -1
	for l in _layers:
		l.player.play()


# ---------- 効果音 ----------

func _make_sfx() -> void:
	_add_sfx(&"lane", 0.1, func(b): _tone(b, 0, 1100, 0.05, "sine", 0.12))
	_add_sfx(&"up", 0.35, func(b): _tone(b, 0, 220, 0.3, "saw", 0.12, 880, 2400))
	_add_sfx(&"down", 0.3, func(b): _tone(b, 0, 700, 0.25, "saw", 0.12, 160, 1800))
	_add_sfx(&"deny", 0.15, func(b): _tone(b, 0, 110, 0.12, "square", 0.08))
	_add_sfx(&"bonus", 0.2, func(b):
		_tone(b, 0, 1320, 0.07, "square", 0.06)
		_tone(b, 0.06, 1760, 0.1, "square", 0.06))
	_add_sfx(&"full", 0.45, func(b):
		for i in 4:
			_tone(b, i * 0.06, [660, 880, 1320, 1760][i], 0.18, "triangle", 0.14))
	_add_sfx(&"time", 0.4, func(b):
		for i in 5:
			_tone(b, i * 0.05, [880, 1175, 1480, 1760, 2350][i], 0.12, "square", 0.06))
	_add_sfx(&"cut", 0.35, func(b):
		_noise(b, 0, 0.3, 0.35, "bandpass", 900)
		_tone(b, 0, 260, 0.3, "square", 0.1, 90))
	_add_sfx(&"crash", 0.95, func(b):
		_noise(b, 0, 0.9, 0.6, "lowpass", 700)
		_tone(b, 0, 140, 0.8, "saw", 0.2, 30))
	_add_sfx(&"timeup", 1.15, func(b):
		_tone(b, 0, 880, 0.25, "triangle", 0.15)
		_tone(b, 0.2, 660, 0.25, "triangle", 0.15)
		_tone(b, 0.4, 440, 0.7, "triangle", 0.15))
	_add_sfx(&"menu", 0.06, func(b): _tone(b, 0, 1500, 0.04, "sine", 0.08))
	_add_sfx(&"ok", 0.25, func(b):
		_tone(b, 0, 990, 0.08, "triangle", 0.12)
		_tone(b, 0.07, 1480, 0.14, "triangle", 0.1))


func _add_sfx(name: StringName, dur: float, fn: Callable) -> void:
	var buf := PackedFloat32Array()
	buf.resize(int(dur * RATE))
	fn.call(buf)
	var p := AudioStreamPlayer.new()
	p.stream = _to_wav(buf, false)
	p.max_polyphony = 4
	add_child(p)
	_sfx[name] = p


# ---------- BGM (16 分音符 × 64 ステップ = 4 小節) ----------

func _step_dur() -> float:
	return 60.0 / BPM / 4.0


func _layer(min_gear: int, fn: Callable) -> void:
	var buf := PackedFloat32Array()
	buf.resize(int(round(_step_dur() * 64.0 * RATE)))
	var vol = fn.call(buf)
	var p := AudioStreamPlayer.new()
	p.stream = _to_wav(buf, true)
	p.volume_db = -80.0
	add_child(p)
	_layers.append({"player": p, "min_gear": min_gear, "vol": vol})


func _bgm_base(b: PackedFloat32Array) -> Variant:
	var sd := _step_dur()
	for st in 64:
		var t := st * sd
		var root: float = ROOTS[st / 16 % 4]
		if st % 4 == 0:
			_tone(b, t, 150, 0.16, "sine", 0.7, 42)
		if st % 4 == 2:
			_tone(b, t, root * 2.0, sd * 1.6, "saw", 0.16, 0, 540)
		if st % 8 == 7:
			_tone(b, t, root * 4.0, sd * 0.8, "saw", 0.09, 0, 800)
	return null


func _bgm_hat(b: PackedFloat32Array) -> Variant:
	for st in 64:
		if st % 4 == 2:
			_noise(b, st * _step_dur(), 0.04, 0.12, "highpass", 7500)
	return null


func _bgm_clap(b: PackedFloat32Array) -> Variant:
	for st in 64:
		if st % 16 == 4 or st % 16 == 12:
			_noise(b, st * _step_dur(), 0.14, 0.16, "bandpass", 1600)
	return null


func _bgm_arp(b: PackedFloat32Array) -> Variant:
	var sd := _step_dur()
	for st in 64:
		var root: float = ROOTS[st / 16 % 4]
		_tone(b, st * sd, root * 4.0 * pow(2.0, ARP[st % 8] / 12.0), sd * 0.9, "square", 0.035, 0, 2400)
	# 音量は 3rd で 0.035、ギアが上がるごとに +0.01
	return func(gear: int) -> float: return 0.0 if gear < 3 else (0.035 + (gear - 3) * 0.01) / 0.035


func _bgm_offhat(b: PackedFloat32Array) -> Variant:
	for st in 64:
		if st % 2 == 1:
			_noise(b, st * _step_dur(), 0.025, 0.05, "highpass", 9000)
	return null


# ---------- 合成 ----------

## 発振器 (sine / square / saw / triangle)。周波数 f → f2 と音量 vol → 0 は指数カーブ。cutoff > 0 ならローパス
func _tone(buf: PackedFloat32Array, start: float, f: float, dur: float, type: String, vol: float, f2 := 0.0, cutoff := 0.0) -> void:
	var n := int((dur + 0.02) * RATE)
	var n0 := int(start * RATE)
	var size := buf.size()
	var steps := dur * RATE
	var f_mul := pow(f2 / f, 1.0 / steps) if f2 > 0.0 else 1.0
	var g_mul := pow(0.0008 / vol, 1.0 / steps)
	var fl := _biquad("lowpass", cutoff, 2.0) if cutoff > 0.0 else PackedFloat32Array()
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var phase := 0.0
	var fr := f
	var g := vol
	for i in n:
		phase += fr / RATE
		phase -= floorf(phase)
		var o: float
		match type:
			"sine": o = sin(TAU * phase)
			"square": o = 1.0 if phase < 0.5 else -1.0
			"saw": o = 2.0 * phase - 1.0
			_: o = 1.0 - 4.0 * absf(phase - 0.5)
		if not fl.is_empty():
			var y := fl[0] * o + fl[1] * x1 + fl[2] * x2 - fl[3] * y1 - fl[4] * y2
			x2 = x1; x1 = o; y2 = y1; y1 = y
			o = y
		buf[(n0 + i) % size] += o * g
		if i < steps:
			fr *= f_mul
			g *= g_mul


## ノイズ (フィルタ: lowpass / highpass / bandpass)
func _noise(buf: PackedFloat32Array, start: float, dur: float, vol: float, type: String, freq: float) -> void:
	var n := int((dur + 0.02) * RATE)
	var n0 := int(start * RATE)
	var size := buf.size()
	var steps := dur * RATE
	var g_mul := pow(0.0008 / vol, 1.0 / steps)
	var fl := _biquad(type, freq, 1.0)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var g := vol
	for i in n:
		var o := randf() * 2.0 - 1.0
		var y := fl[0] * o + fl[1] * x1 + fl[2] * x2 - fl[3] * y1 - fl[4] * y2
		x2 = x1; x1 = o; y2 = y1; y1 = y
		buf[(n0 + i) % size] += y * g
		if i < steps:
			g *= g_mul


## RBJ の双二次フィルタ係数 [b0, b1, b2, a1, a2] (a0 で正規化)
func _biquad(type: String, fc: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * minf(fc, RATE * 0.45) / RATE
	var cw := cos(w0)
	var alpha := sin(w0) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b: Array
	match type:
		"lowpass": b = [(1.0 - cw) / 2.0, 1.0 - cw, (1.0 - cw) / 2.0]
		"highpass": b = [(1.0 + cw) / 2.0, -(1.0 + cw), (1.0 + cw) / 2.0]
		_: b = [alpha, 0.0, -alpha]
	return PackedFloat32Array([b[0] / a0, b[1] / a0, b[2] / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])


func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * MASTER, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w
