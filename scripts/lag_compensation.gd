extends RefCounted
## Read-only history: ray tests never teleport live actors or modify physics space.
const MAX_REWIND = .5
const HISTORY_SECONDS = .65
var history: Dictionary = {}
func clear() -> void:
	history.clear()
func record(slots: Array, time: float) -> void:
	for slot in slots:
		var actor = slot.get("actor")
		if not is_instance_valid(actor): continue
		var zones: Array = []
		for area in actor.hitboxes:
			var collision = area.get_child(0)
			var shape = collision.shape
			zones.append({"transform":area.global_transform*collision.transform,"head":area.get_meta("zone")=="head","radius":shape.radius if shape is SphereShape3D else 0.0,"size":shape.size if shape is BoxShape3D else Vector3.ZERO})
		if not history.has(slot.index): history[slot.index] = []
		var frames = history[slot.index]
		frames.append({"time":time,"instance":actor.get_instance_id(),"life":actor.life_id,"health":actor.health,"zones":zones})
		while frames.size()>48 or (frames.size()>2 and frames[1].time<time-HISTORY_SECONDS): frames.pop_front()
func sample(slot: int, actor: Node, time: float) -> Array:
	var frames = history.get(slot,[])
	if frames.is_empty() or time<frames[0].time: return []
	var a = frames[0]
	var b = a
	for frame in frames:
		if frame.time<=time: a = frame
		b = frame
		if frame.time>=time: break
	if a.instance!=actor.get_instance_id() or a.life!=actor.life_id or a.health<=0: return []
	if b.instance!=a.instance or b.life!=a.life: b = a
	var blend = clampf((time-a.time)/maxf(.001,b.time-a.time),0,1)
	var zones: Array = []
	for i in range(a.zones.size()):
		var zone = a.zones[i].duplicate()
		zone.transform = a.zones[i].transform.interpolate_with(b.zones[i].transform,blend)
		zone.size = a.zones[i].size.lerp(b.zones[i].size,blend)
		zones.append(zone)
	return zones
func raycast(slots: Array, origin: Vector3, direction: Vector3, distance: float, shooter: Node, time: float, excluded: Array[RID]) -> Dictionary:
	var result: Dictionary = {}
	var nearest = distance
	for slot in slots:
		var actor = slot.get("actor")
		if not is_instance_valid(actor) or actor==shooter or actor.health<=0: continue
		var zones = sample(slot.index,actor,time)
		for i in range(zones.size()):
			var area = actor.hitboxes[i]
			if area.get_rid() in excluded: continue
			var zone = zones[i]
			var inverse = zone.transform.affine_inverse()
			var local_origin = inverse*origin
			var local_direction = inverse.basis*direction
			var t = sphere_distance(local_origin,local_direction,zone.radius) if zone.head else box_distance(local_origin,local_direction,zone.size)
			if t>=0 and t<nearest:
				nearest = t
				result = {"position":origin+direction*t,"normal":-direction,"collider":area,"rid":area.get_rid(),"headshot":zone.head}
	return result
static func sphere_distance(origin: Vector3, direction: Vector3, radius: float) -> float:
	var a = direction.length_squared()
	var b = origin.dot(direction)
	var c = origin.length_squared()-radius*radius
	var discriminant = b*b-a*c
	if a<.000001 or discriminant<0: return -1
	var t = (-b-sqrt(discriminant))/a
	return t if t>=0 else (0.0 if c<=0 else -1.0)
static func box_distance(origin: Vector3, direction: Vector3, size: Vector3) -> float:
	var enter = 0.0
	var leave = INF
	for axis in range(3):
		var half = size[axis]*.5
		if absf(direction[axis])<.000001:
			if absf(origin[axis])>half: return -1
			continue
		var a = (-half-origin[axis])/direction[axis]
		var b = (half-origin[axis])/direction[axis]
		enter = maxf(enter,minf(a,b))
		leave = minf(leave,maxf(a,b))
		if enter>leave: return -1
	return enter
