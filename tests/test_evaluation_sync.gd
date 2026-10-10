extends SceneTree
const Fixture = preload("res://tests/post_form_fixture.gd")

class RetrySync:
	extends "res://scripts/study_sync.gd"
	var committed: Dictionary = {}
	var lost_ack := false
	var completed := false
	var attempts := 0
	func _http(_method: int, path: String, payload: Dictionary = {}, _credential: String = "") -> Dictionary:
		if path == "/v1/public-sessions":
			return {"code":200,"body":{"session_id":payload.session_id,"credential":"fixture","remote_records":true,"ai_available":false}}
		if path.ends_with("/events"):
			assert(JSON.stringify(payload).to_utf8_buffer().size() < 71000)
			var ids: Array = []
			var has_form := false
			for event in payload.events:
				ids.append(event.event_id)
				if committed.has(event.event_id): assert(committed[event.event_id] == event)
				committed[event.event_id] = event.duplicate(true)
				if event.channel == "round_evaluation": has_form = true
			if has_form:
				attempts += 1
				if not lost_ack:
					lost_ack = true
					return {"code":0,"body":{}}
			return {"code":200,"body":{"acknowledged":ids}}
		completed = payload.status == "completed"
		return {"code":200,"body":{"status":payload.status}}

var checks := 0
var failures := 0
var now := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	ProjectSettings.set_setting("cascade/support_provider","mock")
	var client := RetrySync.new()
	root.add_child(client)
	client.enabled = true
	client.set_process(false)
	client.outbox_path = "/tmp/cascade-form-retry-"+Crypto.new().generate_random_bytes(6).hex_encode()+".json"
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
			client.finish("completed")
			check(client.active.closing == "","Cannot complete from round summary/forms")
			for player in 3:
				game.open_private_form()
				game.submit_post_form(game.post_form_key(),Fixture.answers(game,"Private retry canary"))
			if rnd == 2:
				for player in 3:
					client.finish("completed")
					check(client.active.closing == "","Final reasoning blocks completion, including P3")
					game.open_private_form()
					game.submit_post_form(game.post_form_key(),Fixture.answers(game,"Not sure"))
		if scenario_number < 3:
			mission.advance()
			client.attach(mission)
	check(client.sessions.size() == 1 and mission.is_complete() and client.active.closing == "completed","Only final required submission marks session complete")
	var exported := client.recovery_export()
	var pending: Array = exported.pending_uploads[0].pending.duplicate(true)
	check(pending.filter(func(e): return e.channel == "round_evaluation").size() == 36,"Outbox stores 36 round evaluations")
	check(pending.filter(func(e): return e.channel == "scenario_reasoning").size() == 12,"Outbox stores 12 reasoning forms")
	check(not JSON.stringify(pending.filter(func(e): return e.channel == "game")).contains("Private retry canary"),"Game channel excludes answers")
	var expected := pending.size()
	for _attempt in 100:
		for item in client.sessions: item.erase("retry_after")
		await client._flush()
		if client.active.closed: break
	check(client.lost_ack and client.attempts > 1,"Lost acknowledgment retried")
	check(client.committed.size() == expected,"Retries retain event identities without duplicates")
	check(client.completed and client.active.pending.is_empty() and client.active.closed,"Completion sent only after all acknowledgments")
	var persisted: Array = JSON.parse_string(FileAccess.get_file_as_string(client.outbox_path))
	check(persisted[0].closed and persisted[0].pending.is_empty(),"Acknowledgments persisted")
	# Local-only permission retains submitted forms in durable recovery records.
	client.active.remote_records = false
	client.active.closed = false
	client.active.closing = ""
	client.active.pending = pending.duplicate(true)
	client._persist()
	var recovered := RetrySync.new()
	root.add_child(recovered)
	recovered.outbox_path = client.outbox_path
	recovered._load_pending()
	check(recovered.sessions[0].pending.size() == expected,"Local-only forms survive reload with stable identities")
	check(JSON.stringify(recovered.recovery_export()).contains("Private retry canary"),"Recovery export preserves answers")
	client._unbind()
	client.queue_free()
	recovered.queue_free()
	DirAccess.remove_absolute(client.outbox_path)
	print("EVALUATION SYNC TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
