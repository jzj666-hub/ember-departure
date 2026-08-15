class_name WeaponGraph
extends RefCounted
## Runtime weapon behavior graph managing active nodes, edges (trigger windows), and input buffers.
## Completely decoupled from AnimationTree/PlayerController.

## Normalized actions dictionary indexed by id.
var actions := {}
## Action IDs in declaration order (matches AnimationTree slots).
var order: PackedStringArray = []
## Entry transition map (button name -> action id).
var entries := {}

## The node playing now, "" when the weapon is at rest.
var current := ""
## Seconds since `current` started.
var elapsed := 0.0

## Action node durations in seconds.
var _spans := {}
## Target action ID of buffered input.
## Time stamp when the buffered input becomes active.
var _pending := ""
var _pending_at := 0.0


## Parses weapon config dictionary into WeaponGraph instance.
static func parse(config: Dictionary) -> WeaponGraph:
	var normalised := WeaponConfig.normalise(config)
	var graph := WeaponGraph.new()
	for action in normalised.actions:
		graph.actions[action.id] = action
		graph.order.append(action.id)
		# Until resolve_spans() runs, an explicit duration is honoured and
		# everything else gets a second. Not a real answer, but a terminating one:
		# a span of zero would leave a node that never ends.
		graph._spans[action.id] = action.duration if action.duration > 0.0 else 1.0
	for entry in normalised.entries:
		graph.entries[entry.trigger] = entry.to
	return graph


## Resolves node durations using real AnimationTree clip lengths and play rates.
##
## The lunge runs inside the take, not before it: the body slides while the take
## plays, so a node is exactly as long as what it plays and `dash_distance` adds
## nothing here.
func resolve_spans(clip_lengths: Dictionary) -> void:
	for id in order:
		var action: Dictionary = actions[id]
		if action.duration > 0.0:
			_spans[id] = action.duration
			continue
		var length := float(clip_lengths.get(id, 0.0))
		_spans[id] = length / action.rate if length > 0.01 else 1.0


func span_of(id: String) -> float:
	return float(_spans.get(id, 1.0))


## Returns AnimationTree slot index for action node ID.
func slot_of(id: String) -> int:
	var index := order.find(id)
	return index


func action_of(id: String) -> Dictionary:
	return actions.get(id, {})


func is_empty() -> bool:
	return order.is_empty()


## Returns entry action node ID if any active button matches entry conditions.
func begin(buttons: int) -> String:
	for trigger in entries:
		if _pressed(buttons, trigger):
			return entries[trigger]
	return ""


## Sets current playing action node and resets timer.
func enter(id: String) -> void:
	current = id
	elapsed = 0.0
	_pending = ""
	_pending_at = 0.0


## Advances clock and processes link windows/buffers. Returns target node ID or "".
func advance(delta: float, buttons: int) -> String:
	if current.is_empty():
		return ""
	elapsed += delta
	var links: Array = actions[current].links

	for link in links:
		if not _pressed(buttons, link.trigger):
			continue
		var start: float = link.window[0]
		var end: float = link.window[1]
		if elapsed >= start and elapsed <= end:
			return link.to
		if elapsed < start and link.buffer:
			_pending = link.to
			_pending_at = start
		# Terminate search on first matching button.
		break

	# Process buffered inputs.
	if not _pending.is_empty() and elapsed >= _pending_at:
		var queued := _pending
		_pending = ""
		return queued
	return ""


## Returns true if current action node duration has elapsed.
func finished() -> bool:
	return current.is_empty() or elapsed >= span_of(current)


## Resets graph play state.
func reset() -> void:
	current = ""
	elapsed = 0.0
	_pending = ""
	_pending_at = 0.0


func _pressed(buttons: int, trigger: String) -> bool:
	var bit: int = CharacterIntent.BUTTONS.get(trigger, 0)
	return bit != 0 and (buttons & bit) != 0
