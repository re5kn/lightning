extends SceneTree
## ゲームロジックだけを画面なしで動かす簡単な確認 (自動操作で 1 プレイ)。
## 実行: godot --headless --path . -s tools/sim_test.gd

func _init() -> void:
	seed(1)
	var r := preload("res://scripts/race.gd").new()
	var counts := {}
	r.sound.connect(func(n): counts[n] = counts.get(n, 0) + 1)
	var dt := 1.0 / 60.0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var max_gear := 0
	while true:
		frames += 1
		if frames % 30 == 0:
			if r.gear < r.max_g: r.shift_up()
			if r.sides == 0: r.move_lane(1 if randf() < 0.5 else -1)
		if r.update(dt): break
		max_gear = maxi(max_gear, r.gear)
	var us := Time.get_ticks_usec() - t0
	print("frames=%d  avg_update=%.3f ms  score=%d  dist=%.1f  max_gear=%d  streams=%d" % [frames, us / 1000.0 / frames, r.score, r.dist / 57.0, max_gear, r.streams.size()])
	print(counts)
	quit()
