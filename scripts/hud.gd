extends Control

const Icons = preload("res://scripts/feed_icons.gd")
const Rules = preload("res://scripts/rules.gd")
var game: Node
var menu: PanelContainer
var resume_button: Button
var help_visible = false
var font: Font
var ink = Color("f4ecd7")
var gold = Color("f1bd58")
var dim = Color("acc0c5")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_build_menu()

func _build_menu() -> void:
	menu = preload("res://scripts/menu.gd").new()
	menu.game = game
	add_child(menu)
	resume_button = menu.resume_button
	_build_vote()

var vote_panel: PanelContainer
var vote_label: Label
var vote_buttons: Array[Button] = []
func _build_vote() -> void:
	vote_panel = PanelContainer.new()
	add_child(vote_panel)
	vote_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vote_panel.offset_left = -430
	vote_panel.offset_right = 430
	vote_panel.offset_top = -180
	vote_panel.offset_bottom = 180
	var style = StyleBoxFlat.new()
	style.bg_color = Color("142b34")
	style.border_color = gold
	style.set_border_width_all(2)
	style.set_content_margin_all(30)
	vote_panel.add_theme_stylebox_override("panel",style)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	vote_panel.add_child(column)
	vote_label = Label.new()
	vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_label.add_theme_font_size_override("font_size",24)
	vote_label.add_theme_color_override("font_color",gold)
	column.add_child(vote_label)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	column.add_child(row)
	for index in range(4):
		var button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 80
		button.pressed.connect(func(): game.net.vote(index))
		row.add_child(button)
		vote_buttons.append(button)
	_label(column,"One vote each. Click again to change it. Ties rotate to the next tied map.",14,dim)
	var exit_button = Button.new()
	exit_button.text = "OPEN MENU"
	exit_button.pressed.connect(func(): game.set_active(false))
	column.add_child(exit_button)
	vote_panel.hide()

func _label(parent: Node, text: String, size: int, color: Color) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _process(_delta: float) -> void:
	if game.challenges.update(_delta,game.active and not game.menu_open): game.sound("achievement",-15)
	queue_redraw()
	vote_panel.visible = game.net.running and not game.net.round_active and not game.menu_open and not game.replays.active and game.clock>=game.net.final_replay_until
	if vote_panel.visible:
		vote_label.text = "%s\nBLUE %d  /  RED %d\n%s" % [game.net.winner,game.combat.scores[1],game.combat.scores[2],"LOADING NEXT ARENA…" if game.net.loading_round else "VOTE NEXT MAP  /  %ds" % maxi(0,ceili(game.net.vote_end-game.clock))]
		for index in range(4):
			vote_buttons[index].text = (preload("res://scripts/destroy_maps.gd").NAMES[index] if game.net.is_destroy() else game.Maps.NAMES[index])+"\n%d VOTES" % game.net.vote_counts[index]
			vote_buttons[index].disabled = game.net.loading_round


func text_at(text: String, at: Vector2, size: int = 18, color: Color = ink) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func centered(text: String, y: float, size: int = 18, color: Color = ink) -> void:
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at = Vector2((self.size.x-width)/2,y)
	draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,4,Color(.03,.07,.09,color.a*.85))
	text_at(text,at,size,color)

func _draw() -> void:
	if font == null or game.player == null:
		return
	var w = size.x
	var h = size.y
	if not game.active or game.menu_open:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.04,0.10,0.13,0.76))
		return
	if game.replays.active:
		_draw_killcam()
		return
	var p = game.player
	var scoped = p.health>0 and p.weapon == 3 and p.scope_age >= Rules.SCOPE_READY and p.held_grenade.is_empty()
	if scoped:
		_draw_scope()
	_draw_minimap()
	_draw_medal()
	if game.mode in ["combat","online"]:
		centered("%d   :   %d" % [game.combat.scores[1],game.combat.scores[2]],42,26,ink)
	if game.net.running and not game.net.is_destroy():
		var seconds = maxi(0,ceili(game.net.round_end-game.clock)) if game.net.round_active else 0
		centered("%02d:%02d" % [seconds/60,seconds%60],65,14,dim)
	if game.net.is_client_ready() and Time.get_ticks_msec()-game.net.last_packet>750:
		centered("CONNECTION INTERRUPTED",92,14,gold)
	var center = size / 2.0
	var aim_color = gold if p.weapon == 1 else ink
	if not scoped and p.health>0:
		var gap = 5.0+tan(deg_to_rad(p.current_spread()))*(h*.5)/tan(deg_to_rad(p.camera.fov*.5))
		for dir in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			draw_line(center+dir*gap,center+dir*(gap+6),Color(0.04,0.1,0.13,0.9),4)
			draw_line(center+dir*gap,center+dir*(gap+6),aim_color,2)
		draw_circle(center,1.3,aim_color)
	if game.hit_flash > 0.0:
		var hit_color = gold if game.last_head else Color.WHITE
		for dir in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			draw_line(center+dir*14,center+dir*21,hit_color,2)
	text_at(str(p.health),Vector2(28,h-40),32,Color("ff9275") if p.health<40 else ink)
	draw_rect(Rect2(28,h-28,120,3),Color(.15,.2,.23,.8))
	draw_rect(Rect2(28,h-28,1.2*p.health,3),ink)
	for i in range(2):
		var at = Vector2(180+i*48,h-44)
		draw_circle(at,6,gold if i==0 else dim)
		text_at(str(p.blast_count if i==0 else p.smoke_count),at+Vector2(12,5),15,ink)
	text_at(p.held_grenade.to_upper() if not p.held_grenade.is_empty() else Rules.WEAPONS[p.weapon].name,Vector2(w-225,h-70),13,gold)
	var ammo_text = "%02d / %02d" % [p.ammo[p.weapon],Rules.WEAPONS[p.weapon].mag] if p.weapon!=2 else ""
	text_at(ammo_text,Vector2(w-225,h-36),30,ink)
	if p.reload_timer>0:
		draw_rect(Rect2(w-225,h-24,180*(1-p.reload_timer/float(Rules.WEAPONS[p.weapon].reload)),3),gold)
	if p.weapon==2 and p.parry_timer>0:
		draw_arc(center,29,-PI*.8,-PI*.2,20,gold,3,true)
	if help_visible:
		centered("Move / jump / crouch • Fire to attack • Aim to scope, parry or toss • Rebind in Settings",h-120,14,dim)
	_draw_feed()
	var fuse = -1.0
	for grenade in game.grenades:
		if is_instance_valid(grenade) and grenade.kind == "blast" and grenade.global_position.distance_to(p.global_position)<=Rules.BLAST_RADIUS:
			fuse = grenade.fuse if fuse < 0 else minf(fuse,grenade.fuse)
	if fuse >= 0:
		var y = h-159
		draw_rect(Rect2(w/2-150,y,300,8),Color(0.07,0.16,0.19,0.94))
		draw_rect(Rect2(w/2-150,y,300*clampf(fuse/Rules.FUSE,0,1),8),gold)
		if fuse <= Rules.PERFECT_WINDOW: centered("JUMP",y-10,16,gold)
	if game.mode in ["combat","online"]:
		if p.hurt_flash>0:
			draw_rect(Rect2(Vector2.ZERO,size),Color(.8,.10,.04,p.hurt_flash*.35))
			draw_rect(Rect2(3,3,w-6,h-6),Color(.95,.18,.07,p.hurt_flash*2),false,6)

	if game.net.is_destroy(): _draw_objective()
	_draw_xp()
	if Input.is_action_pressed("scoreboard"): _draw_scoreboard()

func _draw_scope() -> void:
	var center = size*.5
	var radius = size.y*.39
	var outer = size.length()
	for i in range(96):
		var a = Vector2.from_angle(TAU*i/96.0)
		var b = Vector2.from_angle(TAU*(i+1)/96.0)
		draw_colored_polygon(PackedVector2Array([center+a*radius,center+a*outer,center+b*outer,center+b*radius]),Color("091217"))
	draw_arc(center,radius,0,TAU,96,Color("6a817d"),3,true)
	draw_line(center+Vector2(-radius,0),center+Vector2(radius,0),Color("152527"),1.3)
	draw_line(center+Vector2(0,-radius),center+Vector2(0,radius),Color("152527"),1.3)
	for i in [-3,-2,-1,1,2,3]:
		draw_line(center+Vector2(i*30,-4),center+Vector2(i*30,4),Color("152527"),1)
		draw_line(center+Vector2(-4,i*30),center+Vector2(4,i*30),Color("152527"),1)
	draw_circle(center,2,Color("df9c4d"))

func _draw_feed() -> void:
	var x = 24.0
	for i in range(game.kill_feed.size()):
		var entry = game.kill_feed[i]
		var opacity = clampf(7.0-(game.clock-entry.time),0,1)
		if entry.evicted >= 0:
			opacity *= clampf(1.0-(game.clock-entry.evicted)/.45,0,1)
		var y = size.y-240+i*29
		draw_rect(Rect2(x,y,360,25),Color(.045,.11,.14,.86*opacity))
		draw_rect(Rect2(x,y,3,25),Color(Color("71d3df") if entry.get("team",1)==1 else Color("ff9772"),opacity))
		if entry.get("killer","")=="YOU": draw_rect(Rect2(x,y,360,25),Color(gold,opacity),false,1.5)
		text_at(entry.killer,Vector2(x+11,y+17),12,Color(ink,opacity))
		Icons.draw_icon(self,Vector2(x+111,y+1),"HEADSHOT" if entry.head else entry.weapon,Color(gold if entry.head else ink,opacity))
		text_at(entry.victim,Vector2(x+181,y+17),12,Color(ink,opacity))
		if entry.collateral: text_at("COLL",Vector2(x+316,y+17),10,Color(gold,opacity))
func award_text(value: String, y: float, font_size: int, color: Color) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var at = Vector2((size.x-width)*.5,y)
	draw_string_outline(font,at+Vector2(1,2),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color(0,0,0,color.a*.65))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw_xp() -> void:
	var p = game.progression
	if not p.awards.is_empty():
		var award = p.awards[0]
		var fade = clampf((p.display_until(award)-game.clock)/.3,0,1)
		var y = size.y*.5-76
		var pulse = clampf(1-(game.clock-maxf(award.last,award.shown))/.18,0,1)
		var tags: Array[String] = []
		if award.bonus: tags.append("ADDITIONAL XP")
		else:
			if award.head: tags.append("HEADSHOT")
			if award.one_shot: tags.append("ONE SHOT, ONE KILL")
			if award.collateral: tags.append("COLLATERAL")
		award_text(p.chain_title(award.count),y-35,16,Color(gold,fade))
		award_text("+%d" % award.total,y+3,38+int(pulse*5),Color(gold,fade))
		award_text(" / ".join(tags),y+25,12,Color(ink,fade))
	if game.clock<p.level_up_until:
		award_text("LEVEL UP / %d" % p.recent_level,190,22,gold)

func _draw_scoreboard() -> void:
	var x = (size.x-840)/2
	var y = (size.y-604)/2
	draw_rect(Rect2(Vector2.ZERO,size),Color(.02,.05,.07,.62))
	draw_rect(Rect2(x,y,840,604),Color("132b34"))
	draw_rect(Rect2(x,y,840,3),gold)
	text_at("SCOREBOARD",Vector2(x+28,y+40),27,ink)
	text_at("DESTROY / FIRST TO 3" if game.net.is_destroy() else ("TDM / FIRST TO 250" if game.mode=="online" else ("ENDLESS 5v5" if game.mode=="combat" else "AIM TRAINING")),Vector2(x+565,y+38),17,gold)
	for col in [["PLAYER",40],["LEVEL",378],["KILLS",493],["DEATHS",587],["TOTAL XP",683]]:
		text_at(col[0],Vector2(x+col[1],y+77),12,dim)
	for team in [1,2]:
		var top = y+99+(team-1)*199
		var color = Color("71d3df") if team==1 else Color("ff9772")
		text_at("BLUE TEAM" if team==1 else "RED TEAM",Vector2(x+40,top+15),14,color)
		var rows = game.net.board_rows(team) if game.net.running else game.progression.rows(team)
		for i in range(rows.size()):
			var row = rows[i]
			var ry = top+28+i*30
			draw_rect(Rect2(x+24,ry,792,28),Color(.8,.7,.4,.16) if row.name=="YOU" else Color(.1,.24,.28,.6))
			for col in [[row.name,40],[str(row.level),391],[str(row.kills),509],[str(row.deaths),610],[str(row.xp),697]]:
				text_at(col[0],Vector2(x+col[1],ry+20),15,gold if row.name=="YOU" else ink)
	var p = game.progression
	var level = p.level_for("YOU")
	text_at("YOUR LEVEL %d / 1000" % level,Vector2(x+28,y+538),17,gold)
	text_at("TOTAL XP  %d" % p.xp_for("YOU"),Vector2(x+420,y+538),15,ink)
	var earned = p.xp_for("YOU")-p.threshold(level)
	var needed = p.threshold(mini(1000,level+1))-p.threshold(level)
	var fraction = float(earned)/maxf(1,needed) if level<1000 else 1.0
	draw_rect(Rect2(x+28,y+553,784,4),Color(.25,.35,.38))
	draw_rect(Rect2(x+28,y+553,784*fraction,4),gold)
	text_at("%d FPS   /   %d ms   /   %d Hz server" % [Engine.get_frames_per_second(),game.net.ping_ms,int(game.net.server_tick_rate)],Vector2(x+28,y+582),13,dim)

func radar_point(position: Vector3) -> Vector2:
	return Vector2(130,130)+Vector2(position.x,position.z)*3.05
func _draw_minimap() -> void:
	draw_rect(Rect2(24,24,212,212),Color(.035,.075,.095,.9))
	draw_rect(Rect2(116,34,28,192),Color(.13,.19,.21,.85))
	for rect in (preload("res://scripts/destroy_maps.gd").footprints() if game.net.is_destroy() else game.Maps.footprints(game.current_map)):
		draw_rect(Rect2(Vector2(130,130)+rect.position*3.05,rect.size*3.05),Color(.27,.36,.38,.8))
	draw_rect(Rect2(24,24,212,212),Color(.65,.74,.74,.5),false,1)
	text_at("N",Vector2(125,40),11,dim)
	var actors = game.net.actors() if game.net.running else game.targets.duplicate()
	if not game.net.running: actors.append(game.player)
	var contacts = game.radar.remote if game.net.is_client_ready() else game.radar.contacts(actors,game.player.team,game.clock)
	for contact in contacts:
		var at = radar_point(contact[0]).clamp(Vector2(30,30),Vector2(230,230))
		var age = (Time.get_ticks_msec()-game.radar.remote_at)/1000.0 if game.net.is_client_ready() else 0.0
		var alpha = 1.0 if contact[1] else clampf((contact[2]-age)/.5,0,1)
		if alpha<=0: continue
		draw_circle(at,3.5,Color(Color("71d3df") if contact[1] else Color("ff775c"),alpha))
		if absf(contact[0].y-game.player.position.y)>2:
			var sign_y = -1 if contact[0].y>game.player.position.y else 1
			draw_line(at+Vector2(-2,sign_y*6),at+Vector2(0,sign_y*8),ink,1)
			draw_line(at+Vector2(0,sign_y*8),at+Vector2(2,sign_y*6),ink,1)
	var at = radar_point(game.player.position).clamp(Vector2(31,31),Vector2(229,229))
	var arrow = PackedVector2Array()
	for point in [Vector2(0,-7),Vector2(-5,5),Vector2(0,2),Vector2(5,5)]: arrow.append(at+point.rotated(-game.player.rotation.y))
	draw_colored_polygon(arrow,gold)

func _draw_medal() -> void:
	var award = game.challenges.current
	if award.is_empty(): return
	var age = game.challenges.elapsed
	var alpha = minf(clampf(age/.16,0,1),clampf((2.6-age)/.4,0,1))
	var color = Color(gold,alpha)
	var x = size.x*.5
	var y = (168.0 if game.net.is_destroy() else 128.0)-8.0*(1-clampf(age/.2,0,1))
	var points = PackedVector2Array([Vector2(x,y-21),Vector2(x+15,y),Vector2(x,y+21),Vector2(x-15,y),Vector2(x,y-21)])
	draw_polyline(points,color,2,true)
	draw_line(Vector2(x-180,y),Vector2(x-35,y),Color(gold,alpha*.5),1)
	draw_line(Vector2(x+35,y),Vector2(x+180,y),Color(gold,alpha*.5),1)
	medal_text("CHALLENGE COMPLETE" if award.milestone else "MEDAL EARNED",y-32,12,Color(ink,alpha))
	medal_text(award.title,y+51,25,color)
	medal_text(award.detail,y+73,14,Color(ink,alpha))

func medal_text(value: String, y: float, font_size: int, color: Color) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var at = Vector2((size.x-width)*.5,y)
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color(.03,.07,.09,color.a*.85))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func binding_name(action: String) -> String:
	var codes = game.prefs.data.bindings.get(action,[])
	return game.Preferences.key_label(codes[0]) if not codes.is_empty() else "Unbound"
func _draw_objective() -> void:
	var d = game.net.destroy
	var info = d.state()
	if info.is_empty(): return
	var attacking = info.attackers==game.player.team
	var seconds = maxi(0,ceili(info.deadline-game.clock))
	var role = "ATTACK" if attacking else "DEFEND"
	centered("ROUND %d / 5  •  %s  •  %02d:%02d" % [info.round,role,seconds/60,seconds%60],67,14,gold if info.phase=="planted" else dim)
	centered("%d ALIVE     FIRST TO 3     %d ALIVE" % [info.alive[1],info.alive[2]],86,12,dim)
	for i in range(2):
		var at = radar_point(d.SITES[i])
		draw_arc(at,10,0,TAU,24,gold,2,true)
		text_at("A" if i==0 else "B",at+Vector2(-4,4),12,ink)
		var camera = get_viewport().get_camera_3d()
		if camera!=null and not camera.is_position_behind(d.SITES[i]+Vector3.UP*2.5):
			var screen = camera.unproject_position(d.SITES[i]+Vector3.UP*2.5)
			if Rect2(30,110,size.x-60,size.y-230).has_point(screen):
				draw_circle(screen,13,Color(.04,.08,.10,.65))
				text_at("A" if i==0 else "B",screen+Vector2(-5,5),16,gold)
	if info.phase=="intermission":
		centered(info.reason,size.y*.32,28,gold)
		centered(("HALFTIME • SWITCHING SIDES  /  " if info.round==2 else "NEXT ROUND  /  ")+"%ds" % maxi(0,ceili(info.next-game.clock)),size.y*.32+28,16,ink)
	elif info.phase=="planted":
		centered("BOMB PLANTED AT "+("A" if info.site==0 else "B"),113,18,Color("ff9570"))
	if game.player.health<=0:
		centered("SPECTATING  •  "+d.spectating_name,size.y-112,17,ink)
		centered(binding_name("spectate_next")+"  NEXT TEAMMATE  •  One life per round",size.y-88,12,dim)
	elif info.worker==game.net.own_slot:
		var duration = d.PLANT_SECONDS if info.phase=="live" else d.DEFUSE_SECONDS
		centered("PLANTING" if info.phase=="live" else "DEFUSING",size.y*.62,18,gold)
		draw_rect(Rect2(size.x*.5-120,size.y*.62+12,240,4),Color(.12,.18,.2,.9))
		draw_rect(Rect2(size.x*.5-120,size.y*.62+12,240*clampf(info.work/duration,0,1),4),gold)
		centered("KEEP HOLDING "+binding_name("interact"),size.y*.62+40,12,dim)
	elif info.phase=="live" and info.carrier==game.net.own_slot:
		var near_site = game.player.position.distance_to(d.SITES[0])<2.8 or game.player.position.distance_to(d.SITES[1])<2.8
		centered("HOLD %s TO PLANT • STAND STILL" % binding_name("interact") if near_site else "YOU HAVE THE BOMB  •  %s TO DROP" % binding_name("drop_bomb"),size.y-112,15,gold)
	elif info.phase=="planted" and not attacking and game.player.position.distance_to(info.planted)<1.9:
		centered("HOLD %s TO DEFUSE • 8 SECONDS" % binding_name("interact"),size.y-112,15,gold)
	if info.phase=="live" and attacking:
		var bomb_at = info.dropped
		if info.carrier>=0:
			if info.carrier==game.net.own_slot: bomb_at = game.player.position
			elif game.net.server: bomb_at = game.net.slots[info.carrier].actor.position
			elif game.net.proxies.has(info.carrier): bomb_at = game.net.proxies[info.carrier].position
		draw_rect(Rect2(radar_point(bomb_at)-Vector2(3,3),Vector2(6,6)),gold)

func _draw_killcam() -> void:
	var replay=game.replays
	var red=Color("ef725b")
	if replay.scoped: _draw_scope()
	draw_rect(Rect2(12,12,size.x-24,size.y-24),Color(red,.65),false,2)
	draw_rect(Rect2(12,12,size.x-24,78),Color(.02,.04,.055,.8))
	centered("FINAL KILL" if replay.final else "KILLCAM",47,28,red)
	centered("0.25× SLOW MOTION" if replay.final and replay.playback_speed<1 else "FIRST-PERSON REPLAY",72,12,ink)
	var info=replay.clip.roster[replay.clip.killer]
	var victim=replay.clip.roster.get(replay.clip.victim,["PLAYER"])[0]
	draw_rect(Rect2(12,size.y-106,size.x-24,94),Color(.02,.04,.055,.84))
	centered(str(info[0])+"  →  "+str(victim),size.y-78,22,ink)
	centered(replay.clip.weapon+("  •  HEADSHOT" if replay.clip.head else ""),size.y-54,14,gold)
	centered("FINAL KILL REPLAY • CANNOT SKIP" if replay.final else "PRESS "+binding_name("jump")+" TO SKIP",size.y-28,13,dim)
	var length=maxf(.01,replay.clip.time-replay.clip.frames[0][0])
	draw_rect(Rect2(12,size.y-112,(size.x-24)*clampf((replay.cursor-replay.clip.frames[0][0])/length,0,1),3),red)
	if not replay.scoped:
		var at=size*.5
		for dir in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]: draw_line(at+dir*5,at+dir*11,ink,1.5)
	if replay.hit_played:
		for dir in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]: draw_line(size*.5+dir*14,size*.5+dir*22,gold if replay.clip.head else ink,2)
