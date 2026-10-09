extends Node

# Dedicated synthetic test scene. Excluded from regular game exports.
var now := 1000
var app: Control
var failures: Array = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func wait_until(predicate: Callable, seconds: float = 15) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(0.05).timeout
	return predicate.call()

func report(stage: String) -> void:
	var result := JSON.stringify({"stage":stage,"failures":failures,"status":StudySync.status_text()})
	JavaScriptBridge.eval("(()=>{let e=document.getElementById('test-result');if(!e){e=document.createElement('pre');e.id='test-result';e.style='position:absolute;left:0;top:0;z-index:99;background:white;color:black';document.body.appendChild(e)}e.textContent="+JSON.stringify(result)+";})()")

func _ready() -> void:
	if not OS.has_feature("web"): return
	if JavaScriptBridge.eval("localStorage.getItem('"+StudySync.storage_key+".marker')") == "recover":
		check(await wait_until(func(): return not StudySync.sessions.is_empty() and StudySync.sessions.back().closed),"Refresh retries interrupted upload")
		check(StudySync.sessions.back().pending.is_empty(),"Refresh pending queue acknowledged")
		report("recovered")
		return
	app=load("res://scenes/Main.tscn").instantiate()
	add_child(app)
	check(app.find_child("AccessCodeEntry",true,false) == null,"No access-code field in exported game")
	check(not DevGate.is_open(),"Web Dev Mode locked initially")
	app._start_dev("riverside_01_v3")
	check(app.session == null,"Locked Dev Mode cannot create a sandbox")
	if OS.has_feature("participant"):
		check(not DevGate.available(),"Participant Dev Mode unavailable")
	var title = app.title_screen
	title._on_play()
	var first = app.practice if app.practice != null else app.mission_session
	title._on_play()
	check(first == (app.practice if app.practice != null else app.mission_session),"Repeated Play handled once")
	if app._practice_enabled():
		check(app.practice != null and app.session == null,"Play enters existing introduction/practice directly")
		check(StudySync.sessions.is_empty(),"Practice creates no server session")
		app.practice.finished.emit("synthetic-browser-test")
	else:
		check(app.session != null and app.practice == null,"Participant Play starts normal flow with practice approval unchanged")
	check(app.session != null and not app.session.is_sandbox(),"Normal gameplay started")
	app.session.configure_condition(GameManager.InterventionType.DIRECT_RECOMMENDATION)
	app.session._support_clock=func(): return now
	check(await wait_until(func(): return StudySync.active.credential!=""),"Browser session credential and CORS")
	app.session.start_private()
	for index in 3:
		app.session.open_private_form()
		app.session.submit_belief(PlayerBelief.new("E","VERIFY","E",4,"gather more information"))
	check(await wait_until(func(): return not app.session.support_message.is_empty()),"Browser intervention retrieval")
	check(app.session.phase==GameManager.Phase.DISCUSSION and not app.session.support_shown,"No early display in browser")
	now+=120000
	app.session.tick_discussion()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(app.session.support_shown and app.session.support_seconds_remaining()==15,"Browser actual display begins pause")
	check(app.session.support_message.get("provider","")=="mock","Browser mock label")
	check(await wait_until(func(): return StudySync.active.pending.is_empty()),"Browser incremental save acknowledged")
	StudySync.base_url="http://127.0.0.1:1"
	app.session.logger.record(1,"BROWSER_INTERRUPTED_UPLOAD_TEST")
	check(await wait_until(func(): return StudySync.status=="Offline / unsent records"),"Browser offline indicator")
	check(StudySync.storage_ok,"Browser durable localStorage available")
	JavaScriptBridge.eval("localStorage.setItem('"+StudySync.storage_key+".marker','recover')")
	report("ready-to-refresh")
