class_name Track
## コース: オーバル (直線2本 + 半円2つ)。s = 中心線に沿った距離、d = 横位置 (右がプラス)。
## ワールド座標は Godot の Y が上。たたき台の平面座標 (x, y) を (x, -y) として XZ 平面に置く。

const LS := 420.0
const R := 130.0
const LENGTH := 2.0 * LS + 2.0 * PI * R


## 中心線上の点と向き。戻り値は (x, y, 向き th)
static func at(s: float) -> Vector3:
	s = fposmod(s, LENGTH)
	if s < LS:
		return Vector3(-LS / 2.0 + s, -R, 0.0)
	if s < LS + PI * R:
		var p := (s - LS) / R
		return Vector3(LS / 2.0 + R * sin(p), -R * cos(p), p)
	if s < 2.0 * LS + PI * R:
		var u := s - LS - PI * R
		return Vector3(LS / 2.0 - u, R, PI)
	var q := (s - 2.0 * LS - PI * R) / R
	return Vector3(-LS / 2.0 - R * sin(q), R * cos(q), PI + q)


## ゆるい起伏
static func height(s: float) -> float:
	return 2.5 * sin(s / LENGTH * TAU * 3.0)


## (s, d) → ワールド座標
static func world(s: float, d: float) -> Vector3:
	var t := at(s)
	return Vector3(t.x + d * sin(t.z), height(s), -(t.y - d * cos(t.z)))
