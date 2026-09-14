extends RefCounted
## One local profile, atomically saved with backup. Tests can use an isolated path.
const PATH = "user://profile_v1.json"
const DEFAULT_KEYS = {"forward":[KEY_W],"back":[KEY_S],"left":[KEY_A],"right":[KEY_D],"jump":[KEY_SPACE,-MOUSE_BUTTON_WHEEL_DOWN],"crouch":[KEY_CTRL,KEY_C],"fire":[-MOUSE_BUTTON_LEFT],"aim":[-MOUSE_BUTTON_RIGHT],"weapon_0":[KEY_1],"weapon_1":[KEY_2],"weapon_2":[KEY_3],"weapon_3":[KEY_4],"reload":[KEY_R],"blast":[KEY_G],"smoke":[KEY_Q],"refill":[KEY_F],"reset":[KEY_T],"scoreboard":[KEY_TAB],"help":[KEY_H],"pause":[KEY_ESCAPE]}
const LABELS = {"forward":"Move forward","back":"Move backward","left":"Strafe left","right":"Strafe right","jump":"Jump","crouch":"Crouch (hold)","fire":"Fire / slash / throw","aim":"Aim / scope / parry / short toss","weapon_0":"Rifle","weapon_1":"Heavy pistol","weapon_2":"Sword","weapon_3":"Sniper","reload":"Reload","blast":"Equip blast grenade","smoke":"Equip smoke grenade","refill":"Refill training supplies","reset":"Reset training drill","scoreboard":"Scoreboard (hold)","help":"Toggle tips","pause":"Open / close menu"}
var data: Dictionary = {"version":1,"name":"Player","id":"","xp":0,"sensitivity":.0023,"volume":.65,"weapons_volume":1.0,"effects_volume":1.0,"feedback_volume":.85,"ambience_volume":.35,"quality":1,"fps_limit":120,"fullscreen":false,"resolution_width":1920,"resolution_height":1080,"challenges":{},"cosmetics":{},"bindings":{},"last_address":"","port":27020}
var path = PATH
var error = ""
var dirty = false
func _init(custom_path: String = PATH) -> void:
	path = custom_path
	data.bindings = DEFAULT_KEYS.duplicate(true)
func load_profile() -> void:
	for file_path in [path,path+".bak"]:
		if not FileAccess.file_exists(file_path): continue
		var parser = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(file_path))!=OK: continue
		var parsed = parser.data
		if not parsed is Dictionary or parsed.get("version",0)!=1: continue
		for key in data:
			if parsed.has(key) and typeof(parsed[key])==typeof(data[key]): data[key] = parsed[key]
		# JSON stores all numbers as floats; explicitly validate and clamp numeric fields.
		for key in ["xp","quality","fps_limit","port","sensitivity","volume","weapons_volume","effects_volume","feedback_volume","ambience_volume","resolution_width","resolution_height"]:
			if parsed.get(key) is float or parsed.get(key) is int:
				if is_finite(float(parsed[key])): data[key] = parsed[key]
		break
	data.xp = clampi(int(data.xp),0,25199775)
	data.quality = clampi(int(data.quality),0,2)
	data.fps_limit = clampi(int(data.fps_limit),30,240)
	data.port = clampi(int(data.port),1024,65535)
	data.sensitivity = clampf(float(data.sensitivity),.0003,.012)
	for field in ["volume","weapons_volume","effects_volume","feedback_volume","ambience_volume"]:
		data[field] = clampf(float(data[field]),0,1)
	data.resolution_width = clampi(int(data.resolution_width),960,7680)
	data.resolution_height = clampi(int(data.resolution_height),540,4320)
	data.name = clean_name(data.name)
	if data.id.length()!=32: data.id = Crypto.new().generate_random_bytes(16).hex_encode()
	var valid: Dictionary = {}
	for action in DEFAULT_KEYS:
		var values = data.bindings.get(action,DEFAULT_KEYS[action])
		valid[action] = []
		if values is Array:
			for code in values.slice(0,2):
				if (code is int or code is float) and absf(float(code))<33554432 and code!=0: valid[action].append(int(code))
		if action=="pause" and valid[action].is_empty(): valid[action] = [KEY_ESCAPE]
	data.bindings = valid
static func clean_name(value: String) -> String:
	var output = ""
	for char in value.strip_edges().substr(0,18):
		if char.unicode_at(0)>=32 and char not in ["[","]","\n","\r"]: output += char
	return "Player" if output.is_empty() else output
func save() -> bool:
	var temp = path+".tmp"
	var file = FileAccess.open(temp,FileAccess.WRITE)
	if file==null:
		error = "Could not write your profile. Check available disk space."
		return false
	file.store_string(JSON.stringify(data,"\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path+".bak")
		if DirAccess.rename_absolute(path,path+".bak")!=OK:
			error = "Could not replace the saved profile."
			return false
	if DirAccess.rename_absolute(temp,path)!=OK:
		error = "Could not finish saving the profile."
		if FileAccess.file_exists(path+".bak"): DirAccess.copy_absolute(path+".bak",path)
		return false
	dirty = false
	error = ""
	return true
func apply_bindings() -> void:
	for action in DEFAULT_KEYS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for code in data.bindings[action]:
			if code==0: continue
			var event: InputEvent
			if code<0:
				event = InputEventMouseButton.new()
				event.button_index = -code
			else:
				event = InputEventKey.new()
				event.physical_keycode = code
			InputMap.action_add_event(action,event)
func bind(action: String, slot: int, code: int) -> String:
	var previous = data.bindings[action][slot] if data.bindings[action].size()>slot else 0
	var conflicts: Array[String] = []
	for other in data.bindings:
		if other==action: continue
		if code in data.bindings[other]:
			data.bindings[other].erase(code)
			conflicts.append(LABELS[other])
	var codes: Array = data.bindings[action]
	while codes.size()<=slot: codes.append(0)
	codes[slot] = code
	# Never leave pause unavailable when another action takes its last binding.
	if data.bindings.pause.is_empty() and action!="pause":
		var occupied: Array = []
		for values in data.bindings.values(): occupied.append_array(values)
		for fallback in [previous,KEY_ESCAPE,KEY_F10,KEY_F12]:
			if fallback!=0 and fallback not in occupied:
				data.bindings.pause = [fallback]
				break
	apply_bindings()
	dirty = true
	save()
	return "Reassigned from "+", ".join(conflicts) if not conflicts.is_empty() else "Binding saved"
static func key_label(code: int) -> String:
	if code==0: return "Unbound"
	if code>0: return OS.get_keycode_string(code)
	return {-1:"Mouse left",-2:"Mouse right",-3:"Mouse middle",-4:"Wheel up",-5:"Wheel down",-6:"Wheel left",-7:"Wheel right",-8:"Mouse 4",-9:"Mouse 5"}.get(code,"Mouse %d" % -code)
