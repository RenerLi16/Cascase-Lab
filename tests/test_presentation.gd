extends "res://tests/test_ui.gd"

var capture_dir := "/private/tmp/cascade-presentation"

func snapshot(label: String) -> void:
	await settle(5)
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(capture_dir+"/"+label+".png")

func check_layout(label: String) -> void:
	var bounds := app.get_global_rect()
	for node: Control in descendants(app,"Control"):
		if not node.is_visible_in_tree(): continue
		var ancestor := node.get_parent()
		var scroll_content := false
		while ancestor != null and ancestor != app:
			if ancestor is ScrollContainer: scroll_content = true
			ancestor = ancestor.get_parent()
		if scroll_content: continue
		var rect := node.get_global_rect()
		check(rect.position.x >= -1 and rect.end.x <= bounds.end.x+1,label+" fits horizontally: "+str(node.name))
		check(rect.position.y >= -1 and rect.end.y <= bounds.end.y+1,label+" fits vertically: "+str(node.name))

func public_pixels() -> PackedByteArray:
	app.board.queue_redraw()
	await settle()
	RenderingServer.force_draw()
	return root.get_texture().get_image().get_data()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		var card_rect := Rect2()
		for condition in 3:
			var tag := "%d-%d" % [viewport_size.x,condition]
			app = load("res://scenes/Main.tscn").instantiate()
			root.add_child(app)
			app.session._support_clock = func(): return support_time
			app.session.configure_condition(condition)
			await snapshot(tag+"-observe")
			check_layout(tag+"-observe")
			if condition == 0 and DisplayServer.get_name() != "headless":
				var first := await public_pixels()
				app.session.state.shelters.E.zombie_pressure = 0
				app.session.state.shelters.B.zombie_pressure = 1
				var second := await public_pixels()
				check(first == second,"Hidden P0/P1 changes do not change any public pixels")
				app.session.state.shelters.E.zombie_pressure = 1
				app.session.state.shelters.B.zombie_pressure = 0
			for round_number in 3:
				await click("Private judgment")
				check(app.board == null,"Handoff removes public board and prior form")
				await snapshot(tag+"-r%d-handoff" % round_number)
				check_layout(tag+"-handoff")
				for index in 3:
					await click("Open my form")
					var pickers := descendants(app,"OptionButton")
					check(pickers.size()==5,"Private form preserves five fields")
					choose(pickers[0],"E-F" if index==0 else "E")
					choose(pickers[1],"VERIFY")
					choose(pickers[2],"E")
					choose(pickers[3],str(index+2))
					if index==0:
						await snapshot(tag+"-r%d-form" % round_number)
						check_layout(tag+"-form")
					await click("Submit & pass screen")
				await click("Finish initial discussion")
				await snapshot(tag+"-r%d-support" % round_number)
				check_layout(tag+"-support")
				check(app.support_card.get_global_rect().end.y < app.support_continue.global_position.y,"All support text fits above continue")
				if round_number==0:
					var rect: Rect2 = app.support_card.get_parent().get_global_rect()
					if condition==0: card_rect = rect
					else: check(rect == card_rect,"Conditions have identical note bounds")
				support_time += 15000
				await settle()
				await click("Proceed to actions")
				if round_number==0:
					await map_click("E")
					await snapshot(tag+"-actions")
					await dispatch("VERIFY","E",["H"])
					await dispatch("MONITOR","E",["A"])
					await dispatch("SHIELD","F",["H"])
					await map_click("E-F",true)
					await click("ISOLATE")
					await snapshot(tag+"-isolation")
					check_layout(tag+"-isolation")
					await click("Confirm delivery")
					await create_timer(2.2).timeout
				await click("End round")
				await click("Resolve")
				await create_timer(2.0).timeout
				check(app.session.phase==GameManager.Phase.ROUND_COMPLETE,"Resolution finishes normally")
				if round_number==0:
					check(app.session.last_summary.newly_overrun==["E"],"Reveal cannot clear domain's newly lost list")
				await snapshot(tag+"-r%d-resolved" % round_number)
				await click("Results" if round_number==2 else "Next round")
			await snapshot(tag+"-results")
			check_layout(tag+"-results")
			app.queue_free()
			await settle()
	print("PRESENTATION TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
