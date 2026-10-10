extends RefCounted

static func answers(game: GameManager, text: String = "Not sure") -> Dictionary:
	var result := {}
	for q in game.post_form_questions():
		result[q.id] = q.options[0] if q.has("options") else text
	return result

# Existing mechanics tests still traverse the real barriers with synthetic answers.
static func finish(game: GameManager) -> void:
	for _form in 6:
		if game.post_form_kind() == "": return
		game.open_private_form()
		assert(game.submit_post_form(game.post_form_key(),answers(game)))

static func advance(game: GameManager) -> void:
	game.next_round()
	finish(game)
