extends RefCounted
## Render-only interpolation. Applying a pose never moves collision shapes.
var previous = Transform3D.IDENTITY
var current = Transform3D.IDENTITY
var ready = false
func reset(pose: Transform3D) -> void:
	previous=pose; current=pose; ready=true
func begin_tick(pose: Transform3D) -> void:
	if not ready or pose.origin.distance_squared_to(current.origin)>4: reset(pose)
	previous=current
func end_tick(pose: Transform3D) -> void:
	current=pose
func sample(pose: Transform3D, fraction: float) -> Transform3D:
	if not ready or pose.origin.distance_squared_to(current.origin)>4: reset(pose)
	return previous.interpolate_with(current,clampf(fraction,0,1))
func apply(visual: Node3D, body: Node3D, fraction: float) -> void:
	visual.global_transform=sample(body.global_transform,fraction)
