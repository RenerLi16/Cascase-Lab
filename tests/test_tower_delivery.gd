extends "res://tests/test_ui_improvements.gd"

# Run the established delivery/source coverage independently of the retired access-code UI fixture.
func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://build/tower-controls/delivery")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	UIkit.reduced_motion = true
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	await source_checks()
	print("TOWER DELIVERY: %d checks, %d failures" % [checks,failures])
	app.queue_free()
	await settle()
	quit(0 if failures == 0 else 1)
