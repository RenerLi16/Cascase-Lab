class_name MockSupportProvider
extends SupportProvider

var calls := 0

func request(context: Dictionary, condition: String, _identity: Dictionary, done: Callable) -> void:
	calls += 1
	var source := SupportLibrary.generate(context,condition)
	var first := "讨论: 开发模拟输出。请比较初始判断的依据；如果意见一致，请检查共同依赖的假设，不必人为制造分歧。"
	if condition == "DIRECT_RECOMMENDATION":
		first = "建议: 开发模拟输出。可考虑执行 %s，目标 %s。建议只依据当前公开资料，仍需检查资源和通路。" % [source.action,source.target]
	source.text = first + "\n依据: 已核实的记录只说明当时情况，未知状态仍然未知，公开信息不足以判断所有地点现在是否安全。\n核对: 请结合记录时间、开放道路与剩余物资检查判断依据。此离线测试消息没有观察讨论过程，也没有访问隐藏状态。"
	source.provider = "mock"
	source.model = "development-mock"
	source.template_id = "development.mock"
	done.call(source)
