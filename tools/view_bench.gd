extends SceneTree
## 見た目ごとの 3D 表示の組み立てにかかる時間を測る (画面なし)。
## 実行: godot --headless --path . -s tools/view_bench.gd

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: Node = main.get_node("World")
	seed(1)
	var r := Race.new()
	for i in 600:
		r.update(1.0 / 60.0)
	for v in world.VIEWS:
		world.set_view(v)
		var t0 := Time.get_ticks_usec()
		for i in 120:
			r.update(1.0 / 60.0)
			world.render(r, i / 60.0)
		print("%s: %.2f ms/frame" % [v, (Time.get_ticks_usec() - t0) / 1000.0 / 120.0])
	quit()
