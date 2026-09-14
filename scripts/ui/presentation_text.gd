class_name PresentationText
extends RefCounted

const RULES := "[b]SURVIVE THREE ROUNDS[/b]\nKeep shelters functioning. Quiet shelters may have hidden exposure.\n\n[b]ROADS & OUTBREAK[/b]\nAll roads carry zombies and supply in both directions. Overrun is permanent. Each Overrun shelter infects its neighbors at resolution; new Overrun shelters spread starting next round. Multiple incoming infections stack.\n\nAn Exposed shelter becomes Overrun at the next resolution. Newly exposed shelters wait until the following resolution to progress. Shields block incoming infection, not exposure already inside.\n\n[b]SIX SUPPLIES FOR THE WHOLE MISSION[/b]\nSupply never regenerates or heals infection. Deliveries use the shortest active route. Overrun shelters cannot receive or relay supply.\n\nVERIFY · 1 — a precise, dated pressure snapshot.\nMONITOR · 1 — reports later pressure changes. Installation does not reveal a baseline.\nSHIELD · 1 — blocks incoming road infection this resolution, then expires.\nISOLATE · 2 — deliver one unit to each endpoint, then close the road permanently. Different depots may pay. Both endpoints must be reachable.\n\n[b]CITY SURVEILLANCE[/b]\nA scheduled report arrives at the start of every round. Reports describe observations, not confirmed shelter infection.\n\n[b]MAP CONTROLS[/b]\nWheel or + / − to zoom. Drag with left or middle mouse to pan. Center resets the map. Click a shelter or road to select it."

static func known_status(shelter: ShelterState) -> String:
	if shelter.is_overrun: return "OVERRUN"
	if shelter.monitor_known_pressure >= 0: return "Monitor: Pressure %d" % shelter.monitor_known_pressure
	return "Unknown"

static func observation_text(observation: Dictionary) -> String:
	if observation.type == "VERIFY":
		return "%s · VERIFIED\nPressure %d · Round %d" % [observation.target,observation.pressure,observation.round]
	return "MONITOR ALERT · %s\n%d → %d · Round %d" % [observation.target,observation.old,observation.new,observation.round]

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
	text += "\n\nPRIVATE SURVEYS\n" + JSON.stringify(session.private_surveys,"  ")
	text += "\n\nINTERNAL EVENTS\n" + JSON.stringify(session.logger.to_array(),"  ")
	return text
