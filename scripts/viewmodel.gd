extends Node
## A separate transparent 3D pass keeps the hands and weapons in front of cover.
const Geo = preload("res://scripts/geo.gd")
const Rules = preload("res://scripts/rules.gd")
var recoil_position = 0.0
var recoil_velocity = 0.0
var flash_time = 0.0
var flashes: Array[Node3D] = []
var casings: Array = []
var shell_root: Node3D
var player: CharacterBody3D
var viewport: SubViewport
var root: Node3D
var models: Array[Node3D] = []
var magazines: Array[Node3D] = []
var mag_origins: Array[Vector3] = []
var support_hands: Array[Node3D] = []
var bolts: Array[Node3D] = []
var grenade_model: Node3D
var grenade_shell: MeshInstance3D

func _ready() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var container = SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var camera = Camera3D.new()
	camera.near = 0.025
	camera.fov = 75
	viewport.add_child(camera)
	camera.current = true
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ddeaf0")
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30,-25,0)
	key.light_energy = 0.65
	viewport.add_child(key)
	shell_root = Node3D.new()
	viewport.add_child(shell_root)
	root = Node3D.new()
	viewport.add_child(root)
	var dark = Color("263740")
	var cream = Color("8ba1a3")
	var gold = Color("b88a45")
	for index in range(4):
		var model = Node3D.new()
		root.add_child(model)
		models.append(model)
		var mag = Node3D.new()
		model.add_child(mag)
		magazines.append(mag)
		var bolt = Node3D.new()
		model.add_child(bolt)
		bolts.append(bolt)
		if index == 0:
			Geo.box(model,Vector3.ZERO,Vector3(.14,.16,.56),cream)
			Geo.box(model,Vector3(0,.01,-.38),Vector3(.10,.12,.25),dark)
			Geo.box(model,Vector3(0,.025,-.59),Vector3(.045,.045,.23),dark)
			Geo.box(model,Vector3(0,.025,-.73),Vector3(.065,.065,.07),gold)
			Geo.box(model,Vector3(0,-.1,.15),Vector3(.10,.24,.12),dark)
			mag.position = Vector3(0,-.16,-.11)
			Geo.box(mag,Vector3.ZERO,Vector3(.095,.23,.15),dark)
			Geo.box(bolt,Vector3(.09,.015,.07),Vector3(.065,.035,.10),dark)
			for i in range(6):
				Geo.box(model,Vector3(0,.092,-.24+i*.06),Vector3(.12,.012,.023),dark)
			for i in range(4):
				Geo.box(model,Vector3(.052,.025,-.31-i*.06),Vector3(.012,.035,.028),gold)
		elif index == 1:
			Geo.box(bolt,Vector3(0,.045,.03),Vector3(.125,.13,.41),gold)
			Geo.box(model,Vector3(0,-.1,.15),Vector3(.10,.22,.13),dark)
			mag.position = Vector3(0,-.22,.15)
			Geo.box(mag,Vector3.ZERO,Vector3(.105,.065,.14),cream)
			Geo.box(bolt,Vector3(0,.12,-.13),Vector3(.025,.025,.03),cream)
			for i in range(4):
				Geo.box(bolt,Vector3(.064,.05,.08+i*.03),Vector3(.008,.075,.008),dark)
		elif index == 2:
			Geo.box(model,Vector3(0,0,-.24),Vector3(.06,.025,.85),cream)
			Geo.box(model,Vector3(0,.016,-.24),Vector3(.014,.01,.76),gold)
			Geo.box(model,Vector3(0,0,.22),Vector3(.28,.07,.045),gold)
			Geo.box(model,Vector3(0,0,.34),Vector3(.06,.065,.19),dark)
		else:
			Geo.box(model,Vector3(0,0,-.1),Vector3(.14,.14,.72),Color("4e7773"))
			Geo.box(model,Vector3(0,-.04,.26),Vector3(.13,.22,.3),dark)
			Geo.box(model,Vector3(0,.04,-.68),Vector3(.046,.046,.5),dark)
			Geo.box(model,Vector3(0,.04,-.96),Vector3(.075,.075,.09),gold)
			var scope = Geo.cylinder(model,Vector3(0,.17,-.10),.062,.30,dark)
			scope.rotation.x = PI/2
			var glass = Geo.cylinder(model,Vector3(0,.17,.056),.052,.012,Color("4db8bc"))
			glass.rotation.x = PI/2
			Geo.box(model,Vector3(0,.10,-.10),Vector3(.06,.1,.08),dark)
			mag.position = Vector3(0,-.13,-.03)
			Geo.box(mag,Vector3.ZERO,Vector3(.1,.17,.14),dark)
			Geo.box(bolt,Vector3(.115,.015,.08),Vector3(.12,.045,.04),gold)
			Geo.sphere(bolt,Vector3(.19,.015,.08),.034,dark)
		preload("res://scripts/weapon_art.gd").detail(model,index)
		mag_origins.append(mag.position)
		var main_hand = make_hand(model,Vector3(.025,-.18,.28))
		var hand = make_hand(model,Vector3(-.035,-.13,-.22))
		support_hands.append(hand)
		if index!=2:
			# Receiver pins, ejection port, barrel and iron-sight details break up the silhouette.
			Geo.box(model,Vector3(.075,.015,.015),Vector3(.009,.045,.11),Color("172a33"))
			for z in [-.08,.14]:
				var pin = Geo.cylinder(model,Vector3(.078,.02,z),.012,.012,Color("b2b6ac"))
				pin.rotation.z = PI/2
			var barrel_z = [-.76,-.20,0,-1.01][index]
			var tip = Geo.cylinder(model,Vector3(0,.025,barrel_z),.032,.05,dark)
			tip.rotation.x = PI/2
			var bore = Geo.cylinder(model,Vector3(0,.025,barrel_z-.028),.017,.004,Color("081419"))
			bore.rotation.x = PI/2
			Geo.box(model,Vector3(0,.105,barrel_z+.08),Vector3(.016,.07,.025),dark)
		var flash = Node3D.new()
		model.add_child(flash)
		flash.set_meta("no_finish",true)
		flash.position = Vector3(0,.025,[-.82,-.26,0,-1.07][index])
		for turn in range(3):
			var flame = Geo.box(flash,Vector3(0,0,-.055),Vector3(.018,.075,.14),Color("ffdf9a"))
			flame.rotation.z = turn*PI/3
			var mat = Geo.material(Color("ffe3a5"),2)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flame.get_child(0).material_override = mat
		flash.hide()
		flashes.append(flash)
		for part in model.get_children():
			if part!=flash: Geo.finish_weapon(part)
		preload("res://scripts/optimizer.gd").batch(model,[mag,bolt,hand,main_hand,flash])
	grenade_model = Node3D.new()
	root.add_child(grenade_model)
	grenade_shell = Geo.sphere(grenade_model,Vector3(0,0,.02),.12,gold)
	for y in [-.065,0,.065]:
		Geo.box(grenade_model,Vector3(0,y,.11),Vector3(.17,.018,.03),dark)
	Geo.box(grenade_model,Vector3(0,.12,.02),Vector3(.075,.07,.075),dark)
	Geo.box(grenade_model,Vector3(.075,.075,.02),Vector3(.03,.16,.04),cream)
	Geo.box(grenade_model,Vector3(0,-.13,.17),Vector3(.16,.14,.29),Color("315e69"))
	Geo.finish_weapon(grenade_model)
	apply_cosmetics()
	update_pose(0.0)

func update_pose(delta: float) -> void:
	var aiming = player.is_aiming()
	root.visible = player.health>0 and not (player.weapon == 3 and player.scope_age >= Rules.SCOPE_READY and player.held_grenade.is_empty())
	if delta>0:
		recoil_velocity += (-155*recoil_position-23*recoil_velocity)*delta
		recoil_position += recoil_velocity*delta
		flash_time = maxf(0,flash_time-delta)
		for shell in casings:
			shell.life -= delta
			shell.velocity.y -= 5*delta
			shell.node.position += shell.velocity*delta
			shell.node.rotate_x(delta*13)
			shell.node.rotate_z(delta*8)
			if shell.life<=0: shell.node.queue_free()
		casings = casings.filter(func(shell): return shell.life>0)
	var moving = minf(Vector2(player.velocity.x,player.velocity.z).length()/6,1)
	var bob = sin(player.movement_phase*2)*.009*moving if player.is_on_floor() else 0.0
	var draw = clampf(player.equip_cooldown/.22,0,1)
	root.position = Vector3(.29 if aiming else .36,-.30+bob-player.landing_pose*.08,-.62+recoil_position*.10)
	root.position += Vector3(sin(player.movement_phase)*.009*moving,0,0)
	root.position += Vector3(-player.look_sway.x,-player.look_sway.y,0)
	root.position.y -= draw*draw*.34
	root.rotation = Vector3(recoil_position*.15+draw*.5+player.look_sway.y,-player.look_sway.x,cos(player.movement_phase)*.018*moving)
	root.scale = Vector3.ONE*.83
	for i in range(models.size()):
		flashes[i].visible = flash_time>0 and i==player.weapon and i!=2
		models[i].visible = i == player.weapon and player.held_grenade.is_empty()
		magazines[i].position = mag_origins[i]
		magazines[i].rotation = Vector3.ZERO
		support_hands[i].position = Vector3(-.035,-.13,-.22)
		support_hands[i].visible = i != 1 and i != 2
		bolts[i].position.z = player.visual_kick*.06 if i == 1 else 0.0
	grenade_model.visible = not player.held_grenade.is_empty()
	grenade_shell.material_override.albedo_color = Color("efb447") if player.held_grenade == "blast" else Color("80bfb9")
	if player.reload_timer > 0:
		var progress = 1.0-player.reload_timer/float(Rules.WEAPONS[player.weapon]["reload"])
		var tilt = sin(PI*progress)
		root.rotation += Vector3(-.25*tilt,.08*tilt,.72*tilt)
		root.position += Vector3(-.15*tilt,.09*tilt,-.13*tilt)
		# Remove the magazine, dip it below frame, seat it, then rack the action.
		var travel = smoothstep(.12,.35,progress)*(1.0-smoothstep(.48,.72,progress))
		var mag = magazines[player.weapon]
		mag.position += Vector3(-.12*travel,-.48*travel,.10*travel)
		mag.rotation.z = -.35*travel
		var hand = support_hands[player.weapon]
		hand.visible = true
		hand.position = Vector3(-.035,-.13,-.22).lerp(mag.position+Vector3(-.07,-.04,.09),smoothstep(.04,.16,progress)*(1-smoothstep(.76,.94,progress)))
		bolts[player.weapon].position.z = .10*sin(PI*clampf((progress-.78)/.2,0,1))
	elif player.weapon == 3 and player.sniper_cycle > 0:
		var cycle = 1.0-player.sniper_cycle/1.1
		var motion = sin(PI*clampf((cycle-.12)/.78,0,1))
		bolts[3].position.z = .14*motion
		root.rotation.z = -.075*motion
		root.position.y -= .035*motion
		support_hands[3].position = Vector3(.08,-.05,.04)+Vector3(0,0,.14*motion)
	if player.parry_timer > 0:
		var guard = smoothstep(0,.06,player.parry_timer)
		root.rotation += Vector3(.12,.4,1.1)*guard
		root.position += Vector3(-.26,.17,.12)*guard
	if player.swing_timer > 0:
		var slash = sin(PI*clampf((.5-player.swing_timer)/.38,0,1))
		root.rotation += Vector3(-.18*slash,-.5*slash,-1.2*slash)
		root.position.x -= .42*slash
	if player.throw_pose > 0:
		root.position.y -= sin(player.throw_pose*PI/.3)*.20

func make_hand(parent: Node3D, at: Vector3) -> Node3D:
	var hand = Node3D.new()
	hand.set_meta("no_finish",true)
	parent.add_child(hand)
	hand.position = at
	Geo.box(hand,Vector3.ZERO,Vector3(.13,.10,.16),Color("536f74"),false,"rubber")
	Geo.box(hand,Vector3(0,.045,.01),Vector3(.11,.025,.10),Color("263e4d"))
	for i in range(4):
		Geo.box(hand,Vector3(-.045+i*.03,0,-.09),Vector3(.026,.075,.06),Color("354e5a"))
	Geo.box(hand,Vector3(.072,-.025,0),Vector3(.05,.05,.09),Color("536f74"))
	Geo.box(hand,Vector3(0,-.035,.18),Vector3(.16,.14,.26),Color("355c6b"),false,"rubber")
	Geo.box(hand,Vector3(0,.015,.08),Vector3(.17,.025,.065),Color("b59b61"))
	return hand

func on_shot() -> void:
	recoil_velocity += 7 if player.weapon==0 else 11
	flash_time = .055
	if casings.size()>=10:
		casings[0].node.queue_free()
		casings.pop_front()
	var shell = Geo.cylinder(shell_root,Vector3.ZERO,.012,.05,Color("d3ad60"))
	shell.position = root.global_transform*Vector3(.14,.025,.04)
	shell.rotation.z = PI/2
	casings.append({"node":shell,"velocity":Vector3(1.5,1.0,.25),"life":.65})

func apply_cosmetics() -> void:
	var collection = preload("res://scripts/cosmetics.gd")
	var loadout = collection.clean_loadout(player.cosmetics)
	for index in range(models.size()): collection.paint(models[index],loadout[["rifle","pistol","sword","sniper"][index]])
