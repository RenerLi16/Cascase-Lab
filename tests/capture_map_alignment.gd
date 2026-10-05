extends "res://tests/test_presentation.gd"

func run() -> void:
	var phase := OS.get_environment("ALIGNMENT_PHASE")
	if phase == "": phase = "before"
	capture_dir = ProjectSettings.globalize_path("res://docs/screenshots/map-alignment/"+phase)
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		for entry in ScenarioData.registry().scenarios:
			app._start_dev(entry.id)
			await settle(8)
			app.board.dev_mode = false
			await snapshot(str(viewport_size.x)+"-"+entry.id+"-overview")
			app.board._move_camera(Vector2(500,350),2.6,false)
			await snapshot(str(viewport_size.x)+"-"+entry.id+"-close")
		app.queue_free()
		await settle()
	quit()
