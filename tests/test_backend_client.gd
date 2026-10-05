extends SceneTree

var checks := 0
var failures := 0
var now := 1000
var client: Node

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_until(predicate: Callable, seconds: float = 8) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.02).timeout
	return predicate.call()

func run() -> void:
	client=root.get_node("StudySync")
	client.outbox_path=OS.get_environment("CASCADE_TEST_OUTBOX")
	client.base_url="http://127.0.0.1:1"
	client.enabled=true
	client.set_process(true)
	ProjectSettings.set_setting("cascade/support_provider","backend")
	var mission := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE)
	var game := mission.current
	game._support_clock=func(): return now
	client.attach(mission)
	game.configure_condition(GameManager.InterventionType.DIRECT_RECOMMENDATION)
	game.start_private()
	check(await wait_until(func(): return client.status=="Offline / unsent records"),"Backend offline visibly retains pending events")
	check(FileAccess.file_exists(client.outbox_path) and client.active.pending.size()>0,"Queue retained on disk")
	client.base_url=OS.get_environment("CASCADE_TEST_URL")
	client.retry_at=0
	check(await wait_until(func(): return client.active.credential!=""),"Session credential acquired after reconnect")
	for index in 3:
		game.open_private_form()
		game.submit_belief(PlayerBelief.new("E","VERIFY","E",4,"gather more information"))
	check(await wait_until(func(): return not game.support_message.is_empty()),"Backend intervention returns asynchronously")
	check(game.support_message.get("provider","")=="mock","Backend mock distinctly identified")
	check(game.phase==GameManager.Phase.DISCUSSION and not game.support_shown,"Backend result not displayed before scheduled time")
	now+=120000
	game.begin_support()
	game.mark_support_shown()
	check(game.support_seconds_remaining()==15,"Backend result display starts 15-second pause")
	# Request the same identity twice after completion; server must reuse one result.
	var again: Dictionary = await client.request_support(game.frozen_support_context,game.condition_name(),game.intervention_identity)
	check(again==game.support_message,"Retry reuses exact completed message")
	check(await wait_until(func(): return client.active.pending.is_empty(),15),"All incremental records acknowledged")
	var session_id: String=client.active.session_id
	var secret: String=client.active.credential
	check(not JSON.stringify(client.recovery_export()).contains(secret),"Recovery export excludes session credentials")
	# A process/refresh interruption with unsent events is recovered from durable outbox.
	client.base_url="http://127.0.0.1:1"
	game.logger.record(1,"INTERRUPTED_UPLOAD_TEST")
	client.set_process(false)
	await wait_until(func(): return not client.busy)
	var recovered: Node=load("res://scripts/study_sync.gd").new()
	root.add_child(recovered)
	recovered.outbox_path=client.outbox_path
	recovered.base_url=OS.get_environment("CASCADE_TEST_URL")
	recovered._load_pending()
	recovered.enabled=true
	for saved in recovered.sessions: saved.closing="interrupted"
	recovered.set_process(true)
	check(await wait_until(func(): return recovered.sessions.back().closed,15),"Reload retries interrupted upload and records interruption")
	check(recovered.sessions.back().session_id==session_id,"Recovery retains same session identity")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(client.outbox_path))
	check(parsed.back().pending.is_empty() and parsed.back().closed,"Acknowledgments persisted locally")
	# Simulate unavailable durable storage and expose the limitation.
	recovered.storage_error=""
	recovered.outbox_path="/nonexistent/cascade/pending.json"
	recovered._persist()
	check(recovered.status_text().contains("persistence unavailable"),"Storage failure never claims reliable saving")
	print("BACKEND CLIENT TESTS: %d checks, %d failures" % [checks,failures])
	print("SYNTHETIC_SESSION_ID="+session_id)
	client._unbind()
	recovered.queue_free()
	quit(0 if failures==0 else 1)
