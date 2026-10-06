class_name PresentationText
extends RefCounted

const ACTION_DETAILS := {
	"VERIFY":"Record / dated pressure snapshot",
	"MONITOR":"Observe / reports later changes",
	"SHIELD":"Protect / incoming infection this round",
	"ISOLATE":"Close / one delivery to each endpoint"
}

const MAP_KEY := "\n\n[b]Reading the board[/b]\n? means unobserved pressure; it does not mean safe. Named frames identify playable buildings. Depot frames show their remaining supply. A MONITOR tag marks an installed monitor; M:0 or M:1 is a public monitor reading. OBS R1 · P1 is a dated Verify record, not a current reading.\n\nA SHIELD outline lasts for this resolution. Brackets mark selection; NO SUPPLY marks no stocked supply access. Solid roads can carry supplies; short dotted roads cannot currently carry supplies. Closed roads have long dashes and barricades. Crossed shelters are confirmed Overrun."

static func phase_title(phase: GameManager.Phase) -> String:
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

const RULES := "[b]Survive three rounds[/b]\nKeep shelters functioning. Quiet shelters may have hidden exposure.\n\n[b]Roads and outbreak[/b]\nAll roads carry zombies and supply in both directions. Overrun is permanent. Each Overrun shelter infects its neighbors at resolution; new Overrun shelters spread starting next round. Multiple incoming infections stack.\n\nAn Exposed shelter becomes Overrun at the next resolution. Newly exposed shelters wait until the following resolution to progress. Shields block incoming infection, not exposure already inside.\n\n[b]Six supplies for the whole mission[/b]\nSupply never regenerates or heals infection. Deliveries use the shortest active route. Overrun shelters cannot receive or relay supply.\n\nVERIFY · 1 — a precise, dated pressure snapshot.\nMONITOR · 1 — reports later pressure changes. Installation does not reveal a baseline.\nSHIELD · 1 — blocks incoming road infection this resolution, then expires.\nISOLATE · 2 — deliver one unit to each endpoint, then close the road permanently. Different depots may pay. Both endpoints must be reachable.\n\n[b]Map controls[/b]\nClick a building frame to animate into a close-up and open its information. Overview, empty map space, or Escape returns to the district. Roads open a nearby action bubble without zooming. Hide survey retracts your form; Expand survey restores your answers. Cased lines mark playable roads; other streets are scenery."

# Readable explanations for unavailable actions. Codes stay unchanged in the domain layer.
const UNAVAILABLE := {
	"DELIVERY IN PROGRESS":"A delivery is in progress.",
	"ROAD CLOSED":"This road is already closed.",
	"ENDPOINT OVERRUN":"An endpoint of this road is Overrun.",
	"OVERRUN":"This shelter is Overrun.",
	"MONITOR ACTIVE":"A monitor is already installed here.",
	"SHIELD ACTIVE":"A shield is already active here this round.",
	"NO SUPPLY":"Not enough supply remains.",
	"NO SUPPLY ROUTE":"No stocked depot has a supply route here.",
	"NOT ACTION PHASE":"Actions are available only in the action phase.",
	"WRONG ROUND":"This action belongs to a different round.",
	"SELECT A ROAD":"Select a road.",
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
