extends RefCounted
## One copy of the LAN message checks that two or more classes need (audit A12).

## True for a whole number from 0 to size - 1. A float or a string is refused.
static func is_index(value, size: int) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value < size

## True when the message has exactly these fields, no more and no fewer.
static func only_fields(msg: Dictionary, fields: Array) -> bool:
	if msg.size() != fields.size(): return false
	return fields.all(func(field): return msg.has(field))
