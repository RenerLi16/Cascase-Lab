extends SceneTree

# Real game client -> localhost backend -> QwenProvider whose HTTP transport is a recording fake.
# Started by backend/tests/test_no_dispatch.py, which inspects the intercepted outbound requests.
# Never contacts Alibaba. Do not run directly.
const SENTINEL := "SENTINEL-DISPATCH-7F3A-UNIQUE"
const SENTINEL_TIME := "SENTINEL-TIME-0915"
var checks := 0
var failures := 0
var now := 1000
var client: Node
var legacy_sentences: Array = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_until(predicate: Callable, seconds: float = 15) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.02).timeout
	return predicate.call()

# An older scenario file that still carries the retired dispatches plus unique sentinels.
func legacy_scenario() -> ScenarioData:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenarios/scenario_01.json"))
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://backend/tests/legacy_dispatch_fixture.json"))
	var reports: Array = fixture.retired_public_intel.riverside_01_v2.duplicate(true)
	reports.append({"round":2,"time":SENTINEL_TIME,"text":SENTINEL})
	raw["public_intel"] = reports
	for group: Array in fixture.retired_public_intel.values():
		for report: Dictionary in group: legacy_sentences.append(report.text)
	var scenario := ScenarioData.from_dictionary(raw)
	check(scenario != null and scenario.get("public_intel") == null,"Legacy scenario loads; deprecated reports ignored")
	return scenario

func clean(text: String) -> bool:
	if text.contains(SENTINEL) or text.contains(SENTINEL_TIME) or text.contains("public_intel") or text.contains("PUBLIC_INTEL") or text.contains("public_reports"): return false
	for sentence: String in legacy_sentences:
		if text.contains(sentence): return false
	return true

func play(condition: GameManager.InterventionType) -> Dictionary:
	var mission := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE)
	mission.current = GameManager.new(legacy_scenario(),condition,func(): return now)
	var game := mission.current
	client.attach(mission)
	check(await wait_until(func(): return client.active.credential != ""),"Session started on the backend")
	var record := {"condition":game.condition_name(),"session_id":mission.session_id,"contexts":[],"messages":[]}
	for round_number in 2:
		check(clean(JSON.stringify(game.logger.to_array())),"No dispatch in round %d events" % (round_number+1))
		game.start_private()
		for index in 3:
			game.open_private_form()
			check(game.submit_belief(PlayerBelief.new("E","VERIFY","E",4,"gather more information")),"Private response accepted")
		record.contexts.append(game.frozen_support_context.duplicate(true))
		check(clean(JSON.stringify(game.frozen_support_context)),"Frozen context has no dispatch data")
		if condition != GameManager.InterventionType.NONE:
			check(await wait_until(func(): return not game.support_message.is_empty(),30),"Intervention returned")
			check(game.support_message.get("provider","") == "qwen" and game.support_message.get("context_version","") == SupportContext.VERSION,"Message came through the intercepted Qwen path at the current context version")
		now += GameManager.DISCUSSION_SECONDS*1000
		game.tick_discussion()
		check(game.mark_support_shown(),"Support displayed")
		record.messages.append(game.support_message.get("text",""))
		now += SupportLibrary.PAUSE_SECONDS*1000
		check(game.proceed_to_actions(),"Actions after the reading pause")
		if round_number == 0:
			# Real, permitted evidence for the next context: a dated Verify snapshot and a Monitor.
			for kind in ["VERIFY","MONITOR"]:
				var funding: Array[String] = ["A"]
				check(game.dispatch_action(kind,"E",funding).ok,kind+" dispatched")
				check(game.complete_delivery(game.run_token),kind+" delivered")
		check(game.begin_resolution() and game.apply_resolution(game.run_token) and game.finish_resolution(game.run_token),"Round resolves")
		game.next_round()
	check(await wait_until(func(): return client.active.pending.is_empty(),20),"Automatic saving acknowledged every record")
	var exported := mission.export_dictionary()
	check(exported.schema_version == GameManager.EXPORT_SCHEMA and exported.context_version == SupportContext.VERSION,"Manual export identifies the no-dispatch version")
	check(clean(JSON.stringify(exported)) and clean(JSON.stringify(client.recovery_export())),"Manual and recovery exports carry no dispatch data")
	return record

func run() -> void:
	client = root.get_node("StudySync")
	client.outbox_path = OS.get_environment("CASCADE_TEST_OUTBOX")
	client.base_url = OS.get_environment("CASCADE_TEST_URL")
	client.enabled = true
	client.set_process(true)
	ProjectSettings.set_setting("cascade/support_provider","backend")
	var sessions: Array = []
	for condition in [GameManager.InterventionType.DIRECT_RECOMMENDATION,GameManager.InterventionType.CONSTRUCTIVE_DISSENT,GameManager.InterventionType.NONE]:
		sessions.append(await play(condition))
	client.finish("completed")
	check(await wait_until(func(): return client.sessions.all(func(s): return s.closed),20),"Every session closed and uploaded")
	var file := FileAccess.open(OS.get_environment("CASCADE_TEST_REPORT"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"sessions":sessions,"sentinel":SENTINEL,"sentinel_time":SENTINEL_TIME,"context_version":SupportContext.VERSION}))
	file.close()
	print("OUTBOUND CONTEXT CLIENT TESTS: %d checks, %d failures" % [checks,failures])
	client._unbind()
	quit(0 if failures == 0 else 1)
