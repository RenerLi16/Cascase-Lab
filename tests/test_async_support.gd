extends SceneTree

class DelayedProvider extends SupportProvider:
	var callbacks: Array[Callable] = []
	var inputs: Array = []
	func request(context: Dictionary, condition: String, identity: Dictionary, done: Callable) -> void:
		inputs.append({"context":context,"condition":condition,"identity":identity})
		callbacks.append(done)

var checks := 0
var failures := 0
var now := 1000

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func submit(game: GameManager) -> void:
	game.start_private()
	for index in 3:
		game.open_private_form()
		game.submit_belief(PlayerBelief.new("E","VERIFY","E",4,"gather more information"))

func run() -> void:
	var provider := DelayedProvider.new()
	var game := GameManager.new(null,GameManager.InterventionType.NONE,func(): return now)
	game.support_provider = provider
	submit(game)
	check(provider.inputs.is_empty(),"No AI calls no provider")
	game = GameManager.new(null,GameManager.InterventionType.DIRECT_RECOMMENDATION,func(): return now)
	game.support_provider = provider
	submit(game)
	check(provider.inputs.size()==1 and game.phase==GameManager.Phase.DISCUSSION,"Generation requested during discussion")
	check(not game.mark_support_shown() and not game.begin_support(),"Cannot reveal early")
	var frozen := JSON.stringify(provider.inputs[0].context)
	game.private_surveys[1][0].confidence=1
	game.state.shelters.E.zombie_pressure=1
	check(JSON.stringify(game.frozen_support_context)==frozen,"Snapshot frozen after three responses")
	now+=120000
	game.begin_support()
	check(game.support_message.is_empty() and not game.mark_support_shown(),"Pending generation cannot start reading pause")
	now+=17000
	provider.callbacks[0].call({"text":"Test: delayed\nWhy: synthetic\nCheck: timing","template_id":"test","version":"test","provider":"mock"})
	check(not game.support_shown and not game.proceed_to_actions(),"Receipt alone is not display")
	game.mark_support_shown()
	check(game.support_seconds_remaining()==15,"Reading pause begins at actual display")
	now+=14999
	check(not game.proceed_to_actions(),"Delayed generation retains full reading pause")
	now+=1
	check(game.proceed_to_actions(),"Actions available after actual reading time")
	var dissent := GameManager.new(null,GameManager.InterventionType.CONSTRUCTIVE_DISSENT,func(): return now)
	dissent.support_provider=provider
	submit(dissent)
	check(JSON.stringify(provider.inputs[1].context)==frozen,"Both conditions share same projection")
	dissent.reset()
	provider.callbacks[1].call({"error":"late_provider_failure"})
	check(dissent.support_message.is_empty(),"Reset rejects late provider reply")
	submit(dissent)
	dissent.state.round=2
	provider.callbacks[2].call({"error":"late_round_failure"})
	check(dissent.support_message.is_empty(),"Different round rejects late reply")
	dissent.state.round=1
	provider.callbacks[2].call({"error":"provider_rejected"})
	check(dissent.support_message.provider=="unavailable" and dissent.support_message.text.contains("AI support unavailable"),"Failure visibly distinct from generated output")
	check(dissent.confidential_records.any(func(r): return r.payload.type=="AI_FAILURE"),"Deviation audited separately")
	now+=120000
	dissent.begin_support()
	dissent.mark_support_shown()
	check(dissent.support_seconds_remaining()==15,"Failure retains pause")
	var exported := dissent.export_dictionary()
	check(exported.has("development_private_audit") and exported.private_surveys.size()==3,"Manual export retains private audit and existing responses")
	check(dissent.confidential_records.filter(func(r): return r.channel=="private").map(func(r): return r.payload.slot)==["P1","P2","P3"],"Stable pseudonymous slots kept outside board log")
	check(not JSON.stringify(dissent.logger.to_array()).contains('"response"'),"Board events exclude private responses")
	provider.callbacks.clear()
	print("ASYNC SUPPORT TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
