extends "res://tests/test_ui.gd"

func run() -> void:
	var sync := root.get_node("StudySync")
	# Invoke with --offline-tests: never load a historical outbox or start network I/O.
	check(not sync.enabled and sync.sessions.is_empty(),"Test uses an empty offline outbox")
	if sync.enabled or not sync.sessions.is_empty():
		quit(1)
		return
	sync.outbox_path = "/tmp/cascade-practice-isolation-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	sync.enabled = true
	sync.set_process(false)
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app._begin_play()
	await app.practice.deliver("VERIFY","E")
	await app.practice.deliver("ISOLATE","C-E")
	check(sync.game == null and sync.mission == null and sync.observed_logger == null,"Practice cannot bind to automatic saving")
	check(sync.sessions.is_empty() and sync.active.is_empty() and not FileAccess.file_exists(sync.outbox_path),"Enabled saving still creates no practice records")
	await click("Start measured session")
	check(sync.game == app.session and sync.mission == app.mission_session,"Fresh measured game attaches to automatic saving")
	check(sync.sessions.size() == 1 and FileAccess.file_exists(sync.outbox_path),"Measured session persists immediately")
	check(sync.game.support_provider is BackendSupportProvider,"Qwen backend adapter remains connected after practice")
	check(not JSON.stringify(sync.sessions).contains("practice_demo"),"Saved measured records exclude practice scenario and actions")
	check(app.session.state.total_supply() == 6 and app.session.private_surveys.is_empty(),"Fresh stock and private responses after practice")
	app._show_main_menu()
	sync.enabled = false
	DirAccess.remove_absolute(sync.outbox_path)
	app.queue_free()
	await settle()
	print("PRACTICE ISOLATION TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
