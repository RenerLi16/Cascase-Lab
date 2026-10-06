extends SceneTree

var app: Control
var capture_dir := "/tmp/cascade-first-play/before"
func _initialize() -> void:
	call_deferred("run")
func shot(label: String) -> void:
	for frame in 8: await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir+"/"+label+".png")
func run() -> void:
	if OS.get_environment("CAPTURE_DIR") != "": capture_dir = OS.get_environment("CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	await shot("opening-1440")
	app._start_dev("riverside_01_v2")
	await shot("roads-overview-1440")
	app._select_shelter("E")
	await create_timer(0.7).timeout
	await shot("roads-closeup-1440")
	app.queue_free()
	quit()
