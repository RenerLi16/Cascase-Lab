class_name FirstPlayText
extends RefCounted

# Only orientation copy is localized here. Research instruments stay unchanged.
static var chinese := false
static func choose(english: String, simplified: String) -> String:
	return simplified if chinese else english
static func premise() -> String:
	return choose("You coordinate an outbreak response. Roads carry both infection and supplies. Work together to keep shelters functioning through three rounds, using only six supplies.","你们负责协调疫情应对。道路既运输物资，也传播感染。你们需要共同使用仅有的六份物资，让避难所在三轮中维持运作。")
