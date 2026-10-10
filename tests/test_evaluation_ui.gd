extends "res://tests/test_presentation.gd"

const Fixture = preload("res://tests/post_form_fixture.gd")
const LONG_TEXT := "I considered the public map, road and bridge connections, supply access, and uncertainty. "

func round_summary() -> void:
	app.session.start_private()
	for player in 3:
		app.session.open_private_form()
		app.session.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access"))
	support_time += 120000
	app.session.tick_discussion()
	await settle(5)
	support_time += 15000
	app.session.proceed_to_actions()
	app.session.begin_resolution()
	app.session.apply_resolution(app.session.run_token)
	app.session.finish_resolution(app.session.run_token)
	await settle()

func fill_visible_form(maximum: bool) -> void:
	for picker: OptionButton in descendants(app,"OptionButton"):
		picker.select(1)
		picker.item_selected.emit(1)
	for edit: TextEdit in descendants(app,"TextEdit"):
		edit.text = LONG_TEXT.repeat(15) if maximum else "Not sure"
		edit.text_changed.emit()
	await settle()

func run() -> void:
	capture_dir = "/private/tmp/cascade-evaluation-ui"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	UIkit.reduced_motion = true
	for viewport_size in [Vector2i(1440,900),Vector2i(1200,800)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		app._start_normal()
		app.session._support_clock = func(): return support_time
		for rnd in 2:
			await round_summary()
			Fixture.advance(app.session)
		await round_summary()
		await click("Individual round evaluations")
		var tag := str(viewport_size.x)
		check(app.board == null and descendants(app,"TextEdit").is_empty(),"Opaque handoff clears prior inputs and map")
		await snapshot(tag+"-round-handoff")
		check_layout(tag+"-round-handoff")
		for player in 3:
			await click("Open my form")
			check(descendants(app,"OptionButton").size() == 4,"No AI: four non-AI options")
			check(descendants(app,"TextEdit")[0].text == "","Round form starts blank")
			check(button_containing("Submit & pass").disabled,"Blank form cannot submit")
			if player == 0:
				await snapshot(tag+"-round-blank")
				await fill_visible_form(true)
				check(app.session.post_form_draft.explanation.length() == 600,"Long paste is limited to 600 characters")
				var draft: Dictionary = app.session.post_form_draft.duplicate(true)
				await click("Hide survey")
				app._select_shelter("A")
				await click("Expand survey")
				check(app.session.post_form_draft == draft,"Map inspection preserves draft")
				app._render()
				await settle()
				check(descendants(app,"TextEdit")[0].text == draft.explanation,"Rerender restores draft")
				app._request_leave(app._show_main_menu)
				await click("Cancel")
				check(app.session.post_form_draft == draft,"Cancel navigation preserves answers")
				var scroller: ScrollContainer = app.survey_content.get_child(0)
				scroller.ensure_control_visible(button_containing("Submit & pass"))
				await snapshot(tag+"-round-long-bottom")
				check_layout(tag+"-round-long")
				check(button_containing("Submit & pass").get_global_rect().end.y <= scroller.get_global_rect().end.y+1,"Submit reachable by scrolling")
			else: await fill_visible_form(false)
			await click("Submit & pass")
			check(descendants(app,"TextEdit").is_empty() and app.board == null,"No prior player's answers on handoff")
		check(app.session.phase == GameManager.Phase.SCENARIO_REASONING_GATE,"Final round leads to reasoning before results")
		await snapshot(tag+"-reasoning-handoff")
		check_layout(tag+"-reasoning-handoff")
		for player in 3:
			await click("Open my form")
			check(descendants(app,"TextEdit").size() == 4 and descendants(app,"OptionButton").is_empty(),"Separate four-question scenario form")
			for edit in descendants(app,"TextEdit"): check(edit.text == "","Reasoning starts blank")
			if player == 0: await snapshot(tag+"-reasoning-blank")
			await fill_visible_form(player == 0)
			if player == 0:
				for answer in app.session.post_form_draft.values(): check(answer.length() == 1000,"Each answer capped at 1000")
				var scroller: ScrollContainer = app.survey_content.get_child(0)
				scroller.ensure_control_visible(button_containing("Submit & pass"))
				await snapshot(tag+"-reasoning-long-bottom")
				check_layout(tag+"-reasoning-long")
			await click("Submit & pass")
		check(app.session.phase == GameManager.Phase.RESULTS,"All six final forms enable results")
		app.queue_free()
		await settle()
	# Eligibility in the actual form controls, with synthetic display metadata only.
	for variant in ["qwen","mock","unavailable"]:
		app = load("res://scenes/Main.tscn").instantiate()
		root.add_child(app)
		app._start_normal()
		app.session.configure_condition(GameManager.InterventionType.DIRECT_RECOMMENDATION)
		app.session._support_clock = func(): return support_time
		app.session.start_private()
		for player in 3:
			app.session.open_private_form()
			app.session.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access"))
		app.session.support_message = {"provider":variant,"text":"Fixture: Synthetic display for UI verification only.","template_id":"fixture","version":"fixture-1"}
		support_time += 120000
		app.session.tick_discussion()
		await settle(5)
		support_time += 15000
		app.session.proceed_to_actions()
		app.session.begin_resolution()
		app.session.apply_resolution(app.session.run_token)
		app.session.finish_resolution(app.session.run_token)
		app.session.next_round()
		app.session.open_private_form()
		await settle()
		check(descendants(app,"OptionButton").size() == (6 if variant == "qwen" else 4),"AI controls correctly shown: "+variant)
		var influence: OptionButton = app.find_child("influence",true,false)
		check(influence.item_count == (7 if variant == "qwen" else 6),"AI message influence option: "+variant)
		if variant == "qwen":
			var scroller: ScrollContainer = app.survey_content.get_child(0)
			scroller.ensure_control_visible(button_containing("Submit & pass"))
			await snapshot("1200-ai-questions")
			check_layout("ai-questions")
		app.queue_free()
		await settle()
	print("EVALUATION UI TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
