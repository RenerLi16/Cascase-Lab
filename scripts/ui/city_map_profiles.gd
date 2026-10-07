class_name CityMapProfiles
extends RefCounted

# Visual coordinates only. ScenarioData still owns simulation geometry/route costs.
const FILES := {
	"riverside_01_v2": "res://assets/maps/layouts/riverside.json",
	"twin_districts_02_v1": "res://assets/maps/layouts/twin_districts.json",
	"lifeline_03_v1": "res://assets/maps/layouts/lifeline.json",
	"crossfire_04_v1": "res://assets/maps/layouts/crossfire.json",
}
const TEXTURES := {
	"riverside_01_v2": preload("res://assets/maps/riverside.png"),
	"twin_districts_02_v1": preload("res://assets/maps/twin_districts.png"),
	"lifeline_03_v1": preload("res://assets/maps/lifeline.png"),
	"crossfire_04_v1": preload("res://assets/maps/crossfire.png"),
}
# Boards without a layout record (the practice map) still share the paper terrain.
const EXTRA_TERRAIN := {
	"practice_demo_v1": preload("res://assets/maps/practice.png"),
}
static var cache: Dictionary = {}

static func terrain(id: String) -> Texture2D:
	if TEXTURES.has(id): return TEXTURES[id]
	return EXTRA_TERRAIN.get(id,null)

static func has_profile(id: String) -> bool:
	return FILES.has(id)

static func layout(scenario: ScenarioData) -> Dictionary:
	var id := scenario.scenario_id
	if not cache.has(id): cache[id] = JSON.parse_string(FileAccess.get_file_as_string(FILES[id]))
	return cache[id]

static func vector(values: Array) -> Vector2:
	return Vector2(values[0],values[1])

static func node(scenario: ScenarioData, id: String) -> Dictionary:
	return layout(scenario).nodes[id]

static func rectangle(values: Array) -> Rect2:
	return Rect2(values[0],values[1],values[2],values[3])

static func building(scenario: ScenarioData, id: String) -> Rect2:
	return rectangle(node(scenario,id).building)

static func anchor(scenario: ScenarioData, id: String) -> Vector2:
	return vector(node(scenario,id).anchor)

static func road(scenario: ScenarioData, id: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in layout(scenario).edges[id].centerline: points.append(vector(point))
	return points

static func image_to_world(scenario: ScenarioData, pixel: Vector2) -> Vector2:
	var data := layout(scenario)
	return pixel / vector(data.image_size) * vector(data.world_size)
