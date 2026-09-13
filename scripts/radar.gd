extends RefCounted
## Server-owned firing pings: last shot location, never live enemy tracking.
const REVEAL_SECONDS = 2.0
var shots: Dictionary = {}
var remote: Array = []
var remote_at = 0
func clear() -> void:
	shots.clear()
	remote.clear()
func mark(actor: Node3D, now: float) -> void:
	shots[actor.get_instance_id()] = {"position":actor.global_position,"until":now+REVEAL_SECONDS,"life":actor.get("life_id")}
func contacts(actors: Array, team: int, now: float) -> Array:
	for id in shots.keys():
		if shots[id].until<=now or not is_instance_id_valid(id): shots.erase(id)
	var result: Array = []
	for actor in actors:
		if not is_instance_valid(actor) or actor.health<=0: continue
		if actor.team==team:
			result.append([actor.global_position,true,1.0])
		else:
			var shot = shots.get(actor.get_instance_id(),{})
			if not shot.is_empty() and shot.life==actor.get("life_id"):
				result.append([shot.position,false,shot.until-now])
	return result
