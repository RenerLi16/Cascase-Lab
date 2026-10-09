extends SceneTree

# Synthetic transport: verifies the default local-only public policy and durable records.
class LocalSync:
	extends "res://scripts/study_sync.gd"
	var calls: Array = []
	func _http(_method: int, path: String, payload: Dictionary = {}, _credential: String = "") -> Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		if path == "/v1/public-sessions":
			return {"code":200,"body":{"session_id":payload.session_id,"credential":"synthetic-public-credential","remote_records":false,"ai_available":false,"research_eligible":false,"record_mode":"public-demo"}}
		if path.ends_with("/completion"):
			return {"code":200,"body":{"status":payload.status,"last_seq":payload.last_seq}}
		return {"code":403,"body":{"error":"synthetic-forbidden"}}

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var client := LocalSync.new()
	root.add_child(client)
	client.outbox_path = "/tmp/cascade-local-public-"+Crypto.new().generate_random_bytes(6).hex_encode()+".json"
	client.enabled = true
	client.set_process(false)
	var mission := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.DIRECT_RECOMMENDATION)
	client.attach(mission)
	mission.current.start_private()
	var original_id: String = client.active.session_id
	await client._flush()
	check(client.active.credential != "" and client.calls.size() == 1,"Public bootstrap without a code")
	check(not client.calls[0].payload.has("access_code") and not client.calls[0].payload.metadata.has("research_eligible"),"No client access code or authorization flags")
	await client._flush()
	check(client.calls.size() == 1 and client.active.pending.size() > 0,"Local-only events never uploaded")
	check(client.status_text().contains("Saved on this device"),"Local saving clearly labelled")
	var result: Dictionary = await client.request_support({},"DIRECT_RECOMMENDATION",{"session":original_id,"scenario":"riverside_01_v3","round":1})
	check(result.error == "public_ai_unavailable" and client.calls.size() == 1,"Unavailable AI never sends intervention requests")
	client.finish("interrupted")
	await client._flush()
	check(client.active.closed and client.calls.back().payload.last_seq == 0,"Operational completion has no remote event sequence")
	check(not client.active.pending.is_empty(),"Completion preserves local records")
	var saved: Array = client.active.pending.duplicate(true)
	var recovered := LocalSync.new()
	root.add_child(recovered)
	recovered.outbox_path = client.outbox_path
	recovered._load_pending()
	check(recovered.sessions.size() == 1 and recovered.sessions[0].session_id == original_id,"Recovery preserves identity")
	check(recovered.sessions[0].pending == JSON.parse_string(JSON.stringify(saved)) and recovered.sessions[0].closed,"Recovery preserves all local records")
	check(not JSON.stringify(recovered.recovery_export()).contains("synthetic-public-credential"),"Export excludes credentials")
	check(not mission.research_submission().ok and mission.export_dictionary().record_mode == "public-demo","Public demo cannot be submitted as research")
	client._unbind()
	DirAccess.remove_absolute(client.outbox_path)
	client.queue_free()
	recovered.queue_free()
	print("PUBLIC LOCAL TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
