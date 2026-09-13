extends RefCounted
## Progression model. Main persists local XP; the server confirms online awards.
## Awards survive death; playback never changes XP.
const MAX_LEVEL = 1000
const MULTI_WINDOW = 1.35
const BASE_HOLD = 2.0
const BONUS_HOLD = 1.15
var profiles: Dictionary = {}
var roster: Dictionary = {}
var chain: Dictionary = {}
var awards: Array = []
var last_tick = 0.0
var level_up_until = -1.0
var recent_level = 1

static func threshold(level: int) -> int:
	var n = clampi(level,1,MAX_LEVEL)-1
	return 250*n+25*n*n
static func level_for_xp(xp: int) -> int:
	var low = 1
	var high = MAX_LEVEL
	while low<high:
		var mid = (low+high+1)/2
		if threshold(mid)<=xp: low = mid
		else: high = mid-1
	return low
func xp_for(who: String) -> int: return profiles.get(who,0)
func level_for(who: String) -> int: return level_for_xp(xp_for(who))
func ensure_player(who: String, team: int) -> void:
	if not profiles.has(who): profiles[who] = 0
	if not roster.has(who): roster[who] = {"name":who,"team":team,"kills":0,"deaths":0}
func reset_roster(combat: bool) -> void:
	finish_chain(last_tick)
	roster.clear()
	ensure_player("YOU",1)
	if combat:
		for i in range(4): ensure_player("ALLY %d" % (i+1),1)
		for i in range(5): ensure_player("ENEMY %d" % (i+1),2)
static func chain_bonus(count: int) -> int:
	if count>=4: return 100
	if count==3: return 75
	if count==2: return 50
	return 0
static func chain_title(count: int) -> String:
	if count>=4: return "MULTI KILL"
	if count==3: return "TRIPLE KILL"
	if count==2: return "DOUBLE KILL"
	return "SINGLE KILL"
func grant_xp(who: String, amount: int, now: float) -> void:
	var old_level = level_for(who)
	profiles[who] = mini(threshold(MAX_LEVEL),xp_for(who)+amount)
	if who=="YOU" and level_for(who)>old_level:
		recent_level = level_for(who)
		level_up_until = now+3
func finish_chain(now: float) -> void:
	if chain.is_empty(): return
	var bonus = chain_bonus(chain.count)
	if bonus>0:
		grant_xp("YOU",bonus,now)
		awards.append({"bonus":true,"total":bonus,"count":chain.count,"head":false,"one_shot":false,"collateral":false,"last":now,"shown":-1.0})
	chain = {}
func display_until(award: Dictionary) -> float:
	return award.shown+BONUS_HOLD if award.bonus else maxf(award.last+BASE_HOLD,award.shown+.65)
func update(now: float) -> void:
	last_tick = now
	if not chain.is_empty() and now-chain.last>MULTI_WINDOW: finish_chain(now)
	if not awards.is_empty() and awards[0].shown>=0 and now>=display_until(awards[0]): awards.pop_front()
	if not awards.is_empty() and awards[0].shown<0: awards[0].shown = now
func record(killer: String, victim: String, team: int, head: bool, one_shot: bool, now: float, group: int, sniper: bool) -> int:
	update(now)
	if roster.has(victim): roster[victim].deaths += 1
	if victim=="YOU": finish_chain(now)
	if not roster.has(killer) or killer==victim: return 0
	roster[killer].kills += 1
	var amount = 100 if head or one_shot else 50
	grant_xp(killer,amount,now)
	if killer=="YOU":
		if chain.is_empty():
			chain = {"bonus":false,"total":0,"count":0,"head":false,"one_shot":false,"collateral":false,"group":-1,"last":now,"shown":-1.0}
			awards.append(chain)
		chain.total += amount
		chain.count += 1
		chain.collateral = chain.collateral or (group==chain.group and sniper)
		chain.head = chain.head or head
		chain.one_shot = chain.one_shot or one_shot
		chain.last = now
		chain.group = group
	update(now)
	return amount
func rows(team: int) -> Array:
	var result: Array = []
	for row in roster.values():
		if row.team==team:
			var copy = row.duplicate()
			copy.level = level_for(row.name)
			copy.xp = xp_for(row.name)
			result.append(copy)
	result.sort_custom(func(a,b):
		if a.kills!=b.kills: return a.kills>b.kills
		if a.deaths!=b.deaths: return a.deaths<b.deaths
		return a.name<b.name)
	return result
