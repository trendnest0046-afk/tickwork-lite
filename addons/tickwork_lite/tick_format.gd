@tool
class_name TickFormat
extends RefCounted
## Number formatting for idle games: suffixes, scientific, engineering, letters.
##
## [codeblock]
## TickFormat.format(TickNum.of("1234567"))                       # "1.23M"
## TickFormat.format(TickNum.of("1e45"), TickFormat.Style.SCIENTIFIC) # "1.00e45"
## TickFormat.default_style = TickFormat.Style.LETTERS             # global player setting
## [/codeblock]

enum Style {
	SUFFIX,       ## 1.23K, 4.56M ... falls back to scientific past the suffix table
	SCIENTIFIC,   ## 1.23e45
	ENGINEERING,  ## 12.3e45 (exponent is a multiple of 3)
	LETTERS,      ## K, M, B, T, then aa, ab, ac ... zz, aaa ...
	FULL,         ## 1,234,567 (scientific above FULL_LIMIT_EXPONENT)
}

## Short-scale suffixes. Index i means 10^(3*i).
const SUFFIXES: PackedStringArray = [
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No",
	"Dc", "UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc",
	"Vg", "UVg", "DVg", "TVg", "QaVg", "QiVg", "SxVg", "SpVg", "OcVg", "NoVg",
	"Tg", "UTg", "DTg", "TTg", "QaTg", "QiTg", "SxTg", "SpTg", "OcTg", "NoTg",
	"Qd", "UQd", "DQd", "TQd", "QaQd", "QiQd", "SxQd", "SpQd", "OcQd", "NoQd",
	"Qq", "UQq", "DQq", "TQq", "QaQq", "QiQq", "SxQq", "SpQq", "OcQq", "NoQq",
	"Sg", "USg", "DSg", "TSg", "QaSg", "QiSg", "SxSg", "SpSg", "OcSg", "NoSg",
	"St", "USt", "DSt", "TSt", "QaSt", "QiSt", "SxSt", "SpSt", "OcSt", "NoSt",
	"Og", "UOg", "DOg", "TOg", "QaOg", "QiOg", "SxOg", "SpOg", "OcOg", "NoOg",
	"Nn", "UNn", "DNn", "TNn", "QaNn", "QiNn", "SxNn", "SpNn", "OcNn", "NoNn",
	"Ce",
]
const FULL_LIMIT_EXPONENT := 15
const LETTERS_ALPHABET := "abcdefghijklmnopqrstuvwxyz"

## Global defaults used when a call does not pass its own arguments.
static var default_style: Style = Style.SUFFIX
static var default_decimals: int = 2
## Values below this are printed plainly (e.g. "999" or "12.5").
static var plain_below: float = 1000.0
## Remove trailing zeros: "1.50K" -> "1.5K".
static var trim_zeros: bool = false


## Formats a TickNum (or anything TickNum.of accepts).
## [param style] -1 uses [member default_style]; [param decimals] -1 uses [member default_decimals].
static func format(value: Variant, style: int = -1, decimals: int = -1) -> String:
	var n := TickNum.of(value)
	var st: int = default_style if style < 0 else style
	var dec: int = default_decimals if decimals < 0 else decimals
	if n.is_zero():
		return "0"
	var sign_text := "-" if n.is_negative() else ""
	var a := n.abs_num()
	if a.lt(plain_below) and st != Style.FULL:
		return sign_text + _plain_small(a.to_float(), dec)
	match st:
		Style.SCIENTIFIC:
			return sign_text + _scientific(a, dec)
		Style.ENGINEERING:
			return sign_text + _engineering(a, dec)
		Style.LETTERS:
			return sign_text + _tiered(a, dec, true)
		Style.FULL:
			if a.exponent >= FULL_LIMIT_EXPONENT:
				return sign_text + _scientific(a, dec)
			return sign_text + _group_thousands(a.round_num().to_int())
		_:
			return sign_text + _tiered(a, dec, false)


## Formats a per-second rate, e.g. "1.23K/s".
static func rate(value: Variant, style: int = -1, decimals: int = -1) -> String:
	return format(value, style, decimals) + "/s"


## Formats seconds as "1d 02h", "3h 04m", "5m 06s" or "7s".
static func duration(seconds: float) -> String:
	if is_inf(seconds) or is_nan(seconds):
		return "never"
	var s := maxi(0, floori(seconds))
	var d := s / 86400
	var h := (s % 86400) / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if d > 0:
		return "%dd %02dh" % [d, h]
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm %02ds" % [m, sec]
	return "%ds" % sec


## Formats seconds as a fixed "HH:MM:SS" clock (hours can exceed 24).
static func clock(seconds: float) -> String:
	var s := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]


# ---------------------------------------------------------------------------

static func _fixed(x: float, dec: int) -> String:
	var s := ("%." + str(dec) + "f") % x
	if trim_zeros and s.find(".") != -1:
		s = s.rstrip("0").rstrip(".")
	return s


static func _plain_small(x: float, dec: int) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return _fixed(x, dec)


## Returns [mantissa_rounded, exponent] with rounding carried into the exponent,
## so 9.996e5 at 2 decimals becomes [1.0, 6] instead of "10.00e5".
static func _rounded(a: TickNum, dec: int, step: int) -> Array:
	var e := a.exponent
	var shift := posmod(e, step)
	var base_e := e - shift
	var m := a.mantissa * pow(10.0, shift)
	var factor := pow(10.0, dec)
	var mr := roundf(m * factor) / factor
	if mr >= pow(10.0, step):
		mr /= pow(10.0, step)
		base_e += step
	return [mr, base_e]


static func _scientific(a: TickNum, dec: int) -> String:
	var r := _rounded(a, dec, 1)
	return "%se%d" % [_fixed(r[0], dec), r[1]]


static func _engineering(a: TickNum, dec: int) -> String:
	var r := _rounded(a, dec, 3)
	return "%se%d" % [_fixed(r[0], dec), r[1]]


static func _tiered(a: TickNum, dec: int, letters: bool) -> String:
	var r := _rounded(a, dec, 3)
	var tier: int = int(r[1]) / 3
	var suffix := ""
	if letters:
		suffix = _letter_suffix(tier)
	else:
		if tier >= SUFFIXES.size():
			return _scientific(a, dec)
		suffix = SUFFIXES[tier]
	return _fixed(r[0], dec) + suffix


## K, M, B, T for tiers 1-4, then aa, ab, ... zz, aaa, ...
static func _letter_suffix(tier: int) -> String:
	if tier <= 4:
		return SUFFIXES[tier]
	var idx := tier - 5
	var length := 2
	var block := 26 * 26
	while idx >= block:
		idx -= block
		length += 1
		block *= 26
	var out := ""
	for i in length:
		out = LETTERS_ALPHABET[idx % 26] + out
		idx /= 26
	return out


static func _group_thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out
