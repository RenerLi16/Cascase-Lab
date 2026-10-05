extends Node

# Never holds a provider key. These credentials authorize only one synthetic session.
# Saving and model traffic use distinct HTTPRequest nodes and independent retry loops.
var enabled := true
var sessions: Array = []
var active: Dictionary = {}
var mission: MissionSession
var game: GameManager
var observed_logger: EventLogger
var storage_ok := true
var storage_error := ""
var status := "Saved"
var busy := false
var retry_at := 0
var retry_count := 0
var heartbeat_at := 0
var base_url := "http://127.0.0.1:8787"
# Shared study access code for online builds. Sent only when starting a session, then discarded.
var access_code := ""
var outbox_path := "user://synthetic_pending_v1.json"
var storage_key := "cascade.synthetic.outbox.v1"

func _ready() -> void:
	base_url = str(ProjectSettings.get_setting("cascade/backend_url",base_url)).trim_suffix("/")
	outbox_path = str(ProjectSettings.get_setting("cascade/outbox_path",outbox_path))
	storage_key = str(ProjectSettings.get_setting("cascade/outbox_key",storage_key))
	if OS.get_cmdline_user_args().has("--offline-tests"):
		enabled = false
		set_process(false)
		return
	_load_pending()
	# Closed sessions were fully acknowledged by the server in an earlier run; drop them.
	if storage_error == "": sessions = sessions.filter(func(saved): return not (saved.closed and saved.pending.is_empty()))
	# Refresh does not resume gameplay; existing identities/outbox/jobs remain immutable.
	for saved in sessions:
		if saved.closing == "": saved.closing = "interrupted"
	_persist()

func attach(value: MissionSession) -> void:
	if not enabled:
		value.current.support_provider = MockSupportProvider.new()
		return
	if mission != value:
		finish("interrupted")
		mission = value
		active = {}
	_unbind()
	game = value.current
	_bind()

func _unbind() -> void:
	if observed_logger != null and observed_logger.recorded.is_connected(_on_event): observed_logger.recorded.disconnect(_on_event)
	if game != null:
		if game.confidential_recorded.is_connected(_on_confidential): game.confidential_recorded.disconnect(_on_confidential)
		if game.changed.is_connected(_on_change): game.changed.disconnect(_on_change)

func _bind() -> void:
	observed_logger = game.logger
	game.support_provider = BackendSupportProvider.new(self) if ProjectSettings.get_setting("cascade/support_provider","mock") == "backend" else MockSupportProvider.new()
	game.support_session_id = mission.session_id
	observed_logger.recorded.connect(_on_event)
	game.confidential_recorded.connect(_on_confidential)
	game.changed.connect(_on_change)
	if not active.is_empty():
		for event in observed_logger.to_array(): _on_event(event)
	else:
		_ensure_active()

func _on_change() -> void:
	if game.logger != observed_logger:
		# An explicit reset/configuration change is a new synthetic session identity.
		finish("interrupted")
		mission.session_id = Crypto.new().generate_random_bytes(16).hex_encode()
		active = {}
		_bind_after_reset()
	if game.phase != GameManager.Phase.OBSERVE: _ensure_active()
	if game.phase == GameManager.Phase.RESULTS and mission.index + 1 == mission.order.size():
		mission.capture_result()
		finish("completed")

func _bind_after_reset() -> void:
	_unbind()
	_bind()

func _ensure_active() -> void:
	if not active.is_empty() or game == null: return
	active = {"session_id":mission.session_id,"client_secret":Crypto.new().generate_random_bytes(32).hex_encode(),"credential":"","access_code":access_code,"next_seq":1,"pending":[],"closing":"","closed":false,
		"metadata":{"schema_version":5,"game_version":"cascade-development-5","scenario_order":mission.order.duplicate(),"order_source":mission.order_source,"condition":game.condition_name(),"participant_slots":["P1","P2","P3"],"record_mode":"synthetic-development","research_eligible":false}}
	sessions.append(active)
	# Include setup and all events emitted before the first private form opens.
	for event in observed_logger.to_array(): _enqueue("game",event)
	for record in game.confidential_records: _enqueue(record.channel,record.payload)
	_persist()

func _on_event(event: Dictionary) -> void:
	if not active.is_empty(): _enqueue("game",event)

func _on_confidential(record: Dictionary) -> void:
	if not active.is_empty(): _enqueue(record.channel,record.payload)

func _enqueue(channel: String, payload: Dictionary) -> void:
	active.pending.append({"event_id":Crypto.new().generate_random_bytes(16).hex_encode(),"seq":active.next_seq,"channel":channel,
		"scenario":game.scenario.scenario_id,"round":payload.get("round",game.state.round),"phase":GameManager.Phase.keys()[game.phase],"condition":active.metadata.condition,"payload":payload.duplicate(true)})
	active.next_seq += 1
	status = "Saving"
	_persist()

func finish(outcome: String) -> void:
	if not enabled or active.is_empty() or active.closing != "": return
	_enqueue("audit",{"type":"SESSION_COMPLETED" if outcome == "completed" else "SESSION_INTERRUPTED"})
	active.closing = outcome
	_persist()

func detach() -> void:
	if not enabled: return
	finish("interrupted")
	_unbind()
	game = null
	mission = null
	observed_logger = null
	active = {}

func _process(_delta: float) -> void:
	if not enabled: return
	var now := Time.get_ticks_msec()
	if not active.is_empty() and active.closing == "" and now >= heartbeat_at:
		heartbeat_at = now + 30000
		_enqueue("audit",{"type":"CLIENT_HEARTBEAT"})
	if not busy and now >= retry_at: _flush()

func _flush() -> void:
	var item: Dictionary = {}
	for candidate in sessions:
		if not candidate.closed and (candidate.credential == "" or not candidate.pending.is_empty() or candidate.closing != ""):
			item = candidate
			break
	if item.is_empty():
		status = "Saved" if storage_ok else "Save error"
		return
	busy = true
	var response: Dictionary
	var stage := ""
	var sent: Array = []
	var path := "/v1/sessions/" + str(item.session_id)
	if item.credential == "":
		stage = "start"
		var start := {"session_id":item.session_id,"client_secret":item.client_secret,"metadata":item.metadata}
		if str(item.get("access_code","")) != "": start.access_code = item.access_code
		response = await _http(HTTPClient.METHOD_POST,"/v1/sessions",start)
	elif not item.pending.is_empty():
		stage = "events"
		# Stay below the backend body limit even for larger audit events.
		for event in item.pending:
			if sent.size() >= 50 or (not sent.is_empty() and JSON.stringify(sent).length()+JSON.stringify(event).length()>70000): break
			sent.append(event)
		response = await _http(HTTPClient.METHOD_POST,path+"/events",{"events":sent},item.credential)
	else:
		stage = "completion"
		response = await _http(HTTPClient.METHOD_POST,path+"/completion",{"status":item.closing,"last_seq":item.next_seq-1},item.credential)
	var ok: bool = response.code == 200
	if ok:
		match stage:
			"start":
				ok = response.body.get("session_id","") == item.session_id and response.body.get("credential","") != ""
				if ok:
					item.credential = response.body.credential
					item.access_code = ""
			"events":
				var expected: Array = []
				for event in sent: expected.append(event.event_id)
				ok = response.body.get("acknowledged",[]) == expected
				if ok:
					for event in sent: item.pending.pop_front()
			"completion":
				ok = response.body.get("status","") == item.closing
				if ok: item.closed = true
	if ok:
		retry_count = 0
		retry_at = Time.get_ticks_msec() + 100
		status = "Saving"
		_persist()
	else:
		retry_count = mini(retry_count+1,6)
		retry_at = Time.get_ticks_msec() + int(minf(pow(2,retry_count),30)*1000)
		status = "Offline / unsent records" if response.code == 0 or response.code >= 500 else "Save error"
		if stage == "start" and response.code == 401: status = "Save error — access code rejected"
	busy = false

func _http(method: int, path: String, payload: Dictionary = {}, credential: String = "") -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 10
	request.body_size_limit = 262144
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if credential != "": headers.append("Authorization: Bearer "+credential)
	var error := request.request(base_url+path,headers,method,JSON.stringify(payload) if method == HTTPClient.METHOD_POST else "")
	if error != OK:
		request.queue_free()
		return {"code":0,"body":{}}
	var received: Array = await request.request_completed
	request.queue_free()
	var text: String = received[3].get_string_from_utf8()
	# Connection failures have no body; avoid noisy parse errors in routine logs.
	var parsed = JSON.parse_string(text) if text.strip_edges().begins_with("{") else null
	return {"code":int(received[1]) if received[0] == HTTPRequest.RESULT_SUCCESS else 0,"body":parsed if parsed is Dictionary else {}}

func request_support(context: Dictionary, condition: String, identity: Dictionary) -> Dictionary:
	_ensure_active()
	var item := active
	if item.is_empty() or item.session_id != identity.session: return {"error":"session_changed"}
	var deadline := Time.get_ticks_msec() + 150000
	var path := "/v1/sessions/%s/interventions/%s/%d" % [item.session_id,identity.scenario,identity.round]
	var posted := false
	var attempts := 0
	while Time.get_ticks_msec() < deadline:
		if item.closing != "": return {"error":"session_interrupted"}
		if item.credential == "":
			await get_tree().create_timer(0.25).timeout
			continue
		var response := await _http(HTTPClient.METHOD_GET if posted else HTTPClient.METHOD_POST,path,{} if posted else {"condition":condition,"context":context},item.credential)
		if response.code == 200:
			posted = true
			var result: Dictionary = response.body
			if result.get("status","") == "completed":
				var message = result.get("message")
				return message if message is Dictionary else {"error":"invalid_backend_response"}
			if result.get("status","") == "failed": return {"error":str(result.get("error","provider_failed"))}
		elif response.code != 0 and response.code != 429 and response.code < 500:
			return {"error":"backend_rejected"}
		else:
			attempts += 1
			if attempts >= 5: return {"error":"backend_unavailable"}
		await get_tree().create_timer(minf(pow(2,attempts),8)).timeout
	return {"error":"intervention_timeout"}

func access_required() -> bool:
	return enabled and bool(ProjectSettings.get_setting("cascade/require_access_code",false))

func status_text() -> String:
	if not enabled: return "Offline test / saving disabled"
	var count := 0
	for item in sessions: count += item.pending.size()
	var label := status + (" (%d)" % count if count > 0 else "")
	if not storage_ok: label = "Save error — local persistence unavailable; export JSON"
	return label

func recovery_export() -> Dictionary:
	# Deliberately excludes bootstrap secrets and session-scoped credentials.
	var records: Array = []
	for item in sessions:
		records.append({"session_id":item.session_id,"metadata":item.metadata,"pending":item.pending,"closing":item.closing})
	return {"pending_uploads":records,"storage_available":storage_ok}

func _load_pending() -> void:
	var text := ""
	if OS.has_feature("web"):
		var value = JavaScriptBridge.eval("(()=>{try{return localStorage.getItem('"+storage_key+"')||'';}catch(e){return '__UNAVAILABLE__';}})()")
		text = str(value)
		if text == "__UNAVAILABLE__":
			storage_ok = false
			storage_error = "Browser storage unavailable"
			return
	elif FileAccess.file_exists(outbox_path): text = FileAccess.get_file_as_string(outbox_path)
	if text == "": return
	var parsed = JSON.parse_string(text)
	if parsed is Array and parsed.all(func(item): return item is Dictionary and item.has_all(["session_id","client_secret","credential","metadata","next_seq","pending","closing","closed"]) and item.pending is Array):
		sessions = parsed
	else:
		storage_ok = false
		storage_error = "Pending records could not be read; original file retained"

func _persist() -> void:
	# Never overwrite unreadable pending records.
	if storage_error != "": return
	var text := JSON.stringify(sessions)
	if OS.has_feature("web"):
		storage_ok = bool(JavaScriptBridge.eval("(()=>{try{localStorage.setItem('"+storage_key+"',"+JSON.stringify(text)+");return true;}catch(e){return false;}})()"))
	else:
		var file := FileAccess.open(outbox_path+".tmp",FileAccess.WRITE)
		storage_ok = file != null
		if file != null:
			file.store_string(text)
			file.flush()
			storage_ok = file.get_error() == OK
			file.close()
			FileAccess.set_unix_permissions(outbox_path+".tmp",384)
			if storage_ok: storage_ok = DirAccess.rename_absolute(outbox_path+".tmp",outbox_path) == OK
