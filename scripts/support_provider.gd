class_name SupportProvider
extends RefCounted

# Callback interface: completion may occur later; GameManager owns reveal/timing guards.
func request(_context: Dictionary, _condition: String, _identity: Dictionary, done: Callable) -> void:
	done.call({"error":"missing_provider_configuration"})
