extends RefCounted
## Local cosmetic collection. No currency, purchases, keys, trading or stat modifiers.
const SLOTS = ["armor","rifle","pistol","sword","sniper"]
const LABELS = {"armor":"Operator","rifle":"Rifle","pistol":"Heavy pistol","sword":"Sword","sniper":"Longshot"}
const RARITIES = ["FIELD","SIGNAL","ELITE","MYTHIC","SPECIAL"]
const COLORS = [Color("afc0cd"),Color("65b0f1"),Color("b287ff"),Color("ed78be"),Color("ffd46b")]
const WEIGHTS = [7000,2200,600,175,25]
const DEFAULTS = {"armor":"armor_standard","rifle":"rifle_standard","pistol":"pistol_standard","sword":"sword_standard","sniper":"sniper_standard"}
static var items: Dictionary = {}
var owned: Dictionary = {}
var equipped: Dictionary = DEFAULTS.duplicate()
var opened = 0
var last_drop = ""
var rng = RandomNumberGenerator.new()
var revision = 0
func _init() -> void: rng.randomize()
static func catalog() -> Dictionary:
	if not items.is_empty(): return items
	var finishes = [
		["slate","Slate",0,"607786","c3d6df",0], ["sand","Dune",0,"907354","dcc7a3",1],
		["circuit","Circuit",1,"143c54","49d6ce",2], ["ember","Ember",1,"663d35","f69d51",1],
		["glacier","Glacier",2,"326995","b8f1ff",3], ["orchid","Orchid",2,"43284d","e692da",2],
		["royal","Royal Alloy",3,"33384f","e3bc65",1], ["neon","Neon Divide",3,"18384c","f26ab5",3],
		["aurora","Aurora",4,"35659c","acf5d6",4], ["gilded","Gilded Relic",4,"815b27","fff1b1",2]]
	for slot in SLOTS:
		items[slot+"_standard"] = {"id":slot+"_standard","slot":slot,"name":"Standard Issue","rarity":0,"base":"263740","accent":"8ba1a3","pattern":0,"variant":0,"case":false}
		for i in range(finishes.size()):
			var f = finishes[i]
			var id = slot+"_"+f[0]
			items[id] = {"id":id,"slot":slot,"name":f[1],"rarity":f[2],"base":f[3],"accent":f[4],"pattern":f[5],"variant":(i+1)%3,"case":true}
	return items
static func clean_loadout(value: Dictionary) -> Dictionary:
	var result = DEFAULTS.duplicate()
	var all = catalog()
	for slot in SLOTS:
		var id = value.get(slot,"")
		if id is String and all.has(id) and all[id].slot==slot: result[slot] = id
	return result
func load_data(data: Dictionary) -> void:
	owned.clear()
	var source = data.get("owned",{})
	if source is Dictionary:
		for id in catalog():
			var count = source.get(id,0)
			if (count is int or count is float) and is_finite(float(count)) and count>0: owned[id] = clampi(int(count),1,1000000000)
	for id in DEFAULTS.values(): owned[id] = maxi(1,int(owned.get(id,0)))
	var loadout = data.get("equipped",{})
	equipped = clean_loadout(loadout if loadout is Dictionary else {})
	for slot in SLOTS:
		if not owned.has(equipped[slot]): equipped[slot] = DEFAULTS[slot]
	var count = data.get("opened",0)
	opened = clampi(int(count),0,1000000000) if (count is int or count is float) and is_finite(float(count)) else 0
	last_drop = str(data.get("last_drop",""))
	if not owned.has(last_drop): last_drop = ""
	revision += 1
func save_data() -> Dictionary: return {"owned":owned.duplicate(),"equipped":equipped.duplicate(),"opened":opened,"last_drop":last_drop}
static func rarity_for_roll(roll: int) -> int:
	var threshold = 0
	for i in range(WEIGHTS.size()):
		threshold += WEIGHTS[i]
		if clampi(roll,0,9999)<threshold: return i
	return 4
func roll_item() -> Dictionary:
	var rarity = rarity_for_roll(rng.randi_range(0,9999))
	var pool = catalog().values().filter(func(item): return item.case and item.rarity==rarity)
	return pool[rng.randi_range(0,pool.size()-1)]
func open_case() -> Dictionary:
	var item = roll_item()
	var duplicate = owned.has(item.id)
	owned[item.id] = mini(1000000000,int(owned.get(item.id,0))+1)
	opened = mini(1000000000,opened+1)
	last_drop = item.id
	revision += 1
	return {"item":item,"duplicate":duplicate,"count":owned[item.id]}
func equip_item(id: String) -> bool:
	if not catalog().has(id) or not owned.has(id): return false
	equipped[catalog()[id].slot] = id
	revision += 1
	return true
static var shader: Shader
static var materials: Dictionary = {}
static func finish(id: String) -> ShaderMaterial:
	if materials.has(id): return materials[id]
	if shader==null:
		shader = Shader.new()
		shader.code = """shader_type spatial;
uniform vec4 base : source_color;
uniform vec4 accent : source_color;
uniform float style = 0.0;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
 float p = 0.0;
 if(style > 0.5 && style < 1.5) p = step(0.35, sin((local_pos.x + local_pos.z * 0.7) * 44.0));
 else if(style < 2.5 && style > 1.5) p = step(0.76, abs(sin(local_pos.z * 62.0) * cos(local_pos.y * 48.0)));
 else if(style < 3.5 && style > 2.5) p = step(0.15, sin(local_pos.x * 31.0 + sin(local_pos.z * 34.0) * 2.0 + local_pos.y * 29.0));
 else if(style > 3.5) p = 0.5 + 0.5 * sin(local_pos.z * 13.0 + local_pos.x * 16.0 + TIME * 0.65);
 ALBEDO = mix(base.rgb, accent.rgb, p * 0.75);
 METALLIC = 0.45; ROUGHNESS = 0.38;
}
"""
	var item = catalog()[id]
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base",Color(item.base))
	mat.set_shader_parameter("accent",Color(item.accent))
	mat.set_shader_parameter("style",float(item.pattern))
	materials[id] = mat
	return mat
static func paint(root: Node, id: String, armor: bool = false) -> void:
	if root.has_meta("no_finish") or root.is_queued_for_deletion(): return
	if root is MeshInstance3D:
		if not root.has_meta("original_finish"): root.set_meta("original_finish",root.material_override)
		var original = root.get_meta("original_finish")
		# Team-colored armor panels, visors and silhouettes remain recognizable.
		if armor and (not original is StandardMaterial3D or original.albedo_color.v>.4): return
		root.material_override = original if id.ends_with("_standard") else finish(id)
	for child in root.get_children(): paint(child,id,armor)
