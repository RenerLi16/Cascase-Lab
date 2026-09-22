extends "res://tests/test_presentation.gd"

func run() -> void:
	capture_dir = "/private/tmp/cascade-redesign"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		app.session._support_clock = func(): return support_time
		await snapshot("%d-overview" % viewport_size.x)
		check_layout("overview")
		for id in app.session.state.shelters:
			app._select_shelter(id)
			await create_timer(0.65).timeout
			var rect: Rect2 = app.board.building_rect(id)
			check(Rect2(Vector2.ZERO,app.board.size).encloses(rect.grow(25)),"Focused frame and label fit: "+id)
			check(app.board.hit_test(rect.get_center())==id,"Focused building remains selectable: "+id)
			if id == "E":
				await snapshot("%d-building" % viewport_size.x)
				check_layout("building")
		app._clear_selection()
		await create_timer(0.65).timeout
		app.session.start_private()
		app.session.open_private_form()
		await settle()
		var fields := descendants(app,"OptionButton")
		choose(fields[0],"E")
		choose(fields[1],"VERIFY")
		choose(fields[2],"E")
		choose(fields[3],"4")
		await snapshot("%d-survey" % viewport_size.x)
		check_layout("survey")
		check(app.survey_content.size.y > 250,"Expanded survey has room for the actual form")
		for field: OptionButton in fields:
			check(app.survey_drawer.get_global_rect().encloses(field.get_global_rect()),"Survey fields fit inside expanded drawer")
		await click("Hide survey")
		await create_timer(0.35).timeout
		app._select_shelter("E")
		await create_timer(0.65).timeout
		await snapshot("%d-survey-hidden" % viewport_size.x)
		check_layout("survey-hidden")
		await click("Expand survey")
		await create_timer(0.35).timeout
		check(fields[0].get_selected_metadata()=="E" and fields[3].get_selected_metadata()=="4","Private draft survives map inspection")
		await click("Submit & pass screen")
		for index in 2:
			app.session.open_private_form()
			app.session.submit_belief(PlayerBelief.new("E","VERIFY","E",4,""))
		check(app.session.discussion_seconds_remaining()==120,"Discussion starts at two minutes")
		var deadline: int = app.session.discussion_deadline_ms
		app._select_shelter("E")
		await settle()
		check(app.session.discussion_deadline_ms==deadline,"Inspection never resets discussion timer")
		support_time += 34000
		await settle()
		check(app.timer_label.text=="1:26","Header displays real remaining time")
		app._clear_selection()
		await create_timer(0.65).timeout
		await snapshot("%d-discussion" % viewport_size.x)
		support_time += 86000
		await settle(8)
		check(app.session.phase==GameManager.Phase.INTERVENTION,"Discussion expires into support exactly once")
		await snapshot("%d-support" % viewport_size.x)
		check_layout("support")
		support_time += 15000
		await settle()
		await click("Proceed to actions")
		app._select_shelter("E")
		await create_timer(0.65).timeout
		await snapshot("%d-decisions" % viewport_size.x)
		check_layout("decisions")
		app._clear_selection()
		await create_timer(0.65).timeout
		await map_click("E-F",true)
		await snapshot("%d-road" % viewport_size.x)
		check_layout("road")
		await click("ISOLATE")
		await snapshot("%d-confirm" % viewport_size.x)
		check_layout("confirm")
		app._close_modal()
		app.session.phase = GameManager.Phase.INTERVENTION
		for id in SupportLibrary.TEMPLATES:
			app.session.support_message = {"text":"\n".join(SupportLibrary.TEMPLATES[id]).replace("%s","E-F"),"template_id":id,"version":SupportLibrary.VERSION}
			app._render()
			await settle(10)
			check(app.support_card.get_parent().size.y==440,"All support templates share a fixed card height: "+id)
			check(app.support_card.get_global_rect().end.y < app.support_continue.global_position.y,"All support templates fit above continue: "+id)
		app.queue_free()
		await settle()
	print("REDESIGN TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
