extends SceneTree

const Fixture = preload("res://tests/post_form_fixture.gd")
var checks := 0
var failures := 0
var now := 0
const CANARY := "PRIVATE_POST_OUTCOME_CANARY"

class SyntheticProvider extends SupportProvider:
	var result: Dictionary
	var contexts: Array = []
	func request(context: Dictionary, _condition: String, _identity: Dictionary, done: Callable) -> void:
		contexts.append(context.duplicate(true))
		done.call(result)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var incomplete := MissionSession.new()
	incomplete.current.phase = GameManager.Phase.RESULTS
	check(not incomplete.capture_result() and not incomplete.advance() and not incomplete.is_complete(),"Results phase alone cannot bypass missing forms")
	for variant in ["none","qwen","failed","mock"]:
		var mission := MissionSession.new(GameManager.RunPurpose.NORMAL,GameManager.InterventionType.NONE if variant == "none" else GameManager.InterventionType.DIRECT_RECOMMENDATION)
		var provider := SyntheticProvider.new()
		provider.result = {"error":"synthetic_failure"} if variant == "failed" else {"text":"Synthetic fixture only","provider":variant,"template_id":"test","version":"fixture-1","intervention_id":"fixture-message"}
		var evaluations := 0
		var reasons := 0
		for scenario_number in 4:
			var game := mission.current
			game._support_clock = func(): return now
			game.support_provider = provider
			for round_number in range(1,4):
				game.start_private()
				for player in 3:
					game.open_private_form()
					check(game.submit_belief(PlayerBelief.new("A","WAIT","NONE",3,"protect supply access")),"Initial judgment unchanged")
				now += 120000
				check(game.begin_support(),"Discussion still required")
				check(not game.ai_evaluation_applicable(),"AI not applicable before display")
				game.mark_support_shown()
				now += 15000
				check(game.proceed_to_actions(),"Reading pause still required")
				check(game.begin_resolution() and game.apply_resolution(game.run_token) and game.finish_resolution(game.run_token),"Outcome precedes forms")
				check(game.phase == GameManager.Phase.ROUND_COMPLETE and game.round_evaluations.size() == (round_number-1)*3,"Summary visible first")
				game.next_round()
				for player in 3:
					check(game.phase == GameManager.Phase.ROUND_EVALUATION_GATE,"Round privacy gate")
					check(not mission.capture_result() and not mission.advance() and not mission.is_complete(),"No results/session bypass")
					game.next_round()
					check(game.state.round == round_number,"Next round blocked")
					game.open_private_form()
					var key := game.post_form_key()
					check(not game.submit_post_form(key,{}),"Blank form rejected")
					check(game.post_form_draft.is_empty(),"Next player starts blank")
					check(game.post_form_questions().size() == (7 if variant == "qwen" else 5),"AI-specific visibility")
					var answers := Fixture.answers(game,CANARY)
					var bad := answers.duplicate()
					bad.explanation = "x".repeat(601)
					check(not game.submit_post_form(key,bad),"600-character limit")
					bad.explanation = " \n "
					check(not game.submit_post_form(key,bad),"Whitespace rejected without arbitrary minimum")
					bad = answers.duplicate()
					bad.influence = "AI message"
					check(EvaluationInstruments.valid("round_evaluation",bad,game.ai_evaluation_applicable()) == (variant == "qwen"),"AI influence option eligibility")
					if variant == "qwen": answers.ai_usefulness = "Unable to judge"
					check(game.submit_post_form(key,answers),"Round form accepted")
					evaluations += 1
					check(not game.submit_post_form(key,answers),"Duplicate rejected")
					answers.explanation = "mutated"
					check(game.round_evaluations.back().answers.explanation == CANARY,"Submission immutable")
					var record: Dictionary = game.round_evaluations.back()
					check(record.session_id == mission.session_id and record.scenario_index == scenario_number and record.slot == "P%d" % (player+1),"Stable metadata")
					check(record.timing == "post_outcome_after_round_summary" and record.submitted_utc.ends_with("Z"),"Explicit post-outcome timing")
					check(record.ai_display.not_applicable_reason != "" or variant == "qwen","Inapplicability reason retained")
				if round_number == 3:
					for player in 3:
						check(game.phase == GameManager.Phase.SCENARIO_REASONING_GATE,"Scenario privacy gate")
						check(not mission.capture_result() and not mission.advance(),"Final reasoning cannot be bypassed")
						game.open_private_form()
						var answers := Fixture.answers(game,"Nothing")
						answers.strategy = "x".repeat(1001)
						check(not game.submit_post_form(game.post_form_key(),answers),"1000-character limit")
						answers.strategy = "x".repeat(1000)
						check(game.submit_post_form(game.post_form_key(),answers),"Scenario reasoning accepted")
						reasons += 1
				check(not JSON.stringify(game.logger.to_array()).contains(CANARY),"No sensitive answers in game logs")
			check(game.required_forms_complete() and mission.capture_result(),"Completed forms enable results")
			check(game.anonymous_surveys().size() == 9,"Nine original judgments retained per scenario")
			if scenario_number < 3: check(mission.advance(),"Advance after all forms")
		check(evaluations == 36 and reasons == 12 and mission.is_complete(),"Four-scenario totals 36 + 12")
		check(not JSON.stringify(provider.contexts).contains(CANARY),"New answers never enter current or future provider requests")
		check(mission.export_dictionary().missions[3].round_evaluations.size() == 9,"Final scenario exported")
	var sandbox := MissionSession.new(GameManager.RunPurpose.DEV_SANDBOX,GameManager.InterventionType.NONE,[ScenarioData.registry().development_default_order[0]])
	for _round in 3:
		sandbox.current.begin_sandbox_actions()
		sandbox.current.begin_resolution()
		sandbox.current.apply_resolution(sandbox.current.run_token)
		sandbox.current.finish_resolution(sandbox.current.run_token)
		sandbox.current.next_round()
	check(sandbox.current.phase == GameManager.Phase.RESULTS and sandbox.current.round_evaluations.is_empty() and sandbox.current.scenario_reasoning.is_empty(),"Sandbox excludes forms")
	print("EVALUATION TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
