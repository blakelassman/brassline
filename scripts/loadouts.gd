extends RefCounted
## Level-gated sidegrades. No class changes health, movement, or grenade damage.
const Progress = preload("res://scripts/progression.gd")
const IDS = ["vanguard","raider","sentinel","marksman"]
const CLASSES = {
 "vanguard":{"title":"VANGUARD","level":1,"role":"Precision assault","detail":"One-shot headshots. Learn the fixed S spray.","weapon":{"name":"RIFLE","body":25,"head":100,"mag":24,"cooldown":.16,"reload":1.45,"kick":.75,"auto":true,"recoil":1.0,"spread":1.0}},
 "raider":{"title":"RAIDER","level":3,"role":"Close-range pressure","detail":"Kestrel SMG. Fast fire, short recoil, weaker headshots.","weapon":{"name":"KESTREL SMG","body":20,"head":60,"mag":32,"cooldown":.085,"reload":1.7,"kick":.5,"auto":true,"recoil":.45,"spread":.8}},
 "sentinel":{"title":"SENTINEL","level":6,"role":"Sustained fire","detail":"Bastion LMG. Deep magazine, long reload, wider movement spread.","weapon":{"name":"BASTION LMG","body":23,"head":75,"mag":48,"cooldown":.12,"reload":2.65,"kick":.8,"auto":true,"recoil":.85,"spread":1.35}},
 "marksman":{"title":"MARKSMAN","level":10,"role":"Deliberate precision","detail":"Lancer DMR. Semi-auto, two body hits or one headshot.","weapon":{"name":"LANCER DMR","body":55,"head":100,"mag":12,"cooldown":.42,"reload":1.8,"kick":2.2,"auto":false,"recoil":1.5,"spread":1.1}}
}
static func allowed(id: String, xp: int) -> String:
 return id if CLASSES.has(id) and Progress.level_for_xp(xp)>=CLASSES[id].level else "vanguard"
static func weapon(id: String, slot: int) -> Dictionary:
 return CLASSES.get(id,CLASSES.vanguard).weapon if slot==0 else preload("res://scripts/rules.gd").WEAPONS[slot]
static func decorate(model: Node3D, id: String) -> void:
 var old=model.get_node_or_null("ClassParts")
 if old!=null: old.free()
 model.scale=Vector3.ONE
 var parts=Node3D.new(); parts.name="ClassParts"; model.add_child(parts)
 var geo=preload("res://scripts/geo.gd")
 var dark=Color("263740"); var accent=Color("b6c6bb")
 if id=="raider":
  model.scale=Vector3(.88,.95,.68)
  geo.box(parts,Vector3(0,.15,-.07),Vector3(.15,.06,.19),dark)
  geo.box(parts,Vector3(0,-.24,-.1),Vector3(.08,.3,.09),accent)
 elif id=="sentinel":
  model.scale=Vector3(1.12,1.05,1.08)
  var drum=geo.cylinder(parts,Vector3(0,-.23,-.1),.15,.22,dark); drum.rotation.z=PI/2
  geo.box(parts,Vector3(0,.18,-.12),Vector3(.04,.06,.3),accent)
 elif id=="marksman":
  model.scale=Vector3(.95,1,1.18)
  var optic=geo.cylinder(parts,Vector3(0,.17,-.1),.05,.2,dark); optic.rotation.x=PI/2
  geo.box(parts,Vector3(0,.10,-.1),Vector3(.06,.14,.09),accent)

static func rank_title(level: int) -> String:
 var result="RECRUIT"
 for row in [[3,"OPERATIVE"],[6,"SPECIALIST"],[10,"VETERAN"],[25,"ELITE"],[50,"ACE"],[100,"LEGEND"],[500,"ICON"],[1000,"IMMORTAL"]]:
  if level>=row[0]: result=row[1]
 return result
