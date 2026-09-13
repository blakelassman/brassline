extends RefCounted
## Persistent milestones; online callers consume only host-confirmed events.
var stats: Dictionary = {}
var unlocked: Dictionary = {}
var pending: Array = []
var current: Dictionary = {}
var elapsed = 0.0
var streak = 0
var head_streak = 0
var chain = 0
var last_kill = -999.0
var last_group = -1
var group_count = 0
var last_victim = ""
var revenge = ""
var revision = 0

static func catalog() -> Array:
	var result: Array = []
	var tracks = [
		["kills","Eliminator",[1,100,500,2500,10000],"total eliminations"],
		["headshots","Dead Center",[1,25,100,500,2000],"headshot kills"],
		["jump_kills","Airborne",[1,10,50,250],"kills while airborne"],
		["air_heads","Skywriter",[1,10,50,100],"airborne headshot kills"],
		["boost_kills","Launch Sequence",[1,10,50],"airborne kills within 5 seconds of a grenade boost"],
		["collats","Through and Through",[1,10,50,100],"sniper shots killing at least two enemies"],
		["triple_collats","Thread the Needle",[1,5,25],"sniper shots killing at least three enemies"],
		["best_streak","Unstoppable",[5,10,15,20,25,30,50],"kills in one life, within one match"],
		["best_chain","Rapid Fire",[2,3,4,5,6],"kills in a chain (at most 1.35 seconds apart)"],
		["rifle","Rifle Discipline",[25,250,1000],"rifle kills"],
		["pistol","Sidearm Specialist",[25,250,1000],"heavy pistol kills"],
		["sniper","Longshot Legend",[25,250,1000],"sniper kills"],
		["sword","Close Quarters",[10,100,500],"sword kills"],
		["blast","Demolition",[10,100,500],"blast grenade kills"],
		["quickscopes","Snap Decision",[1,25,100],"sniper kills 0.12–0.45 seconds after starting to scope"],
		["noscope","No Glass",[1,10,50],"unscoped sniper kills"],
		["longshots","Across the Yard",[1,25,100],"gun kills from at least 30 meters"],
		["clutch","Still Standing",[1,25,100],"kills with 25 health or less"],
		["parries","Steel Nerves",[1,25,100],"successful sword parries"],
		["boosts","Perfect Timing",[1,25,100],"perfectly timed grenade boosts"],
		["one_shots","One Is Enough",[10,100,1000],"one-shot kills against full-health enemies"],
		["revenge","Payback",[1,25,100],"kills against your most recent killer"],
		["wins","Victory Lap",[1,10,50,100],"online team wins"],
		["best_head_streak","Clean Sweep",[3,5,10],"consecutive headshot kills without dying"]]
	for track in tracks:
		for i in range(track[2].size()):
			var goal = track[2][i]
			result.append({"id":"%s_%d" % [track[0],goal],"stat":track[0],"goal":goal,"title":"%s %s" % [track[1],["I","II","III","IV","V","VI","VII"][i]],"description":"%d %s" % [goal,track[3]]})
	return result
func load_data(data: Dictionary) -> void:
	stats.clear()
	unlocked.clear()
	var source = data.get("stats",{})
	var earned = data.get("unlocked",{})
	for item in catalog():
		var value = source.get(item.stat,0) if source is Dictionary else 0
		if (value is int or value is float) and is_finite(float(value)): stats[item.stat] = clampi(int(value),0,1000000000)
		if earned is Dictionary and earned.get(item.id,false)==true: unlocked[item.id] = true
func save_data() -> Dictionary: return {"stats":stats.duplicate(),"unlocked":unlocked.duplicate()}
func reset_life() -> void:
	streak = 0
	head_streak = 0
	chain = 0
	last_kill = -999
	last_group = -1
	group_count = 0
func reset_match() -> void:
	reset_life()
	revenge = ""
func add(stat: String, amount: int = 1) -> void: stats[stat] = mini(1000000000,int(stats.get(stat,0))+amount)
func medal(title: String, detail: String) -> void:
	# Milestones are never dropped. Limit queued repeat medals during busy firefights.
	if pending.filter(func(item): return not item.milestone).size()<6:
		pending.append({"title":title,"detail":detail,"milestone":false})
func check_unlocks() -> void:
	for item in catalog():
		if not unlocked.has(item.id) and int(stats.get(item.stat,0))>=item.goal:
			unlocked[item.id] = true
			pending.append({"title":item.title.to_upper(),"detail":item.description,"milestone":true})
	revision += 1
func event(kind: String, data: Dictionary = {}) -> void:
	if kind=="death":
		reset_life()
		revenge = str(data.get("killer",""))
		return
	if kind in ["parries","boosts","wins"]:
		add(kind)
		medal({"parries":"PARRY","boosts":"PERFECT BOOST","wins":"VICTORY"}[kind],{"parries":"Steel meets steel","boosts":"Own the landing","wins":"Team deathmatch won"}[kind])
		check_unlocks()
		return
	if kind!="kill": return
	var now = float(data.get("time",0))
	var weapon = str(data.get("weapon",""))
	var head = bool(data.get("head",false))
	var air = bool(data.get("air",false))
	var group = int(data.get("group",-1))
	streak += 1
	head_streak = head_streak+1 if head else 0
	chain = chain+1 if now-last_kill<=1.35 else 1
	last_kill = now
	group_count = group_count+1 if group==last_group and group>=0 else 1
	last_group = group
	add("kills")
	var weapon_stat = {"RIFLE":"rifle","HEAVY PISTOL":"pistol","LONGSHOT":"sniper","SWORD":"sword","BLAST":"blast"}.get(weapon,"")
	if not weapon_stat.is_empty(): add(weapon_stat)
	stats.best_streak = maxi(int(stats.get("best_streak",0)),streak)
	stats.best_chain = maxi(int(stats.get("best_chain",0)),chain)
	stats.best_head_streak = maxi(int(stats.get("best_head_streak",0)),head_streak)
	if head: add("headshots")
	if air: add("jump_kills")
	if air and head: add("air_heads")
	if air and data.get("boosted",false): add("boost_kills")
	if air: medal("JUMP SHOT" if not head else "AIRBORNE HEADSHOT",weapon)
	if data.get("one_shot",false): add("one_shots")
	if float(data.get("distance",0))>=30 and weapon not in ["SWORD","BLAST"]:
		add("longshots")
		medal("LONG SHOT","%dm" % int(data.distance))
	if int(data.get("health",100))<=25: add("clutch")
	if weapon=="LONGSHOT":
		var scope = float(data.get("scope",0))
		if scope>=.12 and scope<=.45:
			add("quickscopes")
			medal("QUICKSCOPE","Snap. Fire.")
		elif scope<.12:
			add("noscope")
			medal("NO SCOPE","No glass required")
		if group_count==2:
			add("collats")
			medal("COLLATERAL","Two enemies. One shot.")
		elif group_count==3:
			add("triple_collats")
			medal("TRIPLE COLLATERAL","Three enemies. One shot.")
	if not revenge.is_empty() and str(data.get("victim",""))==revenge:
		add("revenge")
		revenge = ""
		medal("PAYBACK","Score settled")
	if streak in [5,10,15,20,25,30,50] or (streak>50 and streak%10==0): medal("%d KILL STREAK" % streak,"Still alive. Keep going.")
	check_unlocks()
func update(delta: float, visible: bool) -> bool:
	if not visible: return false
	elapsed += delta
	if not current.is_empty() and elapsed>2.6: current = {}
	if current.is_empty() and not pending.is_empty():
		current = pending.pop_front()
		elapsed = 0
		return true
	return false
