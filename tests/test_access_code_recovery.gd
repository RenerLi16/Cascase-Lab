extends SceneTree

# Run via backend/tests/test_native_client.py (it supplies a local backend that requires an access code).
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_until(predicate: Callable, seconds: float = 10) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.02).timeout
	return predicate.call()

func run() -> void:
	var client: Node = root.get_node("StudySync")
	client.outbox_path=OS.get_environment("CASCADE_TEST_OUTBOX")
	client.base_url=OS.get_environment("CASCADE_TEST_URL")
	client.enabled=true
	client.set_process(true)
	client.access_code="wrong-code-123456"
	var mission := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE)
	client.attach(mission)
	mission.current.start_private()
	check(await wait_until(func(): return client.status=="Save error — access code rejected"),"Wrong code is visibly rejected")
	check(client.active.credential=="" and client.active.pending.size()>0,"Records stay queued while the code is wrong")
	client.set_access_code("  synthetic-code-123  ")
	check(await wait_until(func(): return client.active.credential!="" and client.active.pending.is_empty()),"Corrected code starts the same session and uploads queued records")
	check(not JSON.stringify(client.sessions).contains("synthetic-code-123"),"Accepted code is not kept in the outbox")
	print("ACCESS CODE RECOVERY TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
