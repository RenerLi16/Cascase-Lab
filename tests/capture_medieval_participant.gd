extends "res://tests/test_presentation.gd"

func run() -> void:
	capture_dir = ProjectSettings.globalize_path("res://build/medieval-review")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	UIkit.reduced_motion = true
	var registered: Array = ScenarioData.registry().development_default_order.duplicate()
	for id in registered:
		var order := registered.duplicate()
		order.erase(id)
		order.push_front(id)
		ProjectSettings.set_setting("cascade/scenario_order",order)
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		app._start_normal()
		app.session._support_clock = func(): return support_time
		app.session.start_private()
		for player in 3:
			app.session.open_private_form()
			app.session.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access"))
		support_time += 120000
		app.session.tick_discussion()
		await settle(8)
		support_time += 15000
		app.session.proceed_to_actions()
		await snapshot("overview-"+str(id))
		if id == "riverside_01_v2":
			for tower in ["A","C","G"]:
				app._select_shelter(tower)
				await snapshot("inspection-"+tower)
		app.queue_free()
		await settle()
	ProjectSettings.set_setting("cascade/scenario_order",[])
	quit()
