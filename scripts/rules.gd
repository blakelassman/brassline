extends RefCounted
## Movement and combat tuning shared by runtime and regression checks.

const FUSE = 1.25
const BLAST_RADIUS = 5.0
const PERFECT_WINDOW = 0.14
const GRAVITY = 24.0
const WALK_SPEED = 7.5
const JUMP_SPEED = 7.2
const HORIZONTAL_CAP = 24.0
const VERTICAL_CAP = 29.0
const JUMP_BUFFER = 0.10
const SCOPE_READY = 0.12
const WEAPONS = [
	{"name": "RIFLE", "body": 25, "head": 100, "mag": 24, "cooldown": 0.16, "reload": 1.45, "kick": 0.75},
	{"name": "HEAVY PISTOL", "body": 40, "head": 100, "mag": 7, "cooldown": 0.65, "reload": 1.65, "kick": 3.2},
	{"name": "SWORD", "body": 100, "head": 100, "mag": 0, "cooldown": 0.65, "reload": 0.0, "kick": 0.0},
	{"name": "LONGSHOT", "body": 100, "head": 100, "mag": 6, "cooldown": 1.1, "reload": 2.1, "kick": 4.5},
]

static func perfect_jump(jump_age: float) -> bool:
	return jump_age >= 0.0 and jump_age <= PERFECT_WINDOW

static func blast_damage(distance: float, source_team: int, target_team: int, is_owner: bool) -> int:
	if is_owner or source_team == target_team or distance > BLAST_RADIUS:
		return 0
	return 100

static func ground_move(flat: Vector2, wish: Vector2, speed: float, delta: float) -> Vector2:
	if wish.length_squared() < 0.001:
		return flat.move_toward(Vector2.ZERO, 120.0 * delta)
	# An opposite direction brakes faster than releasing movement, then accelerates.
	if flat.dot(wish) < 0.0:
		var stop_time = flat.length() / 145.0
		if delta <= stop_time:
			return flat.move_toward(Vector2.ZERO, 145.0 * delta)
		return Vector2.ZERO.move_toward(wish * speed, 90.0 * (delta - stop_time))
	return flat.move_toward(wish * speed, 90.0 * delta)

static func air_move(flat: Vector2, wish: Vector2, delta: float) -> Vector2:
	if wish.length_squared() < 0.001:
		return flat
	# Projection-limited acceleration rewards turning the mouse into a side strafe.
	var direction = wish.normalized()
	var available = 1.5 - flat.dot(direction)
	if available > 0.0:
		flat += direction * minf(available, 65.0 * delta)
	return flat.limit_length(HORIZONTAL_CAP)

static func spread_degrees(weapon: int, speed: float, airborne: bool, scope_age: float) -> float:
	if weapon == 2:
		return 0.0
	# Preserve the signature precision pistol shot during grenade jumps.
	if weapon == 1 and airborne:
		return 0.0
	var motion = clampf((speed - 0.65) / (WALK_SPEED - 0.65), 0.0, 1.0)
	if weapon == 3:
		if scope_age < SCOPE_READY:
			return 5.0
		return 3.0 if airborne else motion * 1.8
	if airborne:
		return 3.0
	return motion * (1.8 if weapon == 0 else 1.0)

static func launch_velocity(old_velocity: Vector3, feet: Vector3, origin: Vector3, jump_age: float) -> Vector3:
	var distance = feet.distance_to(origin)
	if distance >= BLAST_RADIUS:
		return old_velocity
	var strength = clampf(1.0 - distance / BLAST_RADIUS, 0.0, 1.0)
	var horizontal = Vector3(feet.x - origin.x, 0.0, feet.z - origin.z)
	if horizontal.length() > 0.01:
		horizontal = horizontal.normalized()
	var timing = 1.0 if perfect_jump(jump_age) else 0.30
	var impulse = horizontal * 19.0 * strength * timing
	impulse.y = 19.5 * strength * timing
	var result = old_velocity + impulse
	var flat = Vector2(result.x, result.z).limit_length(HORIZONTAL_CAP)
	return Vector3(flat.x, minf(result.y, VERTICAL_CAP), flat.y)

# Match angular movement to projected image size, including the zoom transition.
static func fov_sensitivity(fov: float, base_fov: float = 86.0) -> float:
	return tan(deg_to_rad(clampf(fov,1,179)*.5))/tan(deg_to_rad(base_fov*.5))

static func parry_blocks(facing: Vector3, toward_attacker: Vector3) -> bool:
	return facing.normalized().dot(toward_attacker.normalized()) >= .5
