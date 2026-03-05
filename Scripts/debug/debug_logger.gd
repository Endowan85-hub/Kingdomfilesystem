class_name DebugLogger
extends RefCounted

# Simple persistent logger for reproducing crashes.
# Writes to: user://kingdom_debug.log

static var enabled: bool = true
static var _path: String = "user://kingdom_debug.log"

static func log(msg: String) -> void:
	if not enabled:
		return
	var line: String = "%s | %s\n" % [_ts(), msg]
	# Also mirror to editor output for quick inspection.
	print(line.strip_edges())
	var f := FileAccess.open(_path, FileAccess.READ_WRITE)
	if f == null:
		# If file doesn't exist, create it.
		f = FileAccess.open(_path, FileAccess.WRITE)
		if f == null:
			return
	else:
		f.seek_end()
	f.store_string(line)
	f.flush()

static func clear() -> void:
	if not enabled:
		return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string("")
		f.flush()

static func path() -> String:
	return _path

static func _ts() -> String:
	return Time.get_datetime_string_from_system(true)
