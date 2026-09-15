class_name SupportLibrary
extends RefCounted

# Pure deterministic function of the SAME public projection for every condition.
# No GameManager/ScenarioData reference, I/O, network, clock, RNG or hidden solver.
const VERSION := "support-1.0.0"
const PAUSE_SECONDS := 15
const CONDITIONS := ["NONE", "DIRECT_RECOMMENDATION", "CONSTRUCTIVE_DISSENT"]
const LABELS := ["No AI", "Direct-Recommendation AI", "Constructive-Dissent AI"]
const TEMPLATES := {
	"direct.verify":["Recommendation: Verify Shelter %s next.",
		"Why: A precise observation can test concerns about this location before more supplies are committed. Public reports and the map alone do not establish its current pressure.",
		"Check: Confirm which stocked depot can reach it, and remember that the result is only a snapshot."],
	"direct.shield":["Recommendation: Shield Shelter %s next.",
		"Why: An open road connects this shelter to a visibly Overrun neighbor. Protection could block incoming infection while preserving the shelter as a supply route.",
		"Check: Existing exposure is not cured by shielding; distinguish current observations from older verification results."],
	"direct.monitor":["Recommendation: Monitor Shelter %s next.",
		"Why: Structured proposals include monitoring this reachable location. Continuing observations could test assumptions about changing danger while the team manages its remaining supplies.",
		"Check: Installation reveals no baseline and prevents no infection; consider whether later information will arrive in time to matter."],
	"direct.isolate":["Recommendation: Isolate Road %s next.",
		"Why: Structured proposals include closing this currently usable road. Both endpoints have funded delivery routes, and closure would block infection along this connection.",
		"Check: Inspect the supply access lost on each side before committing both units; alternative roads may still carry infection."],
	"direct.wait_agreement":["Recommendation: Wait; save supply across the district this round.",
		"Why: The structured proposals agree on waiting. Retaining resources leaves them available later, although the public map and reports cannot establish every shelter's current condition.",
		"Check: Consider whether delaying protection could make an important endpoint unreachable after resolution."],
	"direct.wait_unavailable":["Recommendation: Wait; take no supply action across the district this round.",
		"Why: No funded action has a usable delivery route under the current public road, shelter, and depot conditions. An action cannot be completed without reachable supplies.",
		"Check: Review remaining depot stock and closures before ending the round."],
	"dissent.different":["Decision check: The anonymous responses suggest different priorities for the next decision; the public evidence may support more than one interpretation.",
		"Discuss: Which observation would change how the team compares these priorities?",
		"Evidence to seek: A comparison of existing observations, supply access, and the cost of delaying protection."],
	"dissent.assumptions":["Decision check: Similar action proposals rest on different reasoning categories, so agreement about a next step may conceal different assumptions.",
		"Discuss: Which assumption must hold for the proposed step to be useful?",
		"Evidence to seek: The link between dated shelter observations, current road access, and the expected benefit."],
	"dissent.confidence":["Decision check: The structured responses show uncertainty in confidence even where proposals align; confidence alone does not establish the condition of a shelter.",
		"Discuss: What evidence would make the shared assumption more credible?",
		"Evidence to seek: The age and precision of existing observations compared with the remaining supply options."],
	"dissent.agreement":["Decision check: The structured proposals align, but a shared assumption can still overlook hidden exposure or a fragile supply route.",
		"Discuss: What would have to be different for the current plan to lose its advantage?",
		"Evidence to seek: A comparison of dated observations, route availability, and the cost of being wrong."],
	"dissent.unavailable":["Decision check: The public map and remaining stock leave no funded action with a usable delivery route, limiting the team's immediate options.",
		"Discuss: Which assumption about access or available resources shaped the current plan?",
		"Evidence to seek: A comparison of depot balances, road closures, and visibly lost relay shelters."],
	"none.pause":["Pause: This is the scheduled interval between the team's initial discussion and final action selection.",
		"Time: The same interval occurs in every round. The game remains paused while the countdown runs.",
		"Continue: When the interval ends, the action controls become available after the team continues."]
}

static func word_count(text: String) -> int:
	return text.replace("\n"," ").split(" ",false).size()

static func generate(context: Dictionary, condition: String) -> Dictionary:
	var template_id := "none.pause"
	var target := ""
	var action := ""
	var legal := legal_actions(context)
	if condition == "DIRECT_RECOMMENDATION":
		var selected := recommend(context,legal)
		template_id = selected.template_id
		target = selected.target
		action = selected.action
	elif condition == "CONSTRUCTIVE_DISSENT":
		template_id = dissent_template(context,legal)
	var lines: Array = TEMPLATES[template_id].duplicate()
	if "%s" in lines[0]: lines[0] = lines[0] % target
	var displayed := "\n".join(lines)
	assert(word_count(displayed) >= 35 and word_count(displayed) <= 60)
	return {"template_id":template_id, "version":VERSION, "text":displayed,
		"action":action, "target":target, "word_count":word_count(displayed)}

static func reachable(context: Dictionary, depot: String, target: String) -> bool:
	if context.shelters[depot].overrun or context.shelters[target].overrun: return false
	var visited := [depot]
	var index := 0
	while index < visited.size():
		var current: String = visited[index]
		if current == target: return true
		index += 1
		for road in context.roads.values():
			if road.closed or not road.endpoints.has(current): continue
			var neighbor: String = road.endpoints[1] if road.endpoints[0] == current else road.endpoints[0]
			if not context.shelters[neighbor].overrun and not visited.has(neighbor): visited.append(neighbor)
	return false

static func funded_depots(context: Dictionary, target: String) -> Array:
	var output: Array = []
	for depot in context.depots:
		if context.depots[depot] > 0 and reachable(context,depot,target): output.append(depot)
	return output

static func legal_actions(context: Dictionary) -> Array:
	var output: Array = []
	var ids: Array = context.shelters.keys()
	ids.sort()
	for id in ids:
		if funded_depots(context,id).is_empty(): continue
		for kind in ["VERIFY","MONITOR","SHIELD"]:
			if kind == "MONITOR" and context.shelters[id].monitored: continue
			if kind == "SHIELD" and context.shelters[id].shielded: continue
			output.append({"action":kind,"target":id})
	ids = context.roads.keys()
	ids.sort()
	for id in ids:
		var road: Dictionary = context.roads[id]
		if road.closed: continue
		var possible := false
		for first in funded_depots(context,road.endpoints[0]):
			for second in funded_depots(context,road.endpoints[1]):
				if first != second or context.depots[first] >= 2: possible = true
		if possible: output.append({"action":"ISOLATE","target":id})
	return output

static func visible_threats(context: Dictionary, id: String) -> int:
	var count := 0
	for road in context.roads.values():
		if road.closed or not road.endpoints.has(id): continue
		var neighbor: String = road.endpoints[1] if road.endpoints[0] == id else road.endpoints[0]
		if context.shelters[neighbor].overrun: count += 1
	return count

static func recommend(context: Dictionary, legal: Array) -> Dictionary:
	if legal.is_empty(): return {"template_id":"direct.wait_unavailable","action":"WAIT","target":"NONE"}
	var all_wait: bool = context.responses.size() == 3
	for response in context.responses:
		if response.preferred_action != "WAIT": all_wait = false
	if all_wait: return {"template_id":"direct.wait_agreement","action":"WAIT","target":"NONE"}
	var best: Dictionary = {}
	var best_score := -1
	for candidate in legal:
		var score := 0
		var proposals := 0
		for response in context.responses:
			if response.preferred_action == candidate.action and response.action_target == candidate.target: proposals += 1
			if response.danger_location == candidate.target: score += 2
		score += proposals * 3
		match candidate.action:
			"VERIFY":
				score += 10
				for road in context.roads.values():
					if not road.closed and road.endpoints.has(candidate.target): score += 1
			"SHIELD":
				var threats := visible_threats(context,candidate.target)
				if threats == 0: continue
				var shelter: Dictionary = context.shelters[candidate.target]
				if shelter.known_pressure == 1: continue
				if not shelter.verified_history.is_empty() and shelter.verified_history.back().pressure == 1: continue
				score += 25 + threats * 3
			"MONITOR", "ISOLATE":
				if proposals == 0: continue
				score += 12
		# Sorted IDs and fixed action order break ties; no use of player identity/order.
		if score > best_score:
			best_score = score
			best = candidate
	return {"template_id":"direct." + str(best.action).to_lower(), "action":best.action, "target":best.target}

static func dissent_template(context: Dictionary, legal: Array) -> String:
	if legal.is_empty(): return "dissent.unavailable"
	var decisions: Array = []
	var reasons: Array = []
	var confidence: Array = []
	for response in context.responses:
		var decision: String = response.danger_location + ":" + response.preferred_action + ":" + response.action_target
		if not decisions.has(decision): decisions.append(decision)
		if response.reason != "" and not reasons.has(response.reason): reasons.append(response.reason)
		confidence.append(response.confidence)
	if decisions.size() > 1: return "dissent.different"
	if reasons.size() > 1: return "dissent.assumptions"
	if not confidence.is_empty() and (confidence.min() <= 2 or confidence.max() - confidence.min() >= 2): return "dissent.confidence"
	return "dissent.agreement"
