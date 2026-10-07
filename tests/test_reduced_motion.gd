extends "res://tests/test_presentation.gd"

# Full three-condition sessions with reduced motion on: camera, survey drawer,
# piece pops, and key lifts become immediate; research-paced delivery and
# resolution sequences keep their durations and still complete normally.
func run() -> void:
	UIkit.set_reduced_motion(true)
	check(UIkit.reduced_motion() and UIkit.motion(0.5) == 0.0,"Reduced motion removes interface tweens")
	capture_dir = "/tmp/cascade-reduced-motion"
	await super.run()
