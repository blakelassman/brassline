extends RefCounted
## Four fixed arenas with original architecture. Decorative meshes never block shots.
const Geo = preload("res://scripts/geo.gd")
const NAMES = ["FOUNDRY YARD","DRY DOCK","SUNSPIRE","RELAY"]
const DESCRIPTIONS = ["The original movement lab. Open sightlines and boost drills.","Container alleys, loading platforms and long dockside angles.","Warm courtyards, split lanes and a raised central terrace.","A cool industrial station with machinery and overhead routes."]
const FLOORS = ["concrete","metal","tile","metal"]
const PADS = [Vector3(-6,.06,6),Vector3(-10,.06,13),Vector3(-11,.06,13),Vector3(-11,.06,13)]
const PRACTICE = [[],[Vector3(-10,.05,-7),Vector3(1,.05,-12),Vector3(12,2.45,-5),Vector3(-14,.05,4),Vector3(10,.05,13),Vector3(0,.05,1),Vector3(0,.05,-3)],
	[Vector3(-11,.05,-8),Vector3(11,.05,-8),Vector3(0,2.05,-1),Vector3(-12,.05,4),Vector3(12,.05,12),Vector3(8,.05,0),Vector3(8,.05,-4)],
	[Vector3(-12,.05,-10),Vector3(1,.05,-13),Vector3(0,3.05,-8),Vector3(-12,.05,4),Vector3(12,.05,13),Vector3(11,.05,1),Vector3(11,.05,-3)]]

static func environment(parent: Node3D, index: int) -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = [Color("699eaf"),Color("447b96"),Color("629cad"),Color("182c48")][index]
	sky_mat.sky_horizon_color = [Color("d5ded2"),Color("c8d2c8"),Color("ebcf9f"),Color("71939e")][index]
	sky_mat.ground_bottom_color = Color("4d5860")
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c3d9ec")
	env.ambient_light_energy = .44 if index==3 else .25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	parent.add_child(env_node)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-32 if index!=2 else 28,0)
	sun.light_color = Color("ffe6bd") if index!=3 else Color("a2d7eb")
	sun.light_energy = .64 if index!=3 else .6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	parent.add_child(sun)

static func shell(parent: Node3D, index: int) -> void:
	var floor_color = [Color("b1b7ac"),Color("b1b7ac"),Color("e6d4ad"),Color("657d89")][index]
	var wall_color = [Color("719098"),Color("78949b"),Color("e3bb85"),Color("526b7c")][index]
	Geo.box(parent,Vector3(0,-.3,0),Vector3(42,.6,40),floor_color,true,FLOORS[index])
	for side in [-1,1]:
		Geo.box(parent,Vector3(side*20,3.5,0),Vector3(.8,7,40),wall_color,true,"brick" if index==2 else "panel")
		Geo.box(parent,Vector3(0,3.5,side*19),Vector3(40,7,.8),wall_color,true,"brick" if index==2 else "panel")
		Geo.box(parent,Vector3(side*19.55,.18,0),Vector3(.15,.36,38),Color("354c58"))
		Geo.box(parent,Vector3(0,.18,side*18.55),Vector3(40,.36,.15),Color("354c58"))
		for z in range(-16,19,4):
			Geo.box(parent,Vector3(side*19.5,3.4,z),Vector3(.35,6.8,.35),wall_color.darkened(.23))
	# Invisible high perimeter catches boosted players while leaving sky visible.
	for edge in [Vector3(-21,18,0),Vector3(21,18,0),Vector3(0,18,-20),Vector3(0,18,20)]:
		var barrier = StaticBody3D.new()
		parent.add_child(barrier)
		barrier.position = edge
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(1,36,44) if edge.x!=0 else Vector3(44,36,1)
		collision.shape = shape
		barrier.add_child(collision)
	Geo.sign_text(parent,Vector3(0,5.5,-18.5),NAMES[index],100,Color("f8e5bb"))
	Geo.sign_text(parent,Vector3(0,4.55,-18.48),"BRASSLINE / SECTOR 0%d" % index,25,Color("ddba74"))

static func lamp(parent: Node3D, pos: Vector3, color: Color, length: float = 2.0) -> void:
	var bar = Geo.box(parent,pos,Vector3(length,.1,.15),color)
	bar.get_child(0).material_override = Geo.material(color,1.8)
	var light = OmniLight3D.new()
	parent.add_child(light)
	light.position = pos+Vector3(0,-.2,.3)
	light.light_color = color
	light.light_energy = .65
	light.omni_range = 7
	light.shadow_enabled = false

static func container(parent: Node3D, pos: Vector3, size: Vector3, color: Color, id: String) -> void:
	var root = Geo.box(parent,pos,size,color,true,"panel")
	for x in [-1,1]:
		for z in [-1,1]:
			Geo.box(root,Vector3(x*(size.x*.5-.08),0,z*(size.z*.5+.01)),Vector3(.16,size.y,.10),color.darkened(.3))
	for x in [-.35,.35]:
		Geo.box(root,Vector3(x,size.y*.04,size.z*.5+.05),Vector3(.05,size.y*.85,.07),Color("c5c6b5"))
	Geo.sign_text(root,Vector3(0,size.y*.25,size.z*.5+.06),id,22,Color("f2e6cd"))
	Geo.box(root,Vector3(0,-size.y*.42,size.z*.5+.04),Vector3(size.x*.8,.13,.04),Color("dab768"))

static func ramp(parent: Node3D, center: Vector3, width: float, run: float, rise: float, color: Color) -> Node3D:
	# Wedge geometry keeps bot routes at ground level; human movement can walk up.
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a = Vector3(-width/2,0,run/2)
	var b = Vector3(width/2,0,run/2)
	var c = Vector3(width/2,rise,-run/2)
	var d = Vector3(-width/2,rise,-run/2)
	var e = Vector3(-width/2,0,-run/2)
	var f = Vector3(width/2,0,-run/2)
	for v in [a,c,b,a,d,c,a,e,d,b,c,f,e,f,c,e,c,d,a,b,f,a,f,e]:
		st.add_vertex(v)
	st.generate_normals()
	mesh = st.commit()
	var body = StaticBody3D.new()
	parent.add_child(body)
	body.position = center
	body.set_meta("surface","metal")
	var visual = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = Geo.textured(color,"metal")
	body.add_child(visual)
	var collision = CollisionShape3D.new()
	var shape = ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a,b,c,d,e,f])
	collision.shape = shape
	body.add_child(collision)
	return body

static func build(parent: Node3D, index: int) -> void:
	shell(parent,index)
	match index:
		1: dock(parent)
		2: sunspire(parent)
		3: relay(parent)
	# Mark the starting practice spot on every new map.
	Geo.box(parent,PADS[index]-Vector3.UP*.035,Vector3(2.6,.025,2.6),Color("d9b15b"))

static func dock(parent: Node3D) -> void:
	var navy = Color("3b7187")
	var orange = Color("d97b48")
	container(parent,Vector3(-7,1.4,-3),Vector3(4,2.8,8),navy,"BL / 071")
	container(parent,Vector3(7,1.4,6),Vector3(4,2.8,8),orange,"BL / 043")
	container(parent,Vector3(7,1.4,-10),Vector3(4,2.8,5),Color("93a780"),"BL / 019")
	container(parent,Vector3(-13,1.4,-12),Vector3(3,2.8,5),orange,"BL / 026")
	# Upper loading deck and a walkable ramp; the left and center lanes remain open.
	Geo.box(parent,Vector3(13,1.2,-5),Vector3(5,2.4,5),Color("718995"),true,"panel")
	ramp(parent,Vector3(13,0,1),3,7,2.4,Color("929f9f"))
	for z in [-7,-3]:
		Geo.box(parent,Vector3(15.55,2.9,z),Vector3(.1,1,.1),Color("e0bd6d"))
	Geo.beam(parent,Vector3(15.55,3.4,-7),Vector3(15.55,3.4,-3),.1,Color("e0bd6d"))
	Geo.crate(parent,Vector3(-12,.8,7),Vector3(2.5,1.6,2.5),Color("b9a37b"))
	Geo.crate(parent,Vector3(1,.55,7),Vector3(2,1.1,2),Color("b4a078"))
	for z in range(-16,18,3):
		Geo.box(parent,Vector3(2,.02,z),Vector3(.12,.025,1.4),Color("ead191"))
	for x in [-17,17]:
		Geo.box(parent,Vector3(x,5,-13),Vector3(.55,10,.55),Color("d0a150"))
	Geo.box(parent,Vector3(0,9.6,-13),Vector3(34,1,.8),Color("d0a150"))
	for x in range(-15,16,3):
		Geo.beam(parent,Vector3(x,9.1,-12.54),Vector3(x+2,10.1,-12.54),.12,Color("443f3d"))
	Geo.beam(parent,Vector3(-2,9.4,-13),Vector3(-2,6.1,-13),.035,Color("303b42"))
	Geo.cylinder(parent,Vector3(-2,6,-13),.18,.3,Color("d3b770"))
	for x in [-18,18]: lamp(parent,Vector3(x,5,-10),Color("c8e4e8"),2)
	# Skyline outside the playable boundary adds dock context without extra collision.
	for i in range(8):
		Geo.box(parent,Vector3(-30+i*9,2.5+(i%3),-29),Vector3(7,5+(i%3)*2,5),Color("597887"),false,"panel")

static func sunspire(parent: Node3D) -> void:
	var stone = Color("e3c294")
	var blue = Color("3b8994")
	# Central terrace, two long side routes, and covered courtyard pockets.
	Geo.box(parent,Vector3(0,1,-2),Vector3(8,2,6),stone,true,"brick")
	ramp(parent,Vector3(0,0,5),3.4,8,2,Color("dfc393"))
	for side in [-1,1]:
		Geo.box(parent,Vector3(side*12,1.5,-3),Vector3(3,3,3),stone,true,"brick")
		Geo.box(parent,Vector3(side*6.8,1.3,11),Vector3(2.5,2.6,4),blue,true,"tile")
		# Arched facade assembled around a real open passage, rather than a painted door.
		for dx in [-2,2]:
			Geo.box(parent,Vector3(side*10+dx,2,-13),Vector3(.7,4,.8),stone,true,"brick")
		Geo.box(parent,Vector3(side*10,4.3,-13),Vector3(4.8,.7,.8),stone,true,"brick")
		Geo.box(parent,Vector3(side*10,4.7,-13),Vector3(5,.12,1),Color("bf774f"))
		Geo.box(parent,Vector3(side*17,2.7,-2),Vector3(2.5,.15,6),Color("a75b48"))
		for z in [-4,0]:
			Geo.box(parent,Vector3(side*16,1.35,z),Vector3(.12,2.7,.12),Color("4f6566"))
		Geo.sign_text(parent,Vector3(side*12,2,-1.46),"EAST" if side>0 else "WEST",22,Color("604a38"))
	# Split fountain spire on the terrace gives a readable high-ground landmark.
	Geo.cylinder(parent,Vector3(0,2.12,-2),1.25,.24,blue)
	Geo.box(parent,Vector3(0,3.2,-2),Vector3(.75,2.2,.75),stone,true,"tile")
	for y in [2.35,3.45,4.25]:
		Geo.box(parent,Vector3(0,y,-2),Vector3(1.05,.15,1.05),Color("c18850"))
	for x in [-18,18]:
		for z in [-10,8]:
			Geo.cylinder(parent,Vector3(x,.35,z),.65,.7,Color("b97857"))
			Geo.cylinder(parent,Vector3(x,1.8,z),.11,2.8,Color("8a7352"))
			for angle in range(6):
				var branch = Geo.box(parent,Vector3(x,3,z),Vector3(.25,.10,2.6),Color("5c8263"))
				branch.rotation = Vector3(.22,angle*TAU/6,0)
	for x in range(-18,19,3):
		Geo.box(parent,Vector3(x,.025,15),Vector3(1.6,.02,.18),blue)
	for x in [-27,25]:
		Geo.box(parent,Vector3(x,5,-26),Vector3(9,10,10),stone,false,"brick")
		Geo.cylinder(parent,Vector3(x,12,-26),2.2,4,stone)
		Geo.sphere(parent,Vector3(x,14,-26),2.25,Color("51a0a4"))

static func relay(parent: Node3D) -> void:
	var dark = Color("3b5667")
	var pale = Color("94b4bc")
	for x in [-6,6]:
		Geo.box(parent,Vector3(x,1.65,0),Vector3(3,3.3,7),dark,true,"panel")
		for z in [-2,0,2]:
			Geo.box(parent,Vector3(x,1.8,z),Vector3(3.04,1.2,.5),pale,false,"metal")
			for side in [-1,1]:
				var display = Geo.box(parent,Vector3(x+side*1.53,2,z),Vector3(.025,.28,.48),Color("78c2b6"))
				display.get_child(0).material_override = Geo.material(Color("78c2b6"),.7)
		Geo.box(parent,Vector3(x,3.5,0),Vector3(3.3,.15,7.2),Color("d4af60"))
	# Upper service bridge accessible by ramp. The entire floor beneath stays connected.
	Geo.box(parent,Vector3(0,2.8,-8),Vector3(11,.4,3),pale,true,"metal")
	for x in [-5,5]:
		Geo.box(parent,Vector3(x,1.4,-8),Vector3(.35,2.8,.35),dark,true,"metal")
	ramp(parent,Vector3(-9.5,0,-8),3,8,3,pale).rotation.y = -PI/2
	for x in [-4,4]:
		Geo.box(parent,Vector3(x,3.5,-9.45),Vector3(.08,1,.08),Color("d4af60"))
	Geo.beam(parent,Vector3(-4,4,-9.45),Vector3(4,4,-9.45),.08,Color("d4af60"))
	container(parent,Vector3(-12,.85,8),Vector3(3,1.7,2.5),Color("a97849"),"POWER / 02")
	container(parent,Vector3(12,.85,-9),Vector3(3,1.7,2.5),Color("547b86"),"COMMS / 04")
	for z in [-14,-6,2,10]:
		Geo.box(parent,Vector3(0,8.6,z),Vector3(39,.45,.45),dark)
		for x in [-15,0,15]: lamp(parent,Vector3(x,8.3,z),Color("acdce2"),4)
	# Partial roof: bright skylight strips preserve orientation and boost readability.
	for x in [-15,15]:
		Geo.box(parent,Vector3(x,9,0),Vector3(9,.3,38),dark,true,"panel")
	for x in [-18.8,18.8]:
		var pipe = Geo.cylinder(parent,Vector3(x,6,0),.24,36,Color("d9aa63"))
		pipe.rotation.x = PI/2
	for z in range(-16,18,3):
		Geo.box(parent,Vector3(0,.025,z),Vector3(.16,.025,1.2),Color("d7bd70"))
	Geo.sign_text(parent,Vector3(0,1.5,17.5),"RELAY / KEEP MOVING",35,Color("e0cc9b")).rotation.y = PI

static func foundry_details(parent: Node3D) -> void:
	for x in [-18,-10,2,14]:
		Geo.box(parent,Vector3(x,3.3,-18.48),Vector3(2.3,1.5,.10),Color("243e4e"),false,"panel")
		Geo.box(parent,Vector3(x,3.3,-18.40),Vector3(.08,1.5,.06),Color("82a6ad"))
	for x in [-19.4,19.4]:
		var pipe = Geo.cylinder(parent,Vector3(x,4,0),.12,32,Color("aa9067"))
		pipe.rotation.x = PI/2
	lamp(parent,Vector3(-15,5.8,-15),Color("e9d4a3"),2)
	lamp(parent,Vector3(15,5.8,-15),Color("b6dce4"),2)
	for i in range(6):
		Geo.box(parent,Vector3(-25+i*10,4,-29),Vector3(7,8+(i%3)*3,8),Color("78919b"),false,"brick")
