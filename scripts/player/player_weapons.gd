class_name PlayerWeapons
extends RefCounted
## What the equipped weapon changes: the behaviour graph, and the animation the
## rig plays for it.
##
## Owned by PlayerController, which keeps the attack state machine itself - this
## layer owns only the graph and the clips it needs loaded. Dependency is one
## way: this knows about CharacterAnimRig, the rig knows nothing about weapons.
## Pre: bind() before set_graph(); everything else is safe on an unbound layer.

## The equipped weapon's behaviour graph: which take is playing and what chains
## into what. Never null once set_graph() has run - with nothing equipped it holds
## WeaponConfig.defaults(), a single sword swing, so the attack path has one code
## path rather than a branch for "no weapon".
var graph: WeaponGraph
## Swings started since this body was built. Read by the network layer to spot
## the edge without replicating the graph itself.
var strokes := 0

var _rig: CharacterAnimRig


func bind(rig: CharacterAnimRig) -> void:
	_rig = rig


## Loads weapon behavior graph configuration into the swing layer's slots.
## Post: graph != null. Caller handles a swing that was running when this landed.
func set_graph(config: Dictionary) -> void:
	graph = WeaponGraph.parse(config if not config.is_empty()
		else WeaponConfig.defaults())
	if _rig == null or _rig.player == null:
		return

	var lengths := {}
	for i in graph.order.size():
		if i >= _rig.slots.size():
			break
		var id: String = graph.order[i]
		var action := graph.action_of(id)
		var full: String = _rig.visual.call("resolve", action.clip)
		if full == "":
			push_warning("%s: weapon action '%s' wants missing clip '%s'" % [
				_rig.visual.name, id, action.clip])
			continue
		var take := _rig.player.get_animation(full)
		# A take that loops never reaches its own end, and the transition would
		# hold it there for as long as the node runs.
		take.loop_mode = Animation.LOOP_NONE
		# Idempotent, which matters: the same clip is re-flattened every time any
		# weapon using it is equipped. See CharacterAnimRig.flatten().
		_rig.flatten(take, CharacterAnimRig.flatten_mode(action.flatten))
		_rig.slots[i].animation = full
		lengths[id] = take.length
	# The blink's own time is added on top of these by resolve_spans().
	graph.resolve_spans(lengths)


## Stance layer weight at rest. 0 is bare-handed.
##
## Not written to the tree here: the controller scales it by gait every frame,
## because a stance take that stays at full strength while the character runs
## replaces the run's arms with a standing pose.
func set_stance(blend_amount: float) -> void:
	if _rig != null:
		_rig.stance_weight = clampf(blend_amount, 0.0, 1.0)


## Replaces the idle / walk / sprint poles of the gait blend space with the
## weapon's own clips. Empty or missing names restore the bare-handed defaults.
##
## This is what lets an armed idle reach the legs: filtering the stance layer onto
## the Spine subtree can only ever reach the torso, so the lower body has to come
## from the pole itself.
func set_locomotion(idle_clip: String, walk_clip: String, run_clip: String) -> void:
	if _rig == null:
		return
	_rig.set_pole(CharacterAnimRig.P_IDLE, idle_clip, CharacterAnimRig.CLIP_IDLE)
	_rig.set_pole(CharacterAnimRig.P_WALK, walk_clip, CharacterAnimRig.CLIP_WALK)
	_rig.set_pole(CharacterAnimRig.P_RUN, run_clip, CharacterAnimRig.CLIP_RUN)


func set_stance_clip(clip: String) -> void:
	if _rig != null:
		_rig.set_stance_clip(clip)


func set_stance_filter(bone_name: String) -> void:
	if _rig != null:
		_rig.set_stance_filter(bone_name)


# --- what the damage system asks --------------------------------------------

## The graph node playing now, "" at rest.
func current_action() -> String:
	return graph.current if graph != null else ""


## Whether the take running now is inside a window that may connect.
func can_deal_damage(attacking: bool) -> bool:
	return attacking and graph != null and graph.can_deal_damage()


func register_hit() -> void:
	if graph != null:
		graph.register_hit()


func is_in_link_window() -> bool:
	return graph != null and graph.is_in_link_window()


func reset() -> void:
	if graph != null:
		graph.reset()
