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
	queue_redraw()
	vote_panel.visible = game.net.running and not game.net.round_active and not game.menu_open
	if vote_panel.visible:
		vote_label.text = "%s\nBLUE %d  /  RED %d\n%s" % [game.net.winner,game.combat.scores[1],game.combat.scores[2],"LOADING NEXT ARENA…" if game.net.loading_round else "VOTE NEXT MAP  /  %ds" % maxi(0,ceili(game.net.vote_end-game.clock))]
		for index in range(4):
			vote_buttons[index].text = game.Maps.NAMES[index]+"\n%d VOTES" % game.net.vote_counts[index]
			vote_buttons[index].disabled = game.net.loading_round


func text_at(text: String, at: Vector2, size: int = 18, color: Color = ink) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func centered(text: String, y: float, size: int = 18, color: Color = ink) -> void:
	var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text_at(text, Vector2((self.size.x-width)/2,y), size, color)

func _draw() -> void:
	if font == null or game.player == null:
		return
	var w = size.x
	var h = size.y
	if not game.active or game.menu_open:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.04,0.10,0.13,0.76))
		return
	var p = game.player
	var scoped = p.weapon == 3 and p.scope_age >= Rules.SCOPE_READY and p.held_grenade.is_empty()
	if scoped:
		_draw_scope()
	draw_rect(Rect2(24,22,300,65),Color(0.06,0.15,0.19,0.9))
	text_at("BRASSLINE",Vector2(40,49),23,ink)
	text_at(game.Maps.NAMES[game.current_map]+(" / 5v5" if game.mode in ["combat","online"] else " / TRAINING"),Vector2(40,71),12,dim)
	draw_rect(Rect2(w-235,22,210,65),Color(0.06,0.15,0.19,0.9))
	if game.mode in ["combat","online"]:
		text_at("BLUE %d / RED %d" % [game.combat.scores[1],game.combat.scores[2]],Vector2(w-217,48),18,ink)
		text_at("YOU  %d KILLS / %d DEATHS" % [game.kills,game.combat.deaths],Vector2(w-217,71),12,gold)
	else:
		text_at("%02d  TARGETS" % game.kills,Vector2(w-217,48),20,ink)
		text_at("%02d AIR HEADS   /   %02d BOOSTS" % [game.air_heads,game.perfect_boosts],Vector2(w-217,71),12,gold)
	if game.net.running:
		var seconds = maxi(0,ceili(game.net.round_end-game.clock)) if game.net.round_active else 0
		centered("%02d:%02d   /   FIRST TO 250   /   %s TEAM" % [seconds/60,seconds%60,"BLUE" if p.team==1 else "RED"],44,16,gold)
	if game.net.is_client_ready():
		var stale = (Time.get_ticks_msec()-game.net.last_packet)/1000.0
		var connection = "%d ms PING  /  %d FPS  /  SERVER %d Hz" % [game.net.ping_ms,Engine.get_frames_per_second(),int(game.net.server_tick_rate)]
		if stale>.5: connection = "CONNECTION INTERRUPTED  /  %.1fs SINCE UPDATE" % stale
		text_at(connection,Vector2(40,105),12,gold if stale>.5 or game.net.ping_ms>150 else dim)
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
	draw_rect(Rect2(24,h-96,300,70),Color(0.06,0.15,0.19,0.94))
	text_at(str(p.health),Vector2(40,h-56),31,Color("ff9275") if p.health<40 else ink)
	text_at("HEALTH",Vector2(105,h-58),12,dim)
	text_at("G  BLAST  %d     Q  SMOKE  %d" % [p.blast_count,p.smoke_count],Vector2(40,h-39),13,gold)
	draw_rect(Rect2(w-280,h-96,255,70),Color(0.06,0.15,0.19,0.94))
	text_at(p.held_grenade.to_upper()+" GRENADE" if not p.held_grenade.is_empty() else Rules.WEAPONS[p.weapon]["name"],Vector2(w-260,h-67),14,gold)
	var ammo_text = "%02d / %02d" % [p.ammo[p.weapon],Rules.WEAPONS[p.weapon]["mag"]] if p.weapon != 2 else "CLOSE RANGE"
	if not p.held_grenade.is_empty():
		ammo_text = "L THROW / R DROP"
	text_at(ammo_text,Vector2(w-260,h-39),19 if not p.held_grenade.is_empty() else 26,ink)
	if p.reload_timer > 0:
		draw_rect(Rect2(w/2-100,h-130,200,45),Color(.06,.15,.19,.92))
		centered("RELOADING",h-108,16,gold)
		draw_rect(Rect2(w/2-80,h-97,160,3),Color(.1,.2,.24,.9))
		draw_rect(Rect2(w/2-80,h-97,160*(1-p.reload_timer/float(Rules.WEAPONS[p.weapon]["reload"])),3),gold)
	draw_rect(Rect2(w/2-218,h-63,436,37),Color(0.06,0.15,0.19,0.94))
	centered("1 RIFLE    2 PISTOL    3 SWORD    4 SNIPER",h-39,14,ink)
	if help_visible:
		draw_rect(Rect2(24,110,335,133),Color(0.06,0.15,0.19,0.86))
		if game.mode in ["combat","online"]:
			text_at("ENDLESS 5v5",Vector2(40,138),17,gold)
			text_at("Teal allies. Orange enemies. No score limit.",Vector2(40,163),14,ink)
			text_at("Instant respawns. No spawn protection.",Vector2(40,185),14,ink)
			text_at("Smoke blocks bot vision. Cover stops shots.",Vector2(40,207),14,ink)
			text_at("Esc pause / switch arenas   /   H hide tips",Vector2(40,230),12,dim)
		else:
			text_at("THE BOOST SHOT",Vector2(40,138),17,gold)
			text_at("G equips the grenade. Right-click drops it.",Vector2(40,163),14,ink)
			text_at("Jump just before the burst.",Vector2(40,185),14,ink)
			text_at("2 for the pistol. Shoot above the wall.",Vector2(40,207),14,ink)
			text_at("F refill   /   T reset   /   H hide tips",Vector2(40,230),12,dim)
	_draw_feed()
	var fuse = -1.0
	for grenade in game.grenades:
		if is_instance_valid(grenade) and grenade.kind == "blast":
			fuse = grenade.fuse if fuse < 0 else minf(fuse,grenade.fuse)
	if fuse >= 0:
		var y = h-159
		draw_rect(Rect2(w/2-150,y,300,8),Color(0.07,0.16,0.19,0.94))
		draw_rect(Rect2(w/2-150,y,300*clampf(fuse/Rules.FUSE,0,1),8),gold)
		centered("JUMP NOW" if fuse <= Rules.PERFECT_WINDOW else "BLAST  %.2f s" % fuse,y-12,21,gold)
	elif p.max_height > 0.2:
		centered("LAST BOOST  %.1f m" % p.max_height,h-132,16,gold)
	if game.toast_time > 0:
		draw_rect(Rect2(w/2-240,96,480,69),Color(.06,.15,.19,.87))
		centered(game.toast_title,126,27,gold)
		centered(game.toast_detail,152,15,ink)
	draw_rect(Rect2(w-116,h-132,91,26),Color(0.06,0.15,0.19,0.94))
	text_at("ESC  MENU",Vector2(w-107,h-113),11,ink)
	if game.mode in ["combat","online"]:
		if p.hurt_flash>0:
			draw_rect(Rect2(Vector2.ZERO,size),Color(.8,.10,.04,p.hurt_flash*.35))
			draw_rect(Rect2(3,3,w-6,h-6),Color(.95,.18,.07,p.hurt_flash*2),false,6)

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
		var y = size.y-365+i*29
		draw_rect(Rect2(x,y,360,25),Color(.045,.11,.14,.86*opacity))
		draw_rect(Rect2(x,y,3,25),Color(Color("71d3df") if entry.get("team",1)==1 else Color("ff9772"),opacity))
		if entry.get("killer","")=="YOU": draw_rect(Rect2(x,y,360,25),Color(gold,opacity),false,1.5)
		text_at(entry.killer,Vector2(x+11,y+17),12,Color(ink,opacity))
		Icons.draw_icon(self,Vector2(x+111,y+1),"HEADSHOT" if entry.head else entry.weapon,Color(gold if entry.head else ink,opacity))
		text_at(entry.victim,Vector2(x+181,y+17),12,Color(ink,opacity))
		if entry.collateral: text_at("COLL",Vector2(x+316,y+17),10,Color(gold,opacity))
	var p = game.player
	var speed = Vector2(p.velocity.x,p.velocity.z).length()
	draw_rect(Rect2(24,size.y-137,210,29),Color(.06,.15,.19,.9))
	text_at("%.1f m/s  /  %s" % [speed,"AIR" if not p.is_on_floor() else ("READY" if p.current_spread()<.05 else "MOVING")],Vector2(40,size.y-117),13,gold)

func award_text(value: String, y: float, font_size: int, color: Color) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var at = Vector2((size.x-width)*.5,y)
	draw_string_outline(font,at+Vector2(1,2),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color(0,0,0,color.a*.65))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw_xp() -> void:
	var p = game.progression
	var level = p.level_for("YOU")
	var earned = p.xp_for("YOU")-p.threshold(level)
	var needed = p.threshold(mini(1000,level+1))-p.threshold(level)
	var fraction = float(earned)/maxf(1,needed) if level<1000 else 1.0
	draw_rect(Rect2(24,size.y-180,245,34),Color(.06,.15,.19,.92))
	text_at("LV %d  /  TAB SCOREBOARD" % level,Vector2(36,size.y-164),12,gold)
	draw_rect(Rect2(36,size.y-157,221,3),Color(.25,.35,.38))
	draw_rect(Rect2(36,size.y-157,221*fraction,3),gold)
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
	text_at("ENDLESS 5v5" if game.mode in ["combat","online"] else "AIM TRAINING",Vector2(x+565,y+38),17,gold)
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
	text_at("Your level is saved. Release your scoreboard key to return. Combat continues.",Vector2(x+28,y+582),13,dim)
