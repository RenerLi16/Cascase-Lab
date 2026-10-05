class_name BackendSupportProvider
extends SupportProvider

var transport: Node

func _init(client: Node) -> void:
	transport = client

func request(context: Dictionary, condition: String, identity: Dictionary, done: Callable) -> void:
	var result: Dictionary = await transport.request_support(context,condition,identity)
	if done.is_valid(): done.call(result)
