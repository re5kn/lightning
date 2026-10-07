extends SceneTree
## InputMap (プロジェクト設定 > インプットマップ) を作り直して project.godot に保存する。
## 実行: godot --headless --path . -s tools/setup_input.gd
## キーボードとゲームパッドの割り当てはここで決める。エディタのインプットマップで直接変えてもよい。

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = code
	return e

func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = b
	return e

func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = a
	e.axis_value = v
	return e

func _init() -> void:
	var actions := {
		# プレイ中
		"lane_left": [_key(KEY_LEFT), _key(KEY_A), _btn(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"lane_right": [_key(KEY_RIGHT), _key(KEY_D), _btn(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"shift_up": [_key(KEY_UP), _key(KEY_X), _btn(JOY_BUTTON_A), _btn(JOY_BUTTON_RIGHT_SHOULDER)],      # Wii リモコンの 2 ボタン
		"shift_down": [_key(KEY_DOWN), _key(KEY_Z), _btn(JOY_BUTTON_X), _btn(JOY_BUTTON_LEFT_SHOULDER)],  # Wii リモコンの 1 ボタン
		"pause": [_key(KEY_ESCAPE), _key(KEY_P), _btn(JOY_BUTTON_START)],
		"sound_toggle": [_key(KEY_M)],
		"view_toggle": [_key(KEY_V), _btn(JOY_BUTTON_BACK)],                                            # 見た目の切り替え
		# メニュー
		"menu_up": [_key(KEY_UP), _btn(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"menu_down": [_key(KEY_DOWN), _btn(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"menu_accept": [_key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_SPACE), _key(KEY_X), _btn(JOY_BUTTON_A), _btn(JOY_BUTTON_START)],
	}
	for name in actions:
		ProjectSettings.set_setting("input/" + name, {"deadzone": 0.5, "events": actions[name]})
	ProjectSettings.save()
	quit()
