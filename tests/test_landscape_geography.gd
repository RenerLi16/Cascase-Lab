extends "res://tests/test_bridges.gd"

func run() -> void:
	for entry in ScenarioData.registry().scenarios:
		var data := ScenarioData.load_by_id(entry.id)
		geometry_checks(data)
		var view := NetworkView.new()
		view.configure(data,GameState.new(data))
		var bounds := Rect2(-WoodlandArt.PAD,-WoodlandArt.PAD,data.world_size[0]+WoodlandArt.PAD*2,data.world_size[1]+WoodlandArt.PAD*2)
		for size in [Vector2(1440,900),Vector2(1200,800)]:
			view.size = size
			for source in [false,true]:
				view.source_mode = source
				for zoom in [1.0,1.2,1.4,1.6,2.0,2.2]:
					view.zoom = zoom
					for corner in [Vector2(-9999,-9999),Vector2(9999,-9999),Vector2(9999,9999),Vector2(-9999,9999)]:
						view.camera_center = corner
						view._update_camera()
						for screen in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
							check(bounds.grow(0.01).has_point(view.to_world(screen)),"Painted terrain covers every camera boundary: "+entry.id)
		# Every inland path end joins another feature or tapers to an uphill rocky head.
		var features := WoodlandArt.features(data)
		for i in features.size():
			var feature: Dictionary = features[i]
			if feature.mode != "path": continue
			for end in [0,feature.points.size()-1]:
				var at: Vector2 = feature.points[end]
				if not bounds.has_point(at): continue
				var joined := false
				for j in features.size():
					if i != j and WoodlandArt.feature_distance(features[j],data,at,float(features[j].width)) <= 1: joined = true
				var head: bool = feature.kind == "ravine" and feature.has("scales") and feature.scales[end] < 0.1
				check(joined or head,"Inland water/ravine end has a connection or a tapered headwall: "+entry.id)
		# Non-adjacent roads may not cross or invent graph junctions.
		for a in view.state.edges.values():
			for b in view.state.edges.values():
				if a.from in [b.from,b.to] or a.to in [b.from,b.to]: continue
				var first := view.visual_road(a.id)
				var second := view.visual_road(b.id)
				for i in first.size()-1:
					for j in second.size()-1: check(Geometry2D.segment_intersects_segment(first[i],first[i+1],second[j],second[j+1]) == null,"No false road intersections")
		view.free()
	print("LANDSCAPE GEOGRAPHY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
