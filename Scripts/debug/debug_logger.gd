extends RefCounted
class_name DebugLogger
# CONTRACT NOTES (do not remove; add only):
# - Logging is observational only. It must not change gameplay state, order rules, or system contracts.
# - UI queues orders; TurnManager executes resolvers on Execute Month. Logger only records events.
#
# FILES:
# - user://kingdom_debug.log (human-readable)
# - user://kingdom_replay.jsonl (one JSON event per line, for replay/debugging)
#
# ADDITIONAL NOTES:
# - This script must avoid unqualified calls to `log(...)` inside methods because Godot exposes a global
#   math function `log()` (natural logarithm). Always call `DebugLogger.log(...)` explicitly.

static var _initialized: bool = false
static var _silent: bool = false  # when true, all logging is suppressed (used by AI lab)
static var _log_path: String = "user://kingdom_debug.log"
static var _replay_path: String = "user://kingdom_replay.jsonl"
static var _log_buffer: PackedStringArray = PackedStringArray()
static var _replay_buffer: PackedStringArray = PackedStringArray()
const _FLUSH_EVERY: int = 20  # flush to disk after this many lines

static func set_silent(silent: bool) -> void:
	_silent = silent


static func init(reset_files: bool = false) -> void:
	if _initialized:
		return
	_initialized = true
	# Flush any buffer from a prior session before wiping
	flush()
	_log_buffer.clear()
	_replay_buffer.clear()
	if reset_files:
		_reset_file(_log_path)
		_reset_file(_replay_path)
	# qualify to avoid global math log()
	DebugLogger.log("logger_init", {"reset": reset_files})

static func flush() -> void:
	if _log_buffer.size() > 0:
		_append_lines(_log_path, _log_buffer)
		_log_buffer.clear()
	if _replay_buffer.size() > 0:
		_append_lines(_replay_path, _replay_buffer)
		_replay_buffer.clear()

# Primary static API used across the project (e.g., MapDebugView)
static func log(message: String, data: Dictionary = {}) -> void:
	if _silent:
		return
	# Safe to call even before init()
	if not _initialized:
		# Do not reset files implicitly; just mark initialized
		_initialized = true
		# Ensure files exist
		_ensure_file(_log_path)
		_ensure_file(_replay_path)

	var ts := Time.get_datetime_string_from_system(true)
	var line := "[%s] %s" % [ts, message]
	if data.size() > 0:
		line += " " + JSON.stringify(data)

	_log_buffer.append(line)
	var evt := {"t": ts, "msg": message, "data": data}
	_replay_buffer.append(JSON.stringify(evt))
	if _log_buffer.size() >= _FLUSH_EVERY:
		flush()

# Instance-style helpers (used by GameState, which keeps a logger instance)
func event(name: String, data: Dictionary = {}) -> void:
	DebugLogger.log("event:" + name, data)

func order(order_type: String, data: Dictionary = {}) -> void:
	DebugLogger.log("order:" + order_type, data)

func stage_start(stage: String, data: Dictionary = {}) -> void:
	DebugLogger.log("stage_start:" + stage, data)

func stage_end(stage: String, data: Dictionary = {}) -> void:
	DebugLogger.log("stage_end:" + stage, data)

func metric(name: String, data: Dictionary = {}) -> void:
	DebugLogger.log("metric:" + name, data)

static func _ensure_file(path: String) -> void:
	if FileAccess.file_exists(path):
		return
	_reset_file(path)

static func _reset_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("") # truncate/create
		f.close()

static func _append_lines(path: String, lines: PackedStringArray) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return
	f.seek_end()
	f.store_string("\n".join(lines) + "\n")
	f.close()
