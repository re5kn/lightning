extends Control
## 2D の表示: HUD (スコア・残り時間・ギア・ゲージ・距離・入力表示)、タイトル、リザルト、各種演出。
## 座標は 1280×720 の論理解像度 (たたき台と同じ)。

const P := preload("res://scripts/params.gd")
const W := 1280.0
const H := 720.0

var main: Node          # main.gd

var _light: FontVariation
var _regular: FontVariation
var _logo: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := TextServerManager.get_primary_interface()
	var wght := ts.name_to_tag("wght")
	var quicksand: FontFile = load("res://assets/fonts/Quicksand.ttf")
	quicksand.fallbacks = [ThemeDB.fallback_font]
	_light = FontVariation.new()
	_light.base_font = quicksand
	_light.variation_opentype = {wght: 300}
	_regular = FontVariation.new()
	_regular.base_font = quicksand
	_regular.variation_opentype = {wght: 400}
	_logo = FontVariation.new()
	_logo.base_font = load("res://assets/fonts/Exo2-Italic.ttf")
	_logo.variation_opentype = {wght: 200}


func _draw() -> void:
	var t: float = main.anim_t
	match main.state:
		"title":
			_draw_title(t)
		"result":
			_draw_result()
		_:
			_draw_play(t)


# ---------- 文字 ----------

## たたき台の text(): (x, y) は文字の縦の中央。align は "left" / "center" / "right"
func _text(s: String, x: float, y: float, size: int, color: Color, align := "left", font: Font = null) -> void:
	if font == null:
		font = _regular
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if align == "center":
		x -= w / 2.0
	elif align == "right":
		x -= w
	var base := y + (font.get_ascent(size) - font.get_descent(size)) / 2.0
	draw_string(font, Vector2(x, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_w(s: String, size: int, font: Font) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func fmt_time(sec: float) -> String:
	var cs := maxi(0, floori(sec * 100.0))
	return "%02d:%02d:%02d" % [cs / 6000, cs / 100 % 60, cs % 100]


# ---------- プレイ中 ----------

func _draw_play(t: float) -> void:
	var g: Race = main.race
	if g == null:
		return
	# ゲージ満タン / 追い抜きのオレンジの弧 (自機の先頭の前方)
	var head = main.world.head_screen_pos(g)
	if head != null:
		for a in g.arcs:
			var k := a / 0.9
			var col := Color(1.0, 150.0 / 255.0, 40.0 / 255.0, (1.0 - k) * 0.9)
			var lw := 10.0 * (1.0 - k) + 2.0
			for r in [40.0, 75.0]:
				var rx: float = r + k * 140.0
				var pts := PackedVector2Array()
				for i in 33:
					var ang := PI + PI * i / 32.0
					pts.append(Vector2(head.x + cos(ang) * rx, head.y - 6.0 + sin(ang) * rx * 0.55))
				draw_polyline(pts, col, lw, true)
	if g.flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1.0, 40.0 / 255.0, 40.0 / 255.0, g.flash * 0.6))
	# スタート時の表示
	if g.start_t > 0.0:
		_text("ready" if g.start_t > 0.6 else "go", W / 2.0, H * 0.42, 64, Color.WHITE, "center", _light)

	_draw_hud(g, t)

	if main.state == "timeup":
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, minf(0.45, main.state_t * 0.6)))
		_text("time up", W / 2.0, H / 2.0, 84, Color.WHITE, "center", _light)
	if main.paused:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
		_text("pause", W / 2.0, H / 2.0 - 70.0, 64, Color.WHITE, "center", _light)
		_draw_menu(main.menu_items(), W / 2.0, main.menu_y0())


func _draw_hud(g: Race, t: float) -> void:
	_text("%06d" % floori(g.score), 70, 64, 44, Color.WHITE, "left", _light)
	var warn := g.time < 30.0 and floori(t * 2.0) % 2 == 1
	_text(fmt_time(g.time), W - 70, 64, 44, Color("#ff6b6b") if warn else Color.WHITE, "right", _light)

	# ボーナスのポップアップ (上部中央)
	for i in g.popups.size():
		var p: Dictionary = g.popups[i]
		var col: Color = p.color
		col.a = clampf(1.4 - p.t, 0.0, 1.0)
		_text(p.text, W / 2.0, 150.0 - p.t * 30.0 - i * 4.0 + (-40.0 if p.big else 0.0), 36 if p.big else 30, col, "center")

	# ギアのインジケータ
	var cx := 92.0
	var base := 430.0
	var gap := 40.0
	for i in P.GEARS.size():
		var c := Vector2(cx, base - i * gap)
		if i == g.gear:
			draw_circle(c, 13.0, Color.WHITE, true, -1.0, true)
		var sc := Color.WHITE if i <= g.max_g else (Color(1, 1, 1, 0.55) if i == g.max_g + 1 else Color(1, 1, 1, 0.18))
		draw_arc(c, 13.0, 0.0, TAU, 48, sc, 2.0, true)
	if g.max_g < P.TOP:
		var y := base - (g.max_g + 1) * gap
		_text("%02d%%" % floori(g.gauge), cx + 28, y, 22, Color.WHITE)
		# ゲージの細いバー
		draw_rect(Rect2(cx + 28, y + 16, 60, 3), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(cx + 28, y + 16, 60 * g.gauge / 100.0, 3), Color.WHITE)
	if not g.gauge_msg.is_empty():
		var m := g.gauge_msg
		var y := base - mini(g.max_g + 1, P.TOP) * gap + 36.0
		var al := clampf(1.4 - m.t, 0.0, 1.0)
		if m.kind == "orange":
			draw_rect(Rect2(cx + 22, y - 14, 74, 28), Color(Color("#ff7a1a"), al))
			_text(m.text, cx + 59, y, 22, Color(1, 1, 1, al), "center")
		else:
			_text(m.text, cx + 28, y, 24, Color(Color("#ff3b3b"), al))
	_text(P.GEARS[g.gear], cx - 14, base + 56, 44, Color.WHITE, "left", _light)

	# 右側: 距離とコース名
	var rx := W - 70.0
	var run_dst := g.dist / P.DST_UNIT
	_text("DST", rx, 300, 22, Color.WHITE, "right")
	_text("%.1f" % (main.total_dst + (run_dst if main.state == "play" else 0.0)), rx, 330, 22, Color.WHITE, "right")
	_text("%.1f" % run_dst, rx, 360, 22, Color.WHITE, "right")
	_text("LCT", rx, 420, 22, Color.WHITE, "right")
	_text("oval course", rx, 450, 22, Color.WHITE, "right")

	_draw_input_pad(W / 2.0, H - 70.0)


## 入力表示 (動画の Wii リモコンの代わり)。キーボードでもゲームパッドでも点灯する
func _draw_input_pad(x: float, y: float) -> void:
	var w := 300.0
	var h := 58.0
	var r := Rect2(x - w / 2.0, y - h / 2.0, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20 / 255.0, 20 / 255.0, 22 / 255.0, 0.75)
	sb.border_color = Color(1, 1, 1, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	var items := [["<", &"lane_left", -105.0], [">", &"lane_right", -55.0], ["Z", &"shift_down", 40.0], ["X", &"shift_up", 100.0]]
	var on_col := Color("#5fd8ff")
	for it in items:
		var on := Input.is_action_pressed(it[1])
		var c := Vector2(x + it[2], y)
		if on:
			draw_circle(c, 18.0, on_col, true, -1.0, true)
		draw_arc(c, 18.0, 0.0, TAU, 48, on_col if on else Color(1, 1, 1, 0.6), 1.5, true)
		var fg := Color("#06202a") if on else Color.WHITE
		if it[0] == "<" or it[0] == ">":
			var sgn := -1.0 if it[0] == "<" else 1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(7 * sgn, 0), c + Vector2(-5 * sgn, -7), c + Vector2(-5 * sgn, 7)]), fg)
		else:
			_text(it[0], c.x, c.y + 1, 18, fg, "center")
	_text("down", x + 40, y + 38, 11, Color(1, 1, 1, 0.5), "center")
	_text("up", x + 100, y + 38, 11, Color(1, 1, 1, 0.5), "center")


# ---------- メニュー ----------

func _draw_menu(items: Array, x: float, y0: float, alpha := 1.0) -> void:
	for i in items.size():
		var y := y0 + i * 52.0
		var sel: bool = i == main.menu_sel
		var col := Color.WHITE if sel else Color("#7d7d82")
		col.a = alpha
		_text(items[i], x, y, 34, col, "center", _light)
		if sel:
			var right := x + _text_w(items[i], 34, _light) / 2.0 + 24.0
			draw_line(Vector2(40, y + 24), Vector2(40 + (right - 40) * main.menu_line, y + 24), Color(Color("#e8e8e8"), alpha), 2.0, true)


func _draw_title(t: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color("#141416"))
	# 虹色の線のロゴ演出
	for i in P.PALETTE.size():
		var off := i * 7.0
		var wob := sin(t * 1.3 + i * 0.5) * 6.0
		var pts := PackedVector2Array([Vector2(-10, 90 + off + wob), Vector2(170, 200 + off * 0.4), Vector2(W - 170, 200 + off * 0.4), Vector2(W + 10, 70 + off - wob)])
		draw_polyline(pts, Color(P.PALETTE[i], 0.85), 2.0, true)
	_text("lightstream", W / 2.0, 205, 104, Color(200 / 255.0, 200 / 255.0, 205 / 255.0, 0.55), "center", _logo)
	_text("prototype", W / 2.0 + 250, 262, 18, Color("#8a8a90"), "center")
	var items: Array = main.menu_items()
	_draw_menu(items, W / 2.0, main.menu_y0())
	if main.record > 0:
		_text("record " + str(main.record), W / 2.0, 330, 20, Color("#8a8a90"), "center")
	_text("keyboard:  LEFT / RIGHT  lane (hold to repeat)    X / UP  shift up    Z / DOWN  shift down    Enter  select    Esc  pause    M  sound    V  view", W / 2.0, H - 70, 16, Color("#8a8a90"), "center")
	_text("gamepad:  D-pad / left stick  lane    A / RB  shift up    X / LB  shift down    Start  pause    Back  view", W / 2.0, H - 42, 16, Color("#6a6a70"), "center")


func _draw_result() -> void:
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	var g: Race = main.race
	var a := clampf(main.state_t * 2.0, 0.0, 1.0)
	var white := Color(1, 1, 1, a)
	_text("time attack", W / 2.0, 120, 26, white, "center", _light)
	_text("oval course", W / 2.0, 185, 60, white, "center", _light)
	_text("score " + str(int(g.score)), W / 2.0, 290, 60, white, "center", _light)
	_text("record " + str(main.record) + ("  new!" if g.new_record else ""), W / 2.0, 360, 28, Color(Color("#ffd23b"), a) if g.new_record else white, "center", _light)
	_text("distance %.1f" % (g.dist / P.DST_UNIT), W / 2.0, 410, 28, white, "center", _light)
	_draw_menu(main.menu_items(), W / 2.0, main.menu_y0(), a)
