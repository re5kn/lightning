extends Node3D
## 3D 表示。カメラをコースに沿って動かし、道路の縁・光の筋・自機を 3D 空間の光の帯として描く。
## 帯はカメラの方を向いたリボン (たたき台の線の太さ = 遠近で細くなる線と同じ見え方)。
## 遠くでも 1px より細くならないようにし、奥の半分でフェードアウトする。
##
## 見た目 (view) は 2 種類:
##   standard: 暗い背景に光の帯だけ
##   kaleidoscope-tube-hidden: 床を道路で平らにしたチューブの中を走る。チューブの内壁に万華鏡の網目と骨組みを線で描き、
##     壁と道路は背景と同じ暗い色で不透明に塗る。深度バッファで、手前の壁や坂の向こうに回り込んだ線が隠れる (陰線処理)

const P := preload("res://scripts/params.gd")
const VIEWS := ["standard", "kaleidoscope-tube-hidden"]
const CLEAR_STANDARD := Color(0.0784314, 0.0784314, 0.0862745)

# 万華鏡 (たたき台の KS / KT / KH)
const KS_N := 8                  # 万華鏡の区画数 (鏡写しで 2n 枚)
const KS_HOLE := 0.66            # くさびの中の破片が生まれ直す半径の目安
const KS_ITEMS := 26             # くさびの中の破片の数
const KS_MAX_EDGES := 28         # 網目の線の数 (短い線から)
const KT_LEN := 60.0             # 模様の 1 タイルの奥行き (奥行き方向にも折り返して並べる)
const KH_S := 10.0               # 輪切りの間隔
const KH_R := 12.0               # チューブの半径
const KH_NT := 32                # 壁の断面の分割数
const KH_DEPTH := 260.0          # チューブを描く奥行き
const KH_WALL := Color("#05030c")
const KH_ROAD := Color("#0a0716")
const KH_SKEL := Color(150 / 255.0, 120 / 255.0, 1.0)
const KH_RING := Color(200 / 255.0, 180 / 255.0, 1.0)

@onready var camera: Camera3D = $Camera
@onready var lines: MeshInstance3D = $Lines
@onready var surfaces: MeshInstance3D = $Surfaces

var view := "standard"
var _mesh := ArrayMesh.new()
var _surf_mesh := ArrayMesh.new()
var _sv := PackedVector3Array()
var _sc := PackedColorArray()
var _si := PackedInt32Array()
var _ks_items: Array[Dictionary] = []   # {r, a, w, col}: くさびの中の破片 (極座標)
var _ks_rot := 0.0
var _ks_last := -1.0
var _surf_k0 := -(1 << 40)                 # 壁と道路のメッシュを作ったときの輪切りの番号
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _lv := PackedVector3Array()          # 1px の細い線 (線のプリミティブ)
var _lc := PackedColorArray()
var _cam_pos := Vector3.ZERO
var _cam_fwd := Vector3.FORWARD
var _px_per_unit := 684.0      # z = 1 での 1 ワールド単位の画面上の px (720p 基準)


## 光の帯のシェーダー。深度テストはするが深度は書かない。
## 頂点をカメラの方へ少しだけ寄せて (画面上の位置は変わらない)、同じ面の上にある道路や壁の塗りに負けないようにする
const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

uniform float depth_pull = 0.015;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * (1.0 - depth_pull);
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""


func _ready() -> void:
	var sh := Shader.new()
	sh.code = LINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	lines.material_override = mat
	lines.mesh = _mesh
	lines.custom_aabb = AABB(Vector3(-10000, -1000, -10000), Vector3(20000, 2000, 20000))
	# 万華鏡チューブの壁と道路 (不透明。背景と同じ暗い色で塗り、奥の線を隠す)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.vertex_color_is_srgb = true
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	surfaces.material_override = smat
	surfaces.mesh = _surf_mesh
	surfaces.custom_aabb = lines.custom_aabb
	# 地平線が画面の上から 30% の位置に来る、レンズシフトした透視投影 (たたき台の投影と同じ)
	var near := 0.5
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = near / P.FOCAL
	camera.frustum_offset = Vector2(0.0, -near * (0.5 - P.HORIZON_Y) / P.FOCAL)
	camera.near = near
	camera.far = P.VIEW + 100.0
	_px_per_unit = 720.0 * P.FOCAL


## 見た目を切り替える。背景色もそれに合わせる
func set_view(v: String) -> void:
	view = v if VIEWS.has(v) else "standard"
	RenderingServer.set_default_clear_color(KH_WALL if view == "kaleidoscope-tube-hidden" else CLEAR_STANDARD)
	_surf_mesh.clear_surfaces()
	_surf_k0 = -(1 << 40)


func render(race: Race, t: float) -> void:
	var s_cam := race.s - P.CAM_BACK
	_set_camera(s_cam, race.cam_d)
	_verts.clear()
	_cols.clear()
	_idx.clear()
	_lv.clear()
	_lc.clear()

	if view == "kaleidoscope-tube-hidden":
		_render_tube_hidden(race, t, s_cam)
	else:
		_render_standard(race, t, s_cam)

	# 自機 (白い線)。無敵時間中は点滅
	var blink := race.invuln > 0.0 and floori(t * 10.0) % 2 == 0
	if not blink:
		var pp := PackedVector3Array()
		for p in race.pt.trail:
			if p.x >= s_cam + 1.0:
				pp.append(Track.world(p.x, p.y))
		_line(pp, Color.WHITE, 0.15, 0.2)

	_commit(_mesh, _verts, _cols, _idx)
	if _lv.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _lv
		arrays[Mesh.ARRAY_COLOR] = _lc
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


func _render_standard(race: Race, t: float, s_cam: float) -> void:
	# 道路の縁 (白い線) と、外側の薄い二重線
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var x := s_cam + 1.0
		while x < s_cam + P.VIEW:
			pts.append(Track.world(x, side * P.ROAD_HALF))
			x += 3.0
		_line(pts, Color("#f2f2f2"), 0.09, 0.0)
		var pts2 := PackedVector3Array()
		x = s_cam + 1.0
		while x < s_cam + P.VIEW:
			pts2.append(Track.world(x, side * (P.ROAD_HALF + 0.9)))
			x += 4.0
		_line(pts2, Color(1, 1, 1, 0.35), 0.05, 0.0)

	# 光の筋。虹色の線: 線全体が単色のまま、短い間隔で別の色へ次々と切り替わる
	var flick := floori(t * 9.0)
	for st in race.streams:
		var pts := PackedVector3Array()
		for p in st.trail:
			pts.append(Track.world(p.x, p.y))
		var c: Color = P.PALETTE[(flick + st.color_seed) % P.PALETTE.size()] if st.rainbow else st.color
		st.cur_color = c
		_line(pts, c, 0.13, 0.45 if st.adj and race.max_g < P.TOP else 0.2)


func _commit(mesh: ArrayMesh, v: PackedVector3Array, c: PackedColorArray, idx: PackedInt32Array) -> void:
	mesh.clear_surfaces()
	if idx.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# ---------- 万華鏡チューブ (陰線処理版) ----------

## くさびの中の破片を動かす (たたき台の updateKaleidoTex の前半)。速く走るほど模様が速く広がる
func _update_kaleido(t: float, speed: float) -> void:
	var wedge := PI / KS_N
	var dt := minf(0.05, t - _ks_last) if _ks_last >= 0.0 else 0.0
	_ks_last = t
	_ks_rot += dt * (0.3 + speed * 0.01)
	while _ks_items.size() < KS_ITEMS:
		_ks_items.append({r = randf(), a = randf() * wedge, w = (randf() - 0.5) * 0.6, col = randi() % P.PALETTE.size()})
	for it in _ks_items:
		it.r += dt * (0.12 + speed * 0.009) * (0.5 + it.r)
		it.a += dt * it.w
		if it.r > 1.0 or it.a < 0.0 or it.a > wedge:
			it.r = KS_HOLE * 0.9 * randf()
			it.a = randf() * wedge


## 網目の線: くさびの中の破片どうしで近いものを結ぶ (短い線から KS_MAX_EDGES 本)
func _kaleido_edges() -> Array:
	var pos: Array[Vector2] = []
	for it in _ks_items:
		pos.append(Vector2(cos(it.a), sin(it.a)) * it.r)
	var edges := []
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			var dd := pos[i].distance_to(pos[j])
			if dd < 0.2:
				edges.append([i, j, dd])
	edges.sort_custom(func(x, y): return x[2] < y[2])
	if edges.size() > KS_MAX_EDGES:
		edges.resize(KS_MAX_EDGES)
	return edges


## 床を道路で平らにしたチューブ。壁の点は (コース上の位置 s, 角度 th)。th = 0 が右、PI/2 が真上
func _render_tube_hidden(race: Race, t: float, s_cam: float) -> void:
	_update_kaleido(t, race.speed)
	var half := P.ROAD_HALF + 1.0
	var c0 := sqrt(KH_R * KH_R - half * half)               # 道路からチューブの中心までの高さ
	var ta := -asin(c0 / KH_R)                              # 道路より上にある弧の範囲 ta 〜 tb
	var span := PI - 2.0 * ta
	var n2 := KS_N * 2
	var wedge := PI / KS_N
	var off := _ks_rot * 0.3
	var gear := race.gear
	var k0 := floori((s_cam - 2.0) / KH_S)
	var k1 := ceili((s_cam + KH_DEPTH) / KH_S)
	var near := k0 * KH_S
	var far := k1 * KH_S

	# 面: 壁 (少し外側の半径で塗り、壁に沿う線が埋もれないようにする) と道路。輪切りの位置が変わったときだけ作り直す
	if k0 != _surf_k0:
		_surf_k0 = k0
		_build_tube_surfaces(k0, k1, c0)

	# コースの中心と右向きの単位ベクトルを、輪切りの半分の間隔で求めておく (骨組みと道路の線はこの上に置く)
	var step := KH_S / 2.0
	var nf := (k1 - k0) * 2 + 1
	var fc := PackedVector3Array()
	var fl := PackedVector3Array()
	for i in nf:
		var s := near + i * step
		var tr := Track.at(s)
		fc.append(Vector3(tr.x, Track.height(s), -tr.y))
		fl.append(Vector3(sin(tr.z), 0.0, cos(tr.z)))

	var skel_col := Color(KH_SKEL, 0.3 + gear * 0.06)
	# 骨組み: 壁と道路の境目、区画の境目の線
	var skel_th := [ta, PI - ta]
	for k in n2:
		var th := k * wedge + off
		if fposmod(th - ta, TAU) <= span:
			skel_th.append(th)
	for th in skel_th:
		var dx := KH_R * cos(th)
		var up := Vector3(0.0, c0 + KH_R * sin(th), 0.0)
		var pts := PackedVector3Array()
		for i in range(0, nf, 2):
			pts.append(fc[i] + fl[i] * dx + up)
		_line(pts, skel_col, 0.04, 0.0)
	# 骨組み: タイルの継ぎ目の輪
	var m := ceili(near / KT_LEN)
	while m * KT_LEN <= far:
		var i := roundi((m * KT_LEN - near) / step)
		var pts := PackedVector3Array()
		for j in 25:
			var th := ta + span * j / 24.0
			pts.append(fc[i] + fl[i] * (KH_R * cos(th)) + Vector3(0.0, c0 + KH_R * sin(th), 0.0))
		_line(pts, Color(KH_RING, 0.45), 0.05, 0.0)
		m += 1

	# 網目: 破片の位置 (角度 a, 奥行き r) を、角度方向に 2n 回鏡写し、奥行き方向にも折り返して並べる
	# 角度は奥行きのタイルによらないので、円弧の中に入る組と、その断面上の位置 (横位置, 高さ) を先に求めておく
	var edges := _kaleido_edges()
	var ci := PackedInt32Array()            # 線の両端の破片
	var cj := PackedInt32Array()
	var cva := PackedVector2Array()         # 両端の断面上の位置 (横位置, 高さ)
	var cvb := PackedVector2Array()
	var cta := PackedFloat32Array()         # 両端の角度
	var ctb := PackedFloat32Array()
	var ccol := PackedInt32Array()          # 色
	for k in n2:
		var flip := k % 2 != 0
		for e in edges:
			var ia: Dictionary = _ks_items[e[0]]
			var ib: Dictionary = _ks_items[e[1]]
			var tha: float = k * wedge + ((wedge - ia.a) if flip else ia.a) + off
			var thb: float = k * wedge + ((wedge - ib.a) if flip else ib.a) + off
			if fposmod(tha - ta, TAU) <= span and fposmod(thb - ta, TAU) <= span:
				ci.append(e[0])
				cj.append(e[1])
				cva.append(Vector2(KH_R * cos(tha), c0 + KH_R * sin(tha)))
				cvb.append(Vector2(KH_R * cos(thb), c0 + KH_R * sin(thb)))
				cta.append(tha)
				ctb.append(thb)
				ccol.append(ia.col)
	# 遠さで 3 段階に分けた、線の色 (濃さ) と太さ (px)
	var widths_px := PackedFloat32Array([2.0, 1.5, 1.0])
	var bcols: Array[PackedColorArray] = []
	for a in [0.95, 0.6, 0.3]:
		var pc := PackedColorArray()
		for c in P.PALETTE:
			pc.append(Color(c, minf(1.0, a * (0.7 + gear * 0.08))))
		bcols.append(pc)
	var n_items := _ks_items.size()
	var sv := PackedFloat32Array()
	var centers := PackedVector3Array()     # 破片の奥行きでのコースの中心 (道路の高さ)
	var lats := PackedVector3Array()        # そこでの右向きの単位ベクトル
	sv.resize(n_items)
	centers.resize(n_items)
	lats.resize(n_items)
	var nc := ci.size()
	for mm in range(floori(near / KT_LEN), floori(far / KT_LEN) + 1):
		var odd := mm % 2 != 0
		for i in n_items:
			var r: float = _ks_items[i].r
			var s := mm * KT_LEN + ((1.0 - r) if odd else r) * KT_LEN
			sv[i] = s
			var tr := Track.at(s)
			centers[i] = Vector3(tr.x, Track.height(s), -tr.y)
			lats[i] = Vector3(sin(tr.z), 0.0, cos(tr.z))
		for n in nc:
			var i := ci[n]
			var j := cj[n]
			var sa := sv[i]
			var sb := sv[j]
			if sa < near or sb < near or sa > far or sb > far:
				continue
			var va := cva[n]
			var pa := centers[i] + lats[i] * va.x + Vector3(0.0, va.y, 0.0)
			var z := (pa - _cam_pos).dot(_cam_fwd)
			if z < P.NEAR:
				continue
			var b := 0 if z < 70.0 else (1 if z < 150.0 else 2)
			var col := bcols[b][ccol[n]]
			if b == 0:
				# 近い線は壁に沿って曲がるよう 3 つに分けて描く
				var prev := pa
				for q in range(1, 4):
					var cur := _tube_point(lerpf(sa, sb, q / 3.0), lerpf(cta[n], ctb[n], q / 3.0), KH_R, c0)
					_seg(prev, cur, col, widths_px[0])
					prev = cur
			elif b == 1:
				var vb := cvb[n]
				_seg(pa, centers[j] + lats[j] * vb.x + Vector3(0.0, vb.y, 0.0), col, widths_px[1])
			else:
				# 遠い線は 1px なので、帯ではなく線のプリミティブで描く (軽い)
				var vb := cvb[n]
				_lv.append(pa)
				_lv.append(centers[j] + lats[j] * vb.x + Vector3(0.0, vb.y, 0.0))
				_lc.append(col)
				_lc.append(col)

	# 道路の線: 車線の境目、縁の白線と外側の薄い線
	for i in range(1, P.LANES):
		_road_line(fc, fl, P.lane_d(i) - P.LANE_W / 2.0, 2, Color(KH_SKEL, 0.28), 0.03)
	for side in [-1.0, 1.0]:
		_road_line(fc, fl, side * (P.ROAD_HALF + 0.9), 2, Color(1, 1, 1, 0.35), 0.05)
		_road_line(fc, fl, side * P.ROAD_HALF, 1, Color("#f2f2f2"), 0.09)

	# 光の筋 (チューブの中にある部分だけ)
	var flick := floori(t * 9.0)
	for st in race.streams:
		var pts := PackedVector3Array()
		for p in st.trail:
			if p.x >= near and p.x <= far:
				pts.append(Track.world(p.x, p.y))
		var c: Color = P.PALETTE[(flick + st.color_seed) % P.PALETTE.size()] if st.rainbow else st.color
		st.cur_color = c
		_line(pts, c, 0.13, 0.45 if st.adj and race.max_g < P.TOP else 0.2)


func _tube_point(s: float, th: float, r: float, c0: float) -> Vector3:
	var t := Track.at(s)
	var d := r * cos(th)
	return Vector3(t.x + d * sin(t.z), Track.height(s) + c0 + r * sin(th), -(t.y - d * cos(t.z)))


## 画面上で px の太さの 1 本の線分 (網目用の速い版。手前のクリップ面にかかる線分は描かない)
func _seg(a: Vector3, b: Vector3, col: Color, px: float) -> void:
	var za := _depth(a)
	var zb := _depth(b)
	if za < P.NEAR or zb < P.NEAR:
		return
	var side := (b - a).cross(a - _cam_pos).normalized() * (px / _px_per_unit * 0.5)
	var ha := side * za
	var hb := side * zb
	var k := _verts.size()
	_verts.append(a - ha)
	_verts.append(a + ha)
	_verts.append(b - hb)
	_verts.append(b + hb)
	_cols.append(col)
	_cols.append(col)
	_cols.append(col)
	_cols.append(col)
	_idx.append(k)
	_idx.append(k + 1)
	_idx.append(k + 2)
	_idx.append(k + 1)
	_idx.append(k + 3)
	_idx.append(k + 2)


## 道路の上の線。fc, fl はコースの中心と右向きの単位ベクトルの列。every 個おきの点を使う
func _road_line(fc: PackedVector3Array, fl: PackedVector3Array, d: float, every: int, col: Color, width: float) -> void:
	var pts := PackedVector3Array()
	for i in range(0, fc.size(), every):
		pts.append(fc[i] + fl[i] * d)
	_line(pts, col, width, 0.0)


func _build_tube_surfaces(k0: int, k1: int, c0: float) -> void:
	_sv.clear()
	_sc.clear()
	_si.clear()
	var wr := KH_R + 0.2
	var wa := -asin(c0 / wr)
	var wspan := PI - 2.0 * wa
	var foot := wr * cos(wa)                                 # 壁のすそ (道路をここまで広げて隙間をなくす)
	for k in range(k0, k1 + 1):
		var s := k * KH_S
		for j in KH_NT + 1:
			_sv.append(_tube_point(s, wa + wspan * j / KH_NT, wr, c0))
			_sc.append(KH_WALL)
		_sv.append(Track.world(s, -foot))
		_sv.append(Track.world(s, foot))
		_sc.append(KH_ROAD)
		_sc.append(KH_ROAD)
	var row := KH_NT + 3
	for k in k1 - k0:
		var a := k * row
		var b := a + row
		for j in KH_NT:
			_si.append_array([a + j, a + j + 1, b + j + 1, a + j, b + j + 1, b + j])
		var ra := a + KH_NT + 1
		var rb := b + KH_NT + 1
		_si.append_array([ra, ra + 1, rb + 1, ra, rb + 1, rb])
	_commit(_surf_mesh, _sv, _sc, _si)


## 自機の先頭の画面上の位置 (カメラの後ろなら null)
func head_screen_pos(race: Race) -> Variant:
	var p := Track.world(race.s, race.d)
	if camera.is_position_behind(p):
		return null
	return camera.unproject_position(p)


func _set_camera(s: float, d: float) -> void:
	var a := Track.world(s, d)
	var b := Track.world(s + 14.0, d)
	var f := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	_cam_pos = Vector3(a.x, Track.height(s) + P.CAM_H, a.z)
	_cam_fwd = f
	camera.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), _cam_pos)


func _depth(p: Vector3) -> float:
	return (p - _cam_pos).dot(_cam_fwd)


func _fade(z: float) -> float:
	var f := P.VIEW * 0.5
	return 1.0 if z < f else clampf(1.0 - (z - f) / (P.VIEW - f), 0.0, 1.0)


## 点列を 1 本の線として描く。手前のクリップ面で切り、見える区間ごとに帯にする。
## 太さは width (ワールド単位) だが、画面上で min_px より細くはしない
func _line(pts: PackedVector3Array, col: Color, width: float, glow: float, min_px := 1.0) -> void:
	var run := PackedVector3Array()
	var prev_z := 0.0
	for i in pts.size():
		var p := pts[i]
		var z := _depth(p)
		if z >= P.NEAR and z <= P.VIEW:
			if run.is_empty() and i > 0 and prev_z < P.NEAR:
				run.append(pts[i - 1].lerp(p, (P.NEAR - prev_z) / (z - prev_z)))
			run.append(p)
		elif not run.is_empty():
			if z < P.NEAR:
				run.append(pts[i - 1].lerp(p, (P.NEAR - prev_z) / (z - prev_z)))
			_emit(run, col, width, glow, min_px)
			run = PackedVector3Array()
		prev_z = z
	if run.size() >= 2:
		_emit(run, col, width, glow, min_px)


func _emit(run: PackedVector3Array, col: Color, width: float, glow: float, min_px: float) -> void:
	if run.size() < 2:
		return
	if glow > 0.0:
		_strip(run, Color(col, col.a * glow), width, 3.2, min_px)
	_strip(run, col, width, 1.0, min_px)


func _strip(run: PackedVector3Array, col: Color, width: float, mul: float, min_px: float) -> void:
	var n := run.size()
	var base := _verts.size()
	for i in n:
		var p := run[i]
		var tangent := run[mini(i + 1, n - 1)] - run[maxi(i - 1, 0)]
		var z := _depth(p)
		var half := maxf(width, z * min_px / _px_per_unit) * mul * 0.5
		var side := tangent.cross(p - _cam_pos).normalized() * half
		_verts.append(p - side)
		_verts.append(p + side)
		var c := Color(col, col.a * _fade(z))
		_cols.append(c)
		_cols.append(c)
	for i in n - 1:
		var k := base + i * 2
		_idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
