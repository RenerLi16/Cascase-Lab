extends SceneTree
# Launched by Python against an isolated localhost server; No AI, no paid calls.
const Fixture = preload("res://tests/post_form_fixture.gd")
var now := 0
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var client := root.get_node("StudySync")
	client.outbox_path = OS.get_environment("CASCADE_TEST_OUTBOX")
	client.base_url = OS.get_environment("CASCADE_TEST_URL")
	client.enabled = true
	client.set_process(true)
	var mission := MissionSession.new()
	client.attach(mission)
	for scenario_number in 4:
		var game := mission.current
		game._support_clock = func(): return now
		for rnd in 3:
			game.start_private()
			for player in 3:
				game.open_private_form()
				game.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access"))
			now += 120000
			game.tick_discussion()
			game.mark_support_shown()
			now += 15000
			game.proceed_to_actions()
			game.begin_resolution()
			game.apply_resolution(game.run_token)
			game.finish_resolution(game.run_token)
			game.next_round()
			while game.post_form_kind() != "":
				client.finish("completed")
				check(client.active.closing == "","No completion before final required form")
				game.open_private_form()
				var answers := Fixture.answers(game)
				for q in game.post_form_questions():
					if not q.has("options"): answers[q.id] = ("HTTP_FORM_CANARY"+"好🧭".repeat(600)).substr(0,int(q.max_length))
				check(game.submit_post_form(game.post_form_key(),answers),"Maximum-length Unicode answer through production saving path")
		if scenario_number < 3:
			check(mission.advance(),"Advance after complete forms")
			client.attach(mission)
	var deadline := Time.get_ticks_msec()+30000
	while not client.active.closed and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(client.active.closed and client.active.pending.is_empty(),"All forms acknowledged before remote completion")
	check(mission.is_complete(),"Four-scenario client completed")
	client._unbind()
	print("FORM BACKEND CLIENT TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
