@tool
class_name TickNum
extends RefCounted
## Arbitrary-magnitude number for idle/incremental games.
##
## Two internal modes, chosen automatically:
## - [b]native[/b]: |value| < 1e300 is stored as a plain 64-bit float, so everyday
##   maths has normal float precision (whole numbers up to 2^53 are represented
##   exactly), so simple sums like 15 + fifteen 1s stay 30 instead of drifting.
## - [b]big[/b]: larger values are stored as [code]mantissa * 10^exponent[/code]
##   (1 <= |mantissa| < 10, 64-bit int exponent), so numbers like 1e1000000 work.
##
## [member mantissa] and [member exponent] are read-only and valid in both modes
## (computed lazily for native values, for display).
## TickNum values are immutable: every operation returns a new TickNum.
## [codeblock]
## var gold := TickNum.of("1.5e420")
## var more := gold.mul(2).add(TickNum.of(10))
## print(TickFormat.format(more))   # "3.00e420"
## [/codeblock]

const LN10 := 2.302585092994046
## Exponent difference beyond which the smaller operand cannot change a sum.
const PRECISION_DIGITS := 17
## Absolute values smaller than this are treated as zero.
const TINY := 1e-300
## Values with |value| below this are stored natively as floats.
const NATIVE_LIMIT := 1e300
const NATIVE_MAX_EXPONENT := 299

## Normalised mantissa (1 <= |mantissa| < 10, or 0). Read-only.
var mantissa: float:
	get:
		if not _normed:
			_ensure_norm()
		return _m
	set(_v):
		push_error("TickNum is immutable")

## Base-10 exponent. Read-only.
var exponent: int:
	get:
		if not _normed:
			_ensure_norm()
		return _e
	set(_v):
		push_error("TickNum is immutable")

var _native: bool = true
var _f: float = 0.0
var _m: float = 0.0
var _e: int = 0
var _normed: bool = true


## [code]TickNum.new(x)[/code] stores a float value; [code]TickNum.new(m, e)[/code]
## stores m * 10^e.
func _init(p_mantissa: float = 0.0, p_exponent: int = 0) -> void:
	if p_exponent == 0:
		_set_float(p_mantissa)
		return
	_m = p_mantissa
	_e = p_exponent
	_normalize_big()
	if _m != 0.0 and _e <= NATIVE_MAX_EXPONENT:
		_set_float(_m * pow(10.0, _e))


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

## Converts int, float, String ("12", "1.5e300", "-2E-3"), Dictionary
## ({"m": .., "e": ..}) or TickNum into a TickNum. Invalid input gives 0 and an error.
static func of(value: Variant) -> TickNum:
	match typeof(value):
		TYPE_OBJECT:
			if value is TickNum:
				return value
		TYPE_FLOAT:
			return TickNum.new(value, 0)
		TYPE_INT:
			return TickNum.new(float(value), 0)
		TYPE_STRING, TYPE_STRING_NAME:
			return TickNum.parse(String(value))
		TYPE_DICTIONARY:
			return TickNum.from_dict(value)
	push_error("TickNum.of: unsupported value %s" % [value])
	return TickNum.new()


static func zero() -> TickNum:
	return TickNum.new(0.0, 0)


static func one() -> TickNum:
	return TickNum.new(1.0, 0)


## Builds a value from its base-10 logarithm (value = 10^log_value).
static func from_log10(log_value: float) -> TickNum:
	if is_nan(log_value) or is_inf(log_value):
		if log_value < 0.0:
			return TickNum.new()
		push_error("TickNum.from_log10: non-finite input %s" % log_value)
		return TickNum.new()
	if log_value < 299.0 and log_value > -299.0:
		return TickNum.new(pow(10.0, log_value), 0)
	var e := floori(log_value)
	return TickNum.new(pow(10.0, log_value - e), e)


## Parses "123", "1.5e300", "-4.2E-7", "1e1000000". Whitespace and "_" / ","
## digit separators are ignored. Also reads the exact forms written by
## [method to_exact_string]. Returns 0 (with an error) for invalid text.
static func parse(text: String) -> TickNum:
	var t := text.strip_edges().replace("_", "").replace(",", "")
	var marker := t.find("#")
	if marker == -1:
		marker = t.find("@")
	if marker != -1:
		var exact := _parse_exact(t.substr(0, marker), t.substr(marker + 1), t[marker])
		if exact != null:
			return exact
		t = t.substr(0, marker)
	if t.is_empty():
		push_error("TickNum.parse: empty string")
		return TickNum.new()
	var epos := t.to_lower().find("e")
	var mant_text := t if epos == -1 else t.substr(0, epos)
	var exp_text := "0" if epos == -1 else t.substr(epos + 1)
	if not mant_text.is_valid_float() or not exp_text.is_valid_int():
		push_error("TickNum.parse: invalid number '%s'" % text)
		return TickNum.new()
	var e := exp_text.to_int()
	if absi(e) <= 280:
		# Let Godot parse the whole literal as one float (most precise).
		return TickNum.new(t.to_float(), 0)
	return TickNum.new(mant_text.to_float(), e)


static func _parse_exact(readable: String, bits_text: String, kind: String) -> TickNum:
	if not bits_text.is_valid_int():
		return null
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, bits_text.to_int())
	var x := b.decode_double(0)
	if is_nan(x) or is_inf(x):
		return null
	if kind == "#":
		if absf(x) >= NATIVE_LIMIT:
			return null
		return TickNum.new(x, 0)
	# "@": x is the mantissa; exponent comes from the readable part.
	var epos := readable.to_lower().find("e")
	var exp_text := "0" if epos == -1 else readable.substr(epos + 1)
	if not exp_text.is_valid_int() or absf(x) < 1.0 or absf(x) >= 10.0:
		return null
	return TickNum.new(x, exp_text.to_int())


static func from_dict(d: Dictionary) -> TickNum:
	if not d.has("m") or not d.has("e"):
		push_error("TickNum.from_dict: missing 'm'/'e' keys")
		return TickNum.new()
	return TickNum.new(float(d["m"]), int(d["e"]))


func to_dict() -> Dictionary:
	return {"m": mantissa, "e": exponent}


func duplicate_num() -> TickNum:
	if _native:
		return TickNum.new(_f, 0)
	return TickNum.new(_m, _e)


## True when stored as a plain float (|value| < 1e300).
func is_native() -> bool:
	return _native


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

func _set_float(x: float) -> void:
	if is_nan(x) or is_inf(x):
		push_error("TickNum: non-finite value %s; using 0" % x)
		x = 0.0
	if absf(x) < TINY:
		x = 0.0
	if absf(x) >= NATIVE_LIMIT:
		_m = x
		_e = 0
		_normalize_big()
		return
	_native = true
	_f = x
	_normed = x == 0.0
	_m = 0.0
	_e = 0


## Computes the display mantissa/exponent of a native value.
func _ensure_norm() -> void:
	_normed = true
	_m = _f
	_e = 0
	if _f == 0.0:
		return
	var a := absf(_f)
	if a >= 1.0 and a < 10.0:
		return
	var k := floori(log(a) / LN10)
	_m = _f / pow(10.0, k)
	_e = k
	if absf(_m) >= 10.0:
		_m /= 10.0
		_e += 1
	elif absf(_m) < 1.0:
		_m *= 10.0
		_e -= 1


func _normalize_big() -> void:
	_native = false
	_normed = true
	if is_nan(_m) or is_inf(_m):
		push_error("TickNum: non-finite mantissa %s; using 0" % _m)
		_m = 0.0
		_e = 0
	var a := absf(_m)
	if a == 0.0:
		_m = 0.0
		_e = 0
		_native = true
		_f = 0.0
		return
	if a < 1.0 or a >= 10.0:
		var k := floori(log(a) / LN10)
		# Two-step scaling avoids overflow/underflow of 10^k for extreme floats.
		if k > 300 or k < -300:
			var half := k / 2
			_m = _m / pow(10.0, half) / pow(10.0, k - half)
		else:
			_m = _m / pow(10.0, k)
		_e += k
		# Correct floating error in the log estimate.
		if absf(_m) >= 10.0:
			_m /= 10.0
			_e += 1
		elif absf(_m) < 1.0:
			_m *= 10.0
			_e -= 1
	if _e < -300:
		_m = 0.0
		_e = 0
		_native = true
		_f = 0.0


# ---------------------------------------------------------------------------
# Arithmetic (all return new values)
# ---------------------------------------------------------------------------

func add(other: Variant) -> TickNum:
	var b: TickNum = other if other is TickNum else TickNum.of(other)
	if _native and b._native:
		var r := _f + b._f
		if absf(r) < NATIVE_LIMIT:
			return TickNum.new(r, 0)
	if is_zero():
		return b.duplicate_num()
	if b.is_zero():
		return duplicate_num()
	var am := mantissa
	var ae := exponent
	var bm := b.mantissa
	var be := b.exponent
	if be > ae:
		var tm := am
		var te := ae
		am = bm
		ae = be
		bm = tm
		be = te
	var diff := ae - be
	if diff > PRECISION_DIGITS:
		return TickNum.new(am, ae)
	return TickNum.new(am + bm / pow(10.0, diff), ae)


func sub(other: Variant) -> TickNum:
	var b: TickNum = other if other is TickNum else TickNum.of(other)
	if _native and b._native:
		var r := _f - b._f
		if absf(r) < NATIVE_LIMIT:
			return TickNum.new(r, 0)
	return add(b.neg())


func mul(other: Variant) -> TickNum:
	var b: TickNum = other if other is TickNum else TickNum.of(other)
	if _native and b._native:
		var r := _f * b._f
		if absf(r) < NATIVE_LIMIT and (absf(r) >= TINY or _f == 0.0 or b._f == 0.0):
			return TickNum.new(r, 0)
	if is_zero() or b.is_zero():
		return TickNum.new()
	return TickNum.new(mantissa * b.mantissa, exponent + b.exponent)


func div(other: Variant) -> TickNum:
	var b: TickNum = other if other is TickNum else TickNum.of(other)
	if b.is_zero():
		push_error("TickNum.div: division by zero")
		return TickNum.new()
	if is_zero():
		return TickNum.new()
	if _native and b._native:
		var r := _f / b._f
		if absf(r) < NATIVE_LIMIT and absf(r) >= TINY:
			return TickNum.new(r, 0)
	return TickNum.new(mantissa / b.mantissa, exponent - b.exponent)


func neg() -> TickNum:
	if _native:
		return TickNum.new(-_f, 0)
	return TickNum.new(-_m, _e)


func abs_num() -> TickNum:
	if _native:
		return TickNum.new(absf(_f), 0)
	return TickNum.new(absf(_m), _e)


## Raises the value to a real power. Negative bases need an integer power.
func pow_num(power: float) -> TickNum:
	if is_zero():
		return TickNum.new() if power > 0.0 else TickNum.one()
	if is_negative():
		var ip := roundi(power)
		if not is_equal_approx(power, float(ip)):
			push_error("TickNum.pow_num: negative base with non-integer power")
			return TickNum.new()
		var r := abs_num().pow_num(power)
		return r.neg() if ip % 2 != 0 else r
	if _native:
		var r := pow(_f, power)
		if is_finite(r) and r < NATIVE_LIMIT and r >= TINY:
			return TickNum.new(r, 0)
	return TickNum.from_log10(log10() * power)


func sqrt_num() -> TickNum:
	return pow_num(0.5)


## Base-10 logarithm. Returns -INF for zero and NAN for negative values.
func log10() -> float:
	if is_zero():
		return -INF
	if is_negative():
		return NAN
	if _native:
		return log(_f) / LN10
	return log(_m) / LN10 + float(_e)


func log10_abs() -> float:
	if is_zero():
		return -INF
	if _native:
		return log(absf(_f)) / LN10
	return log(absf(_m)) / LN10 + float(_e)


func floor_num() -> TickNum:
	if _native:
		return TickNum.new(floorf(_f), 0)
	return duplicate_num()


func ceil_num() -> TickNum:
	if _native:
		return TickNum.new(ceilf(_f), 0)
	return duplicate_num()


func round_num() -> TickNum:
	if _native:
		return TickNum.new(roundf(_f), 0)
	return duplicate_num()


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

## Returns -1, 0 or 1.
func cmp(other: Variant) -> int:
	var b: TickNum = other if other is TickNum else TickNum.of(other)
	if _native and b._native:
		if _f == b._f:
			return 0
		return 1 if _f > b._f else -1
	var sa := _sign()
	var sb := b._sign()
	if sa != sb:
		return 1 if sa > sb else -1
	if sa == 0:
		return 0
	# Same sign, at least one is big.
	var ea := exponent
	var eb := b.exponent
	var mag := 0
	if ea != eb:
		mag = 1 if ea > eb else -1
	else:
		var ma := absf(mantissa)
		var mb := absf(b.mantissa)
		if ma != mb:
			mag = 1 if ma > mb else -1
	return mag * sa


func _sign() -> int:
	var x := _f if _native else _m
	if x > 0.0:
		return 1
	if x < 0.0:
		return -1
	return 0


func gt(other: Variant) -> bool:
	return cmp(other) > 0


func gte(other: Variant) -> bool:
	return cmp(other) >= 0


func lt(other: Variant) -> bool:
	return cmp(other) < 0


func lte(other: Variant) -> bool:
	return cmp(other) <= 0


func eq(other: Variant) -> bool:
	return cmp(other) == 0


## Relative comparison, useful in tests and for float-noise tolerant checks.
func is_equal_approx_num(other: Variant, relative: float = 1e-9) -> bool:
	var b := TickNum.of(other)
	if is_zero() or b.is_zero():
		return is_zero() and b.is_zero()
	if _sign() != b._sign():
		return false
	return absf(log10_abs() - b.log10_abs()) <= relative / LN10 + 1e-15


func is_zero() -> bool:
	return _f == 0.0 if _native else _m == 0.0


func is_negative() -> bool:
	return _f < 0.0 if _native else _m < 0.0


func is_positive() -> bool:
	return _f > 0.0 if _native else _m > 0.0


static func max_of(a: Variant, b: Variant) -> TickNum:
	var x := TickNum.of(a)
	var y := TickNum.of(b)
	return x if x.gte(y) else y


static func min_of(a: Variant, b: Variant) -> TickNum:
	var x := TickNum.of(a)
	var y := TickNum.of(b)
	return x if x.lte(y) else y


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

## Converts to float. Values beyond float range return +/-INF.
func to_float() -> float:
	if _native:
		return _f
	if _e > 308:
		return INF if _m > 0.0 else -INF
	return _m * pow(10.0, _e)


## Converts to int, clamped to the 64-bit range.
func to_int() -> int:
	var x := to_float()
	if x >= 9.2e18:
		return 9223372036854775807
	if x <= -9.2e18:
		return -9223372036854775807
	return int(x)


## Readable text that parse() reads back ("1.2345e67"), accurate to ~1e-15.
## Use [method to_exact_string] when bit-exact round-trips matter.
func to_plain_string() -> String:
	if is_zero():
		return "0"
	return "%se%d" % [_float_repr(mantissa), exponent]


## Lossless text for saves: the readable value plus the raw 64-bit pattern of
## the stored float ("1.5e1#4624633867356078080" in native mode,
## "7.78e66767@4619..." in big mode). Godot's float-to-text conversion alone can
## differ in the last bit; storing the bits restores the same 64-bit value.
func to_exact_string() -> String:
	if is_zero():
		return "0"
	var b := PackedByteArray()
	b.resize(8)
	if _native:
		b.encode_double(0, _f)
		return "%s#%d" % [to_plain_string(), b.decode_s64(0)]
	b.encode_double(0, _m)
	return "%s@%d" % [to_plain_string(), b.decode_s64(0)]


func _to_string() -> String:
	return to_plain_string()


static func _float_repr(x: float) -> String:
	# 17 significant digits; trim trailing zeros.
	var s := "%.16f" % x
	if s.find(".") != -1:
		s = s.rstrip("0").rstrip(".")
	return s
