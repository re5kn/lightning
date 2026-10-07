extends Node
## 画面の流れ (タイトル → プレイ → time up → リザルト) と入力。
## 入力はすべて InputMap のアクション (プロジェクト設定 > インプットマップ) で受ける。
##   lane_left / lane_right / shift_up / shift_down / pause / sound_toggle / menu_up / menu_down / menu_accept

const P := preload("res://scripts/params.gd")
const SAVE_PATH := "user://save.cfg"

@onready var world: Node3D = $World
@onready var hud: Control = $HUDLayer/HUD
@onready var snd: Node = $Sound

var state := "title"        # title / play / timeup / result
var paused := false
var race: Race
var menu_sel := 0
var menu_line := 0.0
var state_t := 0.0
var anim_t := 0.0
var record := 0
var total_dst := P.START_TOTAL_DST
var time_override := 0.0    # テスト用: 制限時間 (秒)。Web は URL の ?time=60、PC は -- --time=60


func _ready() -> void:
	hud.main = self
	world.visible = false
	_load()
	_read_test_options()


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	anim_t += delta
	state_t += dt
	match state:
		"title", "result":
			_menu_input()
			menu_line += (1.0 - menu_line) * minf(1.0, dt * 8.0)
		"play":
			_play_input()
			if paused:
				menu_line += (1.0 - menu_line) * minf(1.0, dt * 8.0)
			if not paused:
				if race.update(dt):
					_time_up()
				else:
					snd.set_gear(race.gear)
		"timeup":
			race.update_timeup(dt)
			if state_t > 2.6:
				_set_state("result")
	if state == "play" or state == "timeup":
		world.render(race, anim_t)
	hud.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and race:
		race.release_all()


# ---------- 入力 ----------

func _play_input() -> void:
	if Input.is_action_just_pressed(&"pause"):
		_set_paused(not paused)
		return
	if Input.is_action_just_pressed(&"sound_toggle"):
		snd.set_muted(not snd.is_muted())
	if paused:
		_menu_input()
		return
	var lh := Input.is_action_pressed(&"lane_left")
	var rh := Input.is_action_pressed(&"lane_right")
	if Input.is_action_just_pressed(&"lane_left"):
		race.hold_dir(-1, true, lh, rh)
	elif Input.is_action_just_released(&"lane_left"):
		race.hold_dir(-1, false, lh, rh)
	if Input.is_action_just_pressed(&"lane_right"):
		race.hold_dir(1, true, lh, rh)
	elif Input.is_action_just_released(&"lane_right"):
		race.hold_dir(1, false, lh, rh)
	if Input.is_action_just_pressed(&"shift_up"):
		race.shift_up()
	if Input.is_action_just_pressed(&"shift_down"):
		race.shift_down()


func _menu_input() -> void:
	if Input.is_action_just_pressed(&"menu_up"):
		_menu_move(-1)
	elif Input.is_action_just_pressed(&"menu_down"):
		_menu_move(1)
	elif Input.is_action_just_pressed(&"menu_accept"):
		_menu_ok()
	elif Input.is_action_just_pressed(&"sound_toggle"):
		snd.set_muted(not snd.is_muted())


func _unhandled_input(event: InputEvent) -> void:
	# マウス / タッチでメニューを選ぶ
	if (state == "title" or state == "result" or paused) and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var y0 := menu_y0()
		var i := roundi((event.position.y - y0) / 52.0)
		var n := menu_items().size()
		if i >= 0 and i < n and absf(event.position.y - (y0 + i * 52.0)) < 26.0:
			menu_sel = i
			_menu_ok()


func menu_items() -> Array:
	if state == "title":
		return ["start", "sound " + ("off" if snd.is_muted() else "on")]
	if paused:
		return ["resume", "quit"]
	return ["try again", "main menu"]


func menu_y0() -> float:
	if paused:
		return 390.0
	return 400.0 if state == "title" else 560.0


func _menu_move(d: int) -> void:
	var n := menu_items().size()
	menu_sel = (menu_sel + d + n) % n
	menu_line = 0.0
	snd.play(&"menu")


func _menu_ok() -> void:
	if state == "title":
		if menu_sel == 0:
			_start_game()
		else:
			snd.set_muted(not snd.is_muted())
			snd.play(&"ok")
	elif paused:
		if menu_sel == 0:
			_set_paused(false)
		else:
			_quit_race()
	elif state == "result":
		if menu_sel == 0:
			_start_game()
		else:
			snd.play(&"ok")
			_set_state("title")


# ---------- 画面の切り替え ----------

func _set_state(s: String) -> void:
	state = s
	state_t = 0.0
	menu_sel = 0
	menu_line = 0.0
	world.visible = s == "play" or s == "timeup"


func _start_game() -> void:
	snd.play(&"ok")
	race = Race.new()
	race.sound.connect(snd.play)
	if time_override > 0.0:
		race.time = time_override
	paused = false
	_set_state("play")
	snd.bgm_start()


## ポーズ画面を開く / 閉じる。開いたときは「resume」を選んだ状態から
func _set_paused(p: bool) -> void:
	paused = p
	menu_sel = 0
	menu_line = 0.0
	race.release_all()
	snd.bgm_pause(p)
	snd.play(&"menu")


## ポーズ画面で quit: そこまでのスコアと距離でリザルト画面へ (time up と同じく自己ベスト・累計距離に反映)
func _quit_race() -> void:
	paused = false
	race.playing = false
	race.score = floorf(race.score)
	snd.bgm_pause(false)
	snd.bgm_stop()
	snd.play(&"ok")
	_finish_race()
	_set_state("result")


func _time_up() -> void:
	snd.bgm_stop()
	snd.play(&"timeup")
	_finish_race()
	_set_state("timeup")


func _finish_race() -> void:
	total_dst += race.dist / P.DST_UNIT
	if int(race.score) > record:
		record = int(race.score)
		race.new_record = true
	_save()


# ---------- 保存 (自己ベスト・累計距離) ----------

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		record = cf.get_value("progress", "record", 0)
		total_dst = cf.get_value("progress", "total_dst", P.START_TOTAL_DST)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "record", record)
	cf.set_value("progress", "total_dst", total_dst)
	cf.save(SAVE_PATH)


func _read_test_options() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			time_override = a.trim_prefix("--time=").to_float()
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('time')", true)
		if v is String:
			time_override = v.to_float()
