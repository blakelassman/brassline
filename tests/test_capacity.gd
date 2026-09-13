extends Node
var g: Node
var folder = "/tmp/brassline_capacity/"
var checks = 0
var failures = 0
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",title)
func mark(name: String) -> void:
	var file = FileAccess.open(folder+name,FileAccess.WRITE)
	file.store_string("1")
func marked(name: String) -> bool: return FileAccess.file_exists(folder+name)
func wait_for(condition: Callable, seconds: float = 30) -> bool:
	var deadline = Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline: await get_tree().physics_frame
	return condition.call()
func counts() -> Array:
	var result = [0,0,0]
	for p in g.net.peers.values(): result[g.net.slots[p.slot].team] += 1
	return result
func run(game: Node) -> void:
	g = game
	var args = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--coord="): folder = arg.trim_prefix("--coord=")+"/"
	await get_tree().physics_frame
	if "--role=host" in args:
		check(await g.net.host(27919,"",false),"Capacity server starts")
		mark("host")
		var balanced = true
		var until = Time.get_ticks_msec()+35000
		while g.net.peers.size()<10 and Time.get_ticks_msec()<until:
			var c = counts()
			balanced = balanced and absi(c[1]-c[2])<=1
			await get_tree().physics_frame
		check(balanced,"Human teams stay within one player throughout filling")
		check(g.net.peers.size()==10 and g.net.actors().size()==10,"Ten real processes occupy all ten slots")
		check(counts()==[0,5,5] and g.combat.bots.is_empty(),"Full server is five humans versus five humans, zero bots")
		mark("full")
		check(await wait_for(func(): return marked("rejected")),"Eleventh human gets server-full message")
		mark("depart")
		check(await wait_for(func(): return g.net.peers.size()==7),"Three players disconnect")
		var c = counts()
		check(absi(c[1]-c[2])<=1,"Departures rebalance human teams to four versus three")
		check(g.net.actors().size()==10 and g.combat.bots.size()==3,"Bots fill exactly the three vacant slots")
		var teams = [0,0,0]
		for a in g.net.actors(): teams[a.team] += 1
		check(teams==[0,5,5],"Both teams retain exactly five total participants")
		mark("end")
		await get_tree().create_timer(.8).timeout
	elif "--role=full" in args:
		await wait_for(func(): return marked("full"),40)
		g.net.join("127.0.0.1",27919,"")
		check(await wait_for(func(): return not g.net.running),"Full server rejects extra connection")
		check("full" in g.net.status,"Full server explains why join failed")
		mark("rejected")
	else:
		await wait_for(func(): return marked("host"))
		g.net.join("127.0.0.1",27919,"")
		check(await wait_for(func(): return g.net.is_client_ready()),"Human client joins")
		var departing = g.net.own_slot in [5,6,7]
		await wait_for(func(): return marked("depart"),45)
		if departing:
			await g.net.leave()
			check(not g.net.running,"Departing client leaves cleanly")
		else:
			await wait_for(func(): return marked("end"))
			check(g.net.is_client_ready(),"Remaining client stays connected through rebalance")
	print("CAPACITY_RESULT ",checks-failures,"/",checks)
	await g.quit_game()
