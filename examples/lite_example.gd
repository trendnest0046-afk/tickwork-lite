extends SceneTree
# Tickwork Lite example: run with
#   godot --headless --path . --script res://examples/lite_example.gd
func _init() -> void:
	var gold := TickNum.of(15)
	for i in 15:
		gold = gold.add(1)
	print("15 + fifteen 1s = ", TickFormat.format(gold), " (exact: ", gold.eq(30), ")")
	var huge := TickNum.parse("1.5e420").mul(3)
	print("1.5e420 x 3 = ", TickFormat.format(huge))
	for style in [TickFormat.Style.SUFFIX, TickFormat.Style.SCIENTIFIC, TickFormat.Style.ENGINEERING, TickFormat.Style.LETTERS, TickFormat.Style.FULL]:
		print(TickFormat.Style.keys()[style], ": ", TickFormat.format(TickNum.of(123456789), style))
	var saved := huge.to_exact_string()
	print("round trip exact: ", TickNum.parse(saved).eq(huge))
	print("2h 3m 4s -> ", TickFormat.duration(7384))
	quit()
