class_name PresentationText
extends RefCounted

const ACTION_DETAILS := {
	"VERIFY":"Record / dated pressure snapshot",
	"MONITOR":"Observe / reports later changes",
	"SHIELD":"Protect / incoming infection this round",
	"ISOLATE":"Close / one delivery to each endpoint"
}

const MAP_KEY := "\n\n[b]READING THE BOARD[/b]\n? means unobserved pressure; it does not mean safe. A square depot carries its remaining supply below the location letter. A short mast marks an installed monitor; M:0 or M:1 is a public monitor reading. OBS R1 · P1 is a dated Verify record, not a current reading.\n\nAn angular SHIELD outline lasts for this resolution. Brackets mark selection; a corner slash marks no stocked supply access. Fine dotted roads cannot currently carry supplies. Barricades mark a closed road. Crossed shelters are confirmed Overrun."

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

const RULES := "[b]SURVIVE THREE ROUNDS[/b]\nKeep shelters functioning. Quiet shelters may have hidden exposure.\n\n[b]ROADS & OUTBREAK[/b]\nAll roads carry zombies and supply in both directions. Overrun is permanent. Each Overrun shelter infects its neighbors at resolution; new Overrun shelters spread starting next round. Multiple incoming infections stack.\n\nAn Exposed shelter becomes Overrun at the next resolution. Newly exposed shelters wait until the following resolution to progress. Shields block incoming infection, not exposure already inside.\n\n[b]SIX SUPPLIES FOR THE WHOLE MISSION[/b]\nSupply never regenerates or heals infection. Deliveries use the shortest active route. Overrun shelters cannot receive or relay supply.\n\nVERIFY · 1 — a precise, dated pressure snapshot.\nMONITOR · 1 — reports later pressure changes. Installation does not reveal a baseline.\nSHIELD · 1 — blocks incoming road infection this resolution, then expires.\nISOLATE · 2 — deliver one unit to each endpoint, then close the road permanently. Different depots may pay. Both endpoints must be reachable.\n\n[b]CITY SURVEILLANCE[/b]\nA scheduled report arrives at the start of every round. Reports describe observations, not confirmed shelter infection.\n\n[b]MAP CONTROLS[/b]\nWheel or + / − to zoom. Drag with left or middle mouse to pan. Center resets the map. Click a shelter or road to select it."

static func known_status(shelter: ShelterState) -> String:
	if shelter.is_overrun: return "OVERRUN"
	if shelter.monitor_known_pressure >= 0: return "Monitor: Pressure %d" % shelter.monitor_known_pressure
	return "Unknown"

static func observation_text(observation: Dictionary) -> String:
	if observation.type == "VERIFY":
		return "%s · VERIFIED\nPressure %d · Round %d" % [observation.target,observation.pressure,observation.round]
	return "MONITOR ALERT · %s\nPressure %d to %d · Round %d" % [observation.target,observation.old,observation.new,observation.round]

static func debug(session: GameManager) -> String:
	var text := "DEV MODE · HIDDEN STATE\nSource: %s\n\n" % session.scenario.original_source
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
