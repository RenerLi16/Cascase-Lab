extends "res://tests/test_ui.gd"

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	root.push_input(event)
	await settle()

func touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.index = 0
	event.pressed = down
	Input.parse_input_event(event)
	await settle()

func monitor_button() -> TowerActionButton:
	for button in descendants(app,"Button"):
		if button is TowerActionButton and button.kind == "MONITOR": return button
	return null

func run() -> void:
	UIkit.reduced_motion = true
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._start_normal()
	app.session.phase = GameManager.Phase.ACTIONS
	app._render()
	app._select_shelter("E")
	await settle(8)
	var button := monitor_button()
	button.grab_focus()
	await key(KEY_SPACE,true)
	check(button.travel == 3,"Keyboard down depresses face")
	check(not is_instance_valid(app.source_picker) and app.session.state.total_supply() == 6,"Keyboard down cannot dispatch")
	await key(KEY_SPACE,false)
	check(is_instance_valid(app.source_picker),"Keyboard release opens source picker")
	check(app.session.state.total_supply() == 6,"Keyboard selection spends nothing")
	app.source_picker.cancelled.emit()
	await settle()
	check(app.session.state.total_supply() == 6,"Cancel retains all supplies")
	button = monitor_button()
	button.grab_focus()
	check(button.glint == 0,"Reduced motion suppresses transient animation")
	check(button.has_focus(),"Reduced motion retains visible focus")
	Input.emulate_mouse_from_touch = true
	await touch(button.get_global_rect().get_center(),true)
	check(app.session.state.total_supply() == 6,"Touch down spends nothing")
	await touch(button.get_global_rect().get_center(),false)
	check(is_instance_valid(app.source_picker),"Touch selects the whole control")
	if is_instance_valid(app.source_picker):
		var picker = app.source_picker
		picker.choose("H")
		picker.confirm_selection()
		picker.confirm_selection()
		check(app.session.state.total_supply() == 5,"Repeated confirmation spends exactly once")
		await wait_delivery()
		app._select_shelter("E")
		await settle()
		button = monitor_button()
		check(button.disabled and button.reason == "MONITOR ACTIVE","Installed Monitor is unavailable with readable reason")
		await touch(button.get_global_rect().get_center(),true)
		await touch(button.get_global_rect().get_center(),false)
		check(not is_instance_valid(app.source_picker) and app.session.state.total_supply() == 5,"Disabled touch cannot select or spend")
	print("TOWER INPUT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
