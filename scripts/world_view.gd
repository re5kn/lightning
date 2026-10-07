extends Node3D
## 3D 表示。カメラをコースに沿って動かし、道路の縁・光の筋・自機を 3D 空間の光の帯として描く。
## 帯はカメラの方を向いたリボン (たたき台の線の太さ = 遠近で細くなる線と同じ見え方)。
## 遠くでも 1px より細くならないようにし、奥の半分でフェードアウトする。

const P := preload("res://scripts/params.gd")

@onready var camera: Camera3D = $Camera
@onready var lines: MeshInstance3D = $Lines

var _mesh := ArrayMesh.new()
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _cam_pos := Vector3.ZERO
var _cam_fwd := Vector3.FORWARD
var _px_per_unit := 684.0      # z = 1 での 1 ワールド単位の画面上の px (720p 基準)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lines.material_override = mat
	lines.mesh = _mesh
	lines.custom_aabb = AABB(Vector3(-10000, -1000, -10000), Vector3(20000, 2000, 20000))
	# 地平線が画面の上から 30% の位置に来る、レンズシフトした透視投影 (たたき台の投影と同じ)
	var near := 0.5
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = near / P.FOCAL
	camera.frustum_offset = Vector2(0.0, -near * (0.5 - P.HORIZON_Y) / P.FOCAL)
	camera.near = near
	camera.far = P.VIEW + 100.0
	_px_per_unit = 720.0 * P.FOCAL


func render(race: Race, t: float) -> void:
	var s_cam := race.s - P.CAM_BACK
	_set_camera(s_cam, race.cam_d)
	_verts.clear()
	_cols.clear()
	_idx.clear()

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

	# 自機 (白い線)。無敵時間中は点滅
	var blink := race.invuln > 0.0 and floori(t * 10.0) % 2 == 0
	if not blink:
		var pp := PackedVector3Array()
		for p in race.pt.trail:
			if p.x >= s_cam + 1.0:
				pp.append(Track.world(p.x, p.y))
		_line(pp, Color.WHITE, 0.15, 0.2)

	_mesh.clear_surfaces()
	if _idx.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_COLOR] = _cols
		arrays[Mesh.ARRAY_INDEX] = _idx
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


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


## 点列を 1 本の線として描く。手前のクリップ面で切り、見える区間ごとに帯にする
func _line(pts: PackedVector3Array, col: Color, width: float, glow: float) -> void:
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
			_emit(run, col, width, glow)
			run = PackedVector3Array()
		prev_z = z
	if run.size() >= 2:
		_emit(run, col, width, glow)


func _emit(run: PackedVector3Array, col: Color, width: float, glow: float) -> void:
	if run.size() < 2:
		return
	if glow > 0.0:
		_strip(run, Color(col, col.a * glow), width, 3.2)
	_strip(run, col, width, 1.0)


func _strip(run: PackedVector3Array, col: Color, width: float, mul: float) -> void:
	var n := run.size()
	var base := _verts.size()
	for i in n:
		var p := run[i]
		var tangent := run[mini(i + 1, n - 1)] - run[maxi(i - 1, 0)]
		var z := _depth(p)
		var half := maxf(width, z / _px_per_unit) * mul * 0.5
		var side := tangent.cross(p - _cam_pos).normalized() * half
		_verts.append(p - side)
		_verts.append(p + side)
		var c := Color(col, col.a * _fade(z))
		_cols.append(c)
		_cols.append(c)
	for i in n - 1:
		var k := base + i * 2
		_idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
