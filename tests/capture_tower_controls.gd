extends "res://tests/test_presentation.gd"

var frames := 0
var recording := false
var panel: Rect2
var frames_dir := ProjectSettings.globalize_path("res://build/tower-controls/frames")

func capture(label: String, area := Rect2()) -> void:
	await settle(3)
	RenderingServer.force_draw()
	var img := root.get_texture().get_image()
	img.save_png(capture_dir+"/"+label+".png")
	if area.has_area(): img.get_region(Rect2i(area)).save_png(capture_dir+"/"+label+"-close.png")
	for control in descendants(app,"Button"):
		if control is TowerActionButton and control.kind == "MONITOR" and control.is_visible_in_tree():
			img.get_region(Rect2i(control.get_global_rect().grow(4))).save_png(capture_dir+"/"+label+"-control.png")

func hold(count: int) -> void:
	for i in count:
		await create_timer(1.0/15).timeout
		if recording:
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(frames_dir+"/%04d.png" % frames)
			frames += 1

func mouse(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	root.push_input(e)
	await settle(2)

func move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	root.push_input(e)
	await settle(2)

func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://docs/screenshots/tower-controls/after")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	DirAccess.make_dir_recursive_absolute(frames_dir)
	UIkit.reduced_motion = true
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		for chinese in [false,true]:
			FirstPlayText.chinese = chinese
			root.content_scale_size = viewport_size
			root.size = viewport_size
			var tag := str(viewport_size.x)+("-zh" if chinese else "-en")
			app = load("res://scenes/Main.tscn").instantiate()
			root.add_child(app)
			app._start_normal()
			app.session.phase = GameManager.Phase.ACTIONS
			app._render()
			app._select_shelter("E")
			await settle(8)
			panel = app.inspector.get_global_rect()
			var controls: Array = []
			for child in descendants(app,"Button"):
				if child is TowerActionButton: controls.append(child)
			check(controls.size() == 3,"Three tower controls")
			for control in controls:
				check(Rect2(panel.position+Vector2(20,20),panel.size-Vector2(40,40)).encloses(control.get_global_rect()),tag+" controls fit inspector")
				var desc: Label = control.face.get_node("Description")
				check(desc.position.y+desc.size.y < control.size.y-10,tag+" description fits face")
			var button: TowerActionButton = controls[1]
			recording = viewport_size.x == 1440 and not chinese
			await move(Vector2(10,400))
			await capture(tag+"-idle",panel)
			await hold(12)
			UIkit.reduced_motion = false
			await move(button.get_global_rect().get_center())
			await hold(4)
			await capture(tag+"-hover",panel)
			check(not is_instance_valid(app.source_picker) and app.session.state.total_supply() == 6,"Hover never selects or spends")
			await hold(7)
			await move(Vector2(10,400))
			button.grab_focus()
			await capture(tag+"-focus",panel)
			await hold(10)
			var at := button.get_global_rect().get_center()
			await mouse(at,true)
			check(button.travel == 3,"Real pointer down moves only face three pixels")
			check(app.session.state.total_supply() == 6 and not is_instance_valid(app.source_picker),"Press does not spend or select before release")
			await capture(tag+"-pressed",panel)
			await hold(7)
			await mouse(at,false)
			await capture(tag+"-selected",app.source_picker.get_global_rect())
			check(app.session.state.total_supply() == 6 and not app.session.state.shelters.E.is_monitored,"Selected action is not applied")
			await hold(12)
			app.source_picker.choose("H")
			await capture(tag+"-preview",app.source_picker.get_global_rect())
			check(app.session.state.total_supply() == 6,"Source preview spends nothing")
			await hold(12)
			app.source_picker.confirm_selection()
			check(app.session.state.total_supply() == 5 and app.session.state.shelters.E.monitor_known_pressure == -1,"Confirmation spends once, pressure stays hidden in transit")
			await hold(30)
			await wait_delivery()
			UIkit.reduced_motion = true
			app._select_shelter("E")
			await settle(5)
			await capture(tag+"-disabled",app.inspector.get_global_rect())
			for child in descendants(app,"Button"):
				if child is TowerActionButton: check(Rect2(panel.position+Vector2(20,20),panel.size-Vector2(40,40)).encloses(child.get_global_rect()),tag+" disabled stack fits inner inspector")
			check(app.session.state.shelters.E.monitor_known_pressure == -1,"Delivery installs a pending Monitor without revealing pressure")
			await capture(tag+"-map-label",Rect2(app.board.title_rects.E.position-Vector2(4,4),Vector2(app.board.title_rects.E.size.x+8,64)))
			await hold(15)
			recording = false
			app.queue_free()
			await settle()
	FirstPlayText.chinese = false
	print("TOWER VISUAL/INPUT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
