class_name Race
extends RefCounted
## 1プレイ分の状態とルール (たたき台 index.html の newGame / update / moveStreams / judge などの移植)。
## 描画や入力には依存しない。効果音は sound シグナルで知らせる。

signal sound(name: StringName)

const P := preload("res://scripts/params.gd")


## 光の筋 (自機も同じ形で持つ)。trail は (s, d) の点列で、s の昇順
class Stream:
	var s := 0.0              # 先頭の位置
	var d := 0.0              # 先頭の横位置
	var lane := 0
	var tgt := 0              # 移動先の車線
	var v := 0.0
	var length := 0.0
	var rainbow := false
	var color := Color.WHITE
	var cur_color := Color.WHITE   # 描画中の色 (虹色の線は毎フレーム変わる)
	var color_seed := 0
	var trail: Array[Vector2] = []
	var moving_t := 9.0
	var prev_head_rel := 0.0
	var passed := false
	var adj := false
	var lmin := 0             # trail が通る車線の範囲 (判定の高速化用)
	var lmax := 0

	func update_lane_range() -> void:
		lmin = 99
		lmax = -99
		for p in trail:
			var l := Params.lane_of(p.y)
			lmin = mini(lmin, l)
			lmax = maxi(lmax, l)


var s := 0.0                 # 自機の先端位置
var speed := 0.0
var lane := 0
var d := 0.0
var cam_d := 0.0
var lane_t := 9.0
var gear := 0
var max_g := 0
var gauge := 0.0
var gauge_rate := 0.0
var score := 0.0
var dist := 0.0
var time := P.TIME_LIMIT
var start_t := 1.8
var invuln := 0.0
var flash := 0.0
var streams: Array[Stream] = []
var spawn_cd := 0.0
var popups: Array[Dictionary] = []     # {text, color, t, big}
var arcs: Array[float] = []            # オレンジの弧の経過時間
var gauge_msg := {}                    # {text, kind, t}
var sides := 0
var new_record := false
var playing := true                    # false = time up 後 (線は車線変更しない)
var pt := Stream.new()                 # 自機の軌跡

# 車線移動の押しっぱなし
var rep_dir := 0
var rep_t := 0.0

var _ptr := 0


func _init() -> void:
	lane = P.LANES / 2
	d = P.lane_d(lane)
	cam_d = d
	# 自機の軌跡。先頭が横へ動くと、その跡が斜めの線として残る
	pt.s = s
	pt.length = P.PLAYER_LEN
	var t := s - P.CAM_BACK - 6.0
	while t < s:
		pt.trail.append(Vector2(t, d))
		t += 2.0
	pt.trail.append(Vector2(s, d))
	# 開始時は動画のように数本の筋が自機の両側に並んでいる
	var lanes := [lane - 2, lane - 1, lane + 1, lane + 3]
	for i in lanes.size():
		add_stream(lanes[i], s + randf_range(10, 60), P.base_v() * randf_range(P.LINES_START.x, P.LINES_START.y), randf_range(70, 140), 0 if i == 3 else -1)
	add_stream(lane + 2, s + 260.0, 15.0, 120.0)


## rainbow: -1 = ランダム, 0 = 通常, 1 = 虹色
func add_stream(l: int, head_s: float, v: float, length: float, rainbow := -1) -> Stream:
	if l < 0 or l >= P.LANES:
		return null
	var st := Stream.new()
	if rainbow < 0:
		var any := false
		for o in streams:
			any = any or o.rainbow
		st.rainbow = not any and randf() < P.RAINBOW_CHANCE
	else:
		st.rainbow = rainbow == 1
	st.s = head_s
	st.d = P.lane_d(l)
	st.lane = l
	st.tgt = l
	st.v = v
	st.length = length
	st.color = P.PALETTE[randi() % P.PALETTE.size()]
	st.cur_color = st.color
	st.color_seed = randi() % P.PALETTE.size()
	st.prev_head_rel = s - head_s
	var t := head_s - length
	while t < head_s:
		st.trail.append(Vector2(t, st.d))
		t += 2.0
	st.trail.append(Vector2(head_s, st.d))
	st.update_lane_range()
	streams.append(st)
	return st


## 指定位置 x で、その筋がどの車線にいるか (いなければ -1)
func lane_at(st: Stream, x: float) -> int:
	if x > st.s or x < st.s - st.length:
		return -1
	var tr := st.trail
	for i in range(tr.size() - 1, 0, -1):
		var a := tr[i - 1]
		var b := tr[i]
		if x >= a.x and x <= b.x:
			var t := (x - a.x) / (b.x - a.x) if b.x > a.x else 0.0
			return P.lane_of(lerpf(a.y, b.y, t))
	return P.lane_of(tr[0].y)


## lane_at と同じ結果を、x を昇順に調べるとき用に速く返す (呼ぶ前に _ptr = 0)
func _lane_seq(st: Stream, x: float) -> int:
	if x > st.s or x < st.s - st.length:
		return -1
	var tr := st.trail
	var n := tr.size()
	while _ptr < n - 2 and tr[_ptr + 1].x < x:
		_ptr += 1
	var a := tr[_ptr]
	var b := tr[_ptr + 1]
	if x < a.x:
		return P.lane_of(a.y)
	var t := clampf((x - a.x) / (b.x - a.x), 0.0, 1.0) if b.x > a.x else 0.0
	return P.lane_of(lerpf(a.y, b.y, t))


## 車線 l の区間 [from, to] に、除外したもの以外の線 (自機を含む) がいるか。
## 線どうしは同じ車線で重なれない (車線の排他)
func occupied(l: int, from: float, to: float, except_player := false, except_st: Stream = null) -> bool:
	if not except_player and l == lane and s + 2.0 > from and s - P.PLAYER_LEN - 2.0 < to:
		return true
	for o in streams:
		if o == except_st:
			continue
		var a := maxf(from, o.s - o.length)
		var b := minf(to, o.s)
		if a > b:
			continue
		if o.tgt == l:
			return true
		if l < o.lmin or l > o.lmax:
			continue
		_ptr = 0
		var x := a
		while x < b:
			if _lane_seq(o, x) == l:
				return true
			x += 3.0
		if _lane_seq(o, b) == l:
			return true
	return false


## 位置 from より前方で、車線 l にいる一番近い線 (自機を含む) までの距離と、その速度。いなければ空
func obstacle_ahead(l: int, from: float, except_player := false, except_st: Stream = null) -> Dictionary:
	var best := {}
	if not except_player and l == lane:
		var gap := (s - P.PLAYER_LEN) - from
		if gap > -P.PLAYER_LEN:
			best = {"gap": gap, "v": speed}
	for o in streams:
		if o == except_st or o.s <= from:
			continue
		if not best.is_empty() and o.s - o.length - from > best.gap:
			continue
		if l < o.lmin or l > o.lmax:
			continue
		_ptr = 0
		var x := maxf(from, o.s - o.length)
		while x <= o.s:
			if _lane_seq(o, x) == l:
				var gap := x - from
				if best.is_empty() or gap < best.gap:
					best = {"gap": gap, "v": o.v}
				break
			x += 1.5
	return best


func try_spawn() -> void:
	var ahead := randf() < 0.72
	var l := randi() % P.LANES
	var length := randf_range(50, 160)
	var hs: float
	var v: float
	if ahead:
		v = randf_range(12.0, maxf(24.0, speed * 0.8))
		hs = s + randf_range(300, 470)
	else:
		if l == lane:
			return
		v = maxf(speed, P.base_v()) * randf_range(P.LINES_BEHIND.x, P.LINES_BEHIND.y) + 6.0
		if v > 150.0:
			return
		hs = s - P.PLAYER_LEN - randf_range(40, 90)
	if occupied(l, hs - length - 30.0, hs + 30.0):
		return
	add_stream(l, hs, v, length)


## 割り込み (自分から線を横切った / 前に入られた) → ゲージ -50% (足りない分は最大ギアから)
## 今のギアが LO のときは、どの接触でもペナルティなし
func cut_penalty() -> void:
	if gear == 0 or invuln > 0.0:
		return
	# 足りなければ最大ギアを 1 つ下げて繰り越す (例: 最大 5th・30% → 最大 4th・80%)
	# TOP ではゲージを 0% とみなす。今のギアが新しい最大を超えていれば合わせて下げる
	var total := maxf(0.0, max_g * 100.0 + (gauge if max_g < P.TOP else 0.0) - 50.0)
	max_g = floori(total / 100.0)
	gauge = total - max_g * 100.0
	if gear > max_g:
		gear = max_g
	invuln = P.INVULN_TIME
	_gauge_msg("50%", "red")
	sound.emit(&"cut")
	flash = 0.15


## 後ろから衝突 → ギアは LO へ。解放状態とゲージは「現在の値 - 100%」
func crash() -> void:
	if gear == 0 or invuln > 0.0:
		return
	var total := maxf(0.0, max_g * 100.0 + (gauge if max_g < P.TOP else 0.0) - 100.0)
	gear = 0
	max_g = floori(total / 100.0)
	gauge = total - max_g * 100.0
	invuln = P.INVULN_TIME
	flash = 0.35
	_gauge_msg("100%", "red")
	sound.emit(&"crash")


func _popup(text: String, color := Color.WHITE, big := false) -> void:
	popups.append({"text": text, "color": color, "t": 0.0, "big": big})


func _gauge_msg(text: String, kind: String) -> void:
	gauge_msg = {"text": text, "kind": kind, "t": 0.0}


# ---------- 入力 ----------

func move_lane(dir: int) -> void:
	if not playing:
		return
	# 移動先の車線で、自機の先頭の真横に線がいたら、その線を横切ってさらに先の車線へ (ゲージ -50%)
	# 接触は先頭だけで判定する。抜いた直後の線 (先頭が自機の先頭より後ろ) の車線へは、そのまま移れる
	var n := lane + dir
	var crossed := 0
	while n >= 0 and n < P.LANES and occupied(n, s - 1.0, s + 1.0, true):
		n += dir
		crossed += 1
	if n < 0 or n >= P.LANES:
		sound.emit(&"deny")
		return
	lane = n
	lane_t = 0.0
	if crossed > 0 and gear > 0 and invuln <= 0.0:
		cut_penalty()
	else:
		sound.emit(&"lane")


func shift_up() -> void:
	if start_t > 0.0:
		return
	if gear < max_g:
		gear += 1
		sound.emit(&"up")
	else:
		sound.emit(&"deny")


func shift_down() -> void:
	if start_t > 0.0:
		return
	if gear > 0:
		gear -= 1
		sound.emit(&"down")
	else:
		sound.emit(&"deny")


## 車線移動キーを押した / 離した。left_held, right_held は今押されているか
func hold_dir(dir: int, on: bool, left_held: bool, right_held: bool) -> void:
	if on:
		move_lane(dir)
		rep_dir = dir
		rep_t = 0.22
	elif rep_dir == dir:
		rep_dir = -1 if left_held else (1 if right_held else 0)
		rep_t = 0.22


func release_all() -> void:
	rep_dir = 0


# ---------- 更新 ----------

## プレイ中の1フレーム。時間切れになったら true
func update(dt: float) -> bool:
	# 車線移動の押しっぱなし
	if rep_dir != 0:
		rep_t -= dt
		if rep_t <= 0.0:
			move_lane(rep_dir)
			rep_t = 0.12
	lane_t += dt

	# 速度。シフトアップ・ダウンで速度は階段状に一瞬で切り替わる (徐々に加減速しない)
	var target: float = P.base_v() * P.RATIO[gear]
	if start_t > 0.0:
		start_t -= dt
		if start_t >= 0.6:
			target = 0.0
	speed = target

	var ds := speed * dt
	# 前の線に追いついたら止まる (重なれない)。勢いよく当たったら衝突
	var ob := obstacle_ahead(lane, s, true)
	if not ob.is_empty() and ds >= ob.gap + ob.v * dt - 0.3:
		if speed - ob.v > 3.0 and invuln <= 0.0 and start_t <= 0.0:
			crash()
		speed = minf(speed, ob.v)
		ds = maxf(0.0, ob.gap + ob.v * dt - 0.3)
	s += ds
	dist += ds

	# 横移動: 先頭だけが斜めに進み、後ろは軌跡をたどる (1車線ぶん横へ動く間に約 LANE_RUN 前進)
	var tgt_d := P.lane_d(lane)
	var lat := maxf(P.LANE_W / 0.25 * dt, ds * P.LANE_W / P.LANE_RUN)
	d += clampf(tgt_d - d, -lat, lat)
	var tr := pt.trail
	pt.s = s
	if s - tr[tr.size() - 2].x >= 1.0:
		tr.append(Vector2(s, d))
	else:
		tr[tr.size() - 1] = Vector2(s, d)
	while tr.size() > 2 and tr[1].x < s - P.CAM_BACK - 6.0:
		tr.pop_front()
	cam_d += (d - cam_d) * minf(1.0, dt * 4.0)
	score += ds * P.SCORE_PER_UNIT * (1.0 + gear * 0.12)
	if start_t <= 0.0:
		time -= dt
	invuln -= dt
	flash -= dt

	_move_streams(dt)
	_judge(dt)

	# 生成と消去
	streams = streams.filter(func(st: Stream) -> bool: return st.s > s - 220.0 and st.s - st.length < s + 540.0)
	spawn_cd -= dt
	if spawn_cd <= 0.0 and streams.size() < P.STREAM_COUNT:
		try_spawn()
		spawn_cd = randf_range(0.25, 0.9)

	for p in popups:
		p.t += dt
	popups = popups.filter(func(p: Dictionary) -> bool: return p.t < 1.4)
	for i in arcs.size():
		arcs[i] += dt
	arcs = arcs.filter(func(a: float) -> bool: return a < 0.9)
	if not gauge_msg.is_empty():
		gauge_msg.t += dt
		if gauge_msg.t > 1.4:
			gauge_msg = {}

	if time <= 0.0:
		time = 0.0
		playing = false
		rep_dir = 0
		score = floorf(score)
		return true
	return false


## time up の演出中: 自機は減速して止まり、線はそのまま流れる
func update_timeup(dt: float) -> void:
	speed = maxf(0.0, speed - 60.0 * dt)
	s += speed * dt
	_move_streams(dt)


func _move_streams(dt: float) -> void:
	for st in streams:
		st.s += st.v * dt
		st.moving_t += dt
		# 基本は車線変更しない。同じ車線の前の線 (自機を含む) に追いつきそうなときだけ左右へよける
		var ob := obstacle_ahead(st.tgt, st.s, false, st)
		if not ob.is_empty():
			if st.v > ob.v and ob.gap < 12.0 + (st.v - ob.v) * 1.5 and st.moving_t > 0.8 and playing:
				var moved := false
				var dirs := [-1, 1] if randf() < 0.5 else [1, -1]
				for dir: int in dirs:
					var nl := st.tgt + dir
					if nl < 0 or nl >= P.LANES or occupied(nl, st.s - st.length - 8.0, st.s + 20.0, false, st):
						continue
					st.tgt = nl
					st.moving_t = 0.0
					moved = true
					# 自機のすぐ前に入ってきた → 割り込まれた
					var gap_p := (st.s - st.length) - s
					if nl == lane and gap_p > -2.0 and gap_p < 30.0:
						cut_penalty()
					break
				if not moved:
					st.v = ob.v            # よけられないので速度を合わせて後ろにつく
			if st.moving_t > 0.8 and ob.gap < 0.5:
				st.s -= minf(st.v * dt, 0.5 - ob.gap)
				st.v = minf(st.v, ob.v)
		var td := P.lane_d(st.tgt)
		st.d += clampf(td - st.d, -P.LANE_W * dt / 0.8, P.LANE_W * dt / 0.8)
		if absf(td - st.d) < 1e-3:
			st.lane = st.tgt
		var tr := st.trail
		if st.s - tr[tr.size() - 2].x >= 2.0:
			tr.append(Vector2(st.s, st.d))
		else:
			tr[tr.size() - 1] = Vector2(st.s, st.d)
		while tr.size() > 2 and tr[1].x < st.s - st.length:
			tr.pop_front()
		st.update_lane_range()


## 隣接によるゲージと追い抜きボーナスの判定 (衝突と割り込みは update / move_lane / _move_streams で判定)
func _judge(dt: float) -> void:
	var left := 0.0                 # 左右の隣の線の速さ (いなければ 0)
	var right := 0.0
	var my := lane_at(pt, s)
	for st in streams:
		st.adj = false
		# ゲージは自機の先頭の位置で判定する。先頭の真横に隣の線がある
		# (= 先頭が隣の線の先頭より後ろ、かつ尾より前) ときだけ溜まる
		var l := lane_at(st, s)
		if l >= 0:
			if l == my - 1:
				left = maxf(left, st.v)
				st.adj = true
			elif l == my + 1:
				right = maxf(right, st.v)
				st.adj = true
		var head_rel := s - st.s

		# 追い抜き: 隣の車線の線の先端を自機の先端が追い越した
		# 1 本の線につき 1 回だけ。抜いた後で抜き返されて、また抜いても加算しない
		if not st.passed and st.prev_head_rel < 0.0 and head_rel >= 0.0 and absi(P.lane_of(st.d) - lane) == 1 and start_t <= 0.0:
			st.passed = true
			# 10 秒プラスの線は、抜いた時点の色の単色になる
			if st.rainbow:
				time += P.TIME_BONUS
				_popup("+10:00", Color.WHITE, true)
				sound.emit(&"time")
				st.rainbow = false
				st.color = st.cur_color
			# 追い抜きボーナス。演出としてオレンジの弧を出す
			var b := P.bonus_of(gear)
			score += b
			_popup("+" + str(b))
			sound.emit(&"bonus")
			arcs.append(0.0)
		st.prev_head_rel = head_rel

	sides = (1 if left > 0.0 else 0) + (1 if right > 0.0 else 0)
	# ゲージ: 隣に線があると増える
	#  - 基準の速さは、今のギアではなく、その時点で上げられるギアの上限 (max_g) で決まる
	#  - 上限より低いギアで走っていると遅くなる (今のギアの速さ ÷ 上限ギアの速さ。低いほど遅い)
	#  - 隣の線が速いほど速い (隣の速さ ÷ 上限ギアの速さ)。両隣にいれば左右の分を足す
	if sides > 0 and max_g < P.TOP and start_t <= 0.0:
		var v_top: float = P.base_v() * P.RATIO[max_g]
		var rate: float = P.GAUGE_RATE[max_g] * (P.RATIO[gear] / P.RATIO[max_g]) * (_adj_mul(left, v_top) + _adj_mul(right, v_top))
		gauge_rate = rate
		gauge += rate * dt
		score += rate * dt * 0.3 * (gear + 1)
		if gauge >= 100.0:
			# 次のギアを解放するだけ (スコアの加算と弧の演出は無し)
			gauge = 0.0
			max_g += 1
			_gauge_msg("100%", "orange")
			sound.emit(&"full")


func _adj_mul(v: float, v_top: float) -> float:
	return clampf(v / v_top, P.ADJ_SPEED_MUL.x, P.ADJ_SPEED_MUL.y) if v > 0.0 else 0.0
