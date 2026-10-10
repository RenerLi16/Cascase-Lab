class_name PresentationText
extends RefCounted

const ACTION_DETAILS := {
	"VERIFY":"Record / dated pressure snapshot",
	"MONITOR":"Observe / reports later changes",
	"SHIELD":"Protect / incoming infection this round",
	"ISOLATE":"Close bridge / blocks outbreak spread and supply deliveries across this connection"
}

# Player-facing action names. Internal identifiers (logs, exports, AI contract) stay unchanged.
const ACTION_NAMES := {"VERIFY":"VERIFY","MONITOR":"MONITOR","SHIELD":"SHIELD","ISOLATE":"CLOSE BRIDGE","WAIT":"WAIT / SAVE SUPPLY"}
const BRIDGE_ONLY := "Only bridges can be closed."
const CLOSURE_EFFECT := "Blocks outbreak spread and supply deliveries across this connection."

static func action_name(kind: String) -> String:
	return ACTION_NAMES.get(kind,kind)

static func connection_name(edge: EdgeState) -> String:
	return ("Bridge " if edge.bridge else "Road ") + edge.id.replace("-"," — ")

const MAP_KEY := "\n\n[b]Reading the board[/b]\n? means unobserved pressure; it does not mean safe. Named towers identify playable buildings. Depot labels show their remaining supply. A lit beacon means functioning, not infection-free; light is decorative, not protection, detection or supply range. A functioning shelter stays lit even without supply access. A MONITOR tag marks an installed monitor; M:0 or M:1 is a public monitor reading. OBS R1 · P1 is a dated Verify record, not a current reading.\n\nA SHIELD emblem lasts for this resolution. Brackets mark selection; NO SUPPLY marks no stocked supply access. Solid roads can carry supplies; short dotted roads cannot currently carry supplies. Timber decks mark bridges over water or ravines; only bridges can be closed. A closed bridge has a barricade, long dashes and a CLOSED stamp. Crossed shelters are confirmed Overrun."

static func phase_title(phase: GameManager.Phase) -> String:
	if phase in [GameManager.Phase.ROUND_EVALUATION_GATE,GameManager.Phase.ROUND_EVALUATION_FORM]: return "Round evaluation"
	if phase in [GameManager.Phase.SCENARIO_REASONING_GATE,GameManager.Phase.SCENARIO_REASONING_FORM]: return "Scenario reasoning"
	return {
		GameManager.Phase.OBSERVE:"Observe",
		GameManager.Phase.PRIVATE_FORM:"Private judgment",
		GameManager.Phase.DISCUSSION:"Team discussion",
		GameManager.Phase.INTERVENTION:"Decision pause",
		GameManager.Phase.ACTIONS:"Select actions",
		GameManager.Phase.DELIVERY:"Supply delivery",
		GameManager.Phase.RESOLUTION:"Resolution",
		GameManager.Phase.ROUND_COMPLETE:"Round complete",
		GameManager.Phase.RESULTS:"Incident summary"
	}.get(phase,"Private judgment")

const RULES := "[b]Survive three rounds[/b]\nKeep shelters functioning. Quiet shelters may have hidden exposure.\n\n[b]Roads, bridges and outbreak[/b]\nAll roads and bridges carry zombies and supply in both directions. Overrun is permanent. Each Overrun shelter infects its neighbors at resolution; new Overrun shelters spread starting next round. Multiple incoming infections stack.\n\nAn Exposed shelter becomes Overrun at the next resolution. Newly exposed shelters wait until the following resolution to progress. Shields block incoming infection, not exposure already inside.\n\n[b]Six supplies for the whole mission[/b]\nSupply never regenerates or heals infection. Deliveries use the shortest active route. Overrun shelters cannot receive or relay supply.\n\nVERIFY · 1 — a precise, dated pressure snapshot.\nMONITOR · 1 — reports later pressure changes. Installation does not reveal a baseline.\nSHIELD · 1 — blocks incoming road infection this resolution, then expires.\nCLOSE BRIDGE · 2 — only bridges can be closed; ordinary roads stay open. Deliver one unit to each end, then the bridge closes permanently. It blocks outbreak spread and supply deliveries across this connection. Choose a highlighted source depot for each end, then confirm both deliveries. Different depots may pay. Both ends must be reachable.\n\n[b]Map controls[/b]\nChoose an action, then click a highlighted depot on the map to preview its route. Confirm delivery to spend supplies; Back or Cancel spends nothing.\n\nClick a named tower to animate into a close-up and open its information. Overview, empty map space, or Escape returns to the district. Roads and bridges open a nearby information bubble without zooming. Hide survey retracts your form; Expand survey restores your answers. Drag to pan; use the wheel, pinch or + / − for bounded zoom. Reduce motion freezes ambient effects without changing game timing."

# Readable explanations for unavailable actions. Codes stay unchanged in the domain layer.
const UNAVAILABLE := {
	"DELIVERY IN PROGRESS":"A delivery is in progress.",
	"ROAD CLOSED":"This bridge is already closed.",
	"NOT A BRIDGE":BRIDGE_ONLY,
	"ENDPOINT OVERRUN":"An end of this bridge is Overrun.",
	"OVERRUN":"This shelter is Overrun.",
	"MONITOR ACTIVE":"A monitor is already installed here.",
	"SHIELD ACTIVE":"A shield is already active here this round.",
	"NO SUPPLY":"Not enough supply remains.",
	"NO SUPPLY ROUTE":"No stocked depot has a supply route here.",
	"NOT ACTION PHASE":"Actions are available only in the action phase.",
	"WRONG ROUND":"This action belongs to a different round.",
	"SELECT A ROAD":"Select a bridge.",
	"SELECT A SHELTER":"Select a shelter."
}

static func unavailable_text(code: String) -> String:
	if UNAVAILABLE.has(code): return UNAVAILABLE[code]
	return code.capitalize() if code == code.to_upper() else code

static func known_status(shelter: ShelterState) -> String:
	if shelter.is_overrun: return "Overrun"
	if shelter.monitor_known_pressure >= 0: return "Monitor: Pressure %d" % shelter.monitor_known_pressure
	return "Unknown"

static func observation_text(observation: Dictionary) -> String:
	if observation.type == "VERIFY":
		return "%s · Verify reading\nPressure %d at round %d · dated snapshot" % [observation.target,observation.pressure,observation.round]
	return "Monitor alert · %s\nPressure %d to %d · Round %d" % [observation.target,observation.old,observation.new,observation.round]

static func debug(session: GameManager) -> String:
	var text := "DEV MODE · HIDDEN STATE\nInitial exposures: %s\n\n" % ", ".join(session.scenario.initial_exposure_ids())
	for id in session.state.shelters:
		var shelter: ShelterState = session.state.shelters[id]
		text += "%s: P%d · shield %s · monitor %s\n" % [id,shelter.zombie_pressure,shelter.shielded_this_round,shelter.is_monitored]
	text += "\nSUPPLY ROUTES\n"
	var network := NetworkManager.new(session.state)
	for depot in session.state.depots:
		text += "%s: %s\n" % [depot,", ".join(network.get_reachable_shelters(depot))]
		for id in session.state.shelters:
			text += "%s to %s: %s\n" % [depot,id," — ".join(network.get_supply_path(depot,id))]
	text += "\nNEXT RESOLUTION\n" + JSON.stringify(session.preview_resolution(),"  ")
	text += "\n\nANONYMOUS SURVEYS (UNORDERED WITHIN ROUND)\n" + JSON.stringify(session.anonymous_surveys(),"  ")
	text += "\n\nINTERNAL EVENTS\n" + JSON.stringify(session.logger.to_array(),"  ")
	return text
