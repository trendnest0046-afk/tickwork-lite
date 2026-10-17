# Tickwork Lite (free, MIT)

Big numbers and number formatting for Godot 4 idle/incremental games. This is a free sample of **Tickwork**, the full framework: https://terminator046.itch.io/tickwork (free Lite page: https://terminator046.itch.io/tickwork-lite).

- `TickNum`: numbers far beyond float range. Plain 64-bit floats below 1e300 (whole numbers up to 2^53 represented exactly), mantissa × 10^exponent above (64-bit exponent; 1e1000000 tested). About 15–16 significant digits.
- `TickFormat`: `1.23M`, `1.23e45`, `12.3e45`, `1.23aa`, `1,234,567`, durations such as `1h 02m`. Rounding carries correctly (999,999 shows as `1.00M`).

Tested on Godot 4.7.2.

## Install
Copy `addons/tickwork_lite` into your project. No plugin needs enabling: the classes register automatically.

```gdscript
var gold := TickNum.of("1.5e420")
gold = gold.mul(3).add(1000)
print(TickFormat.format(gold))                              # 4.50e420
print(TickFormat.format(1234567))                           # 1.23M
print(TickFormat.format(TickNum.parse("1e18"), TickFormat.Style.LETTERS))  # 1.00ab
if gold.gte(TickNum.of(1e300)):
	print("rich")
```
Saving: store `n.to_exact_string()` and read it back with `TickNum.parse(text)`. It stores the raw 64-bit value; in our tests, values came back bit-for-bit.

Run the example: `godot --headless --path . --script res://examples/lite_example.gd`

## Full version
**Tickwork** adds generators, upgrades, achievements, prestige layers, offline progress, versioned saves with backup fallback, a complete demo game, and a **headless balancing simulator** that tells you when players reach each unlock and where they will hit a wall.

If you later install the full Tickwork, delete `addons/tickwork_lite` first. Both define `TickNum` and `TickFormat`.
