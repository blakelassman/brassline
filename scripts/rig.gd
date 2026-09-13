extends RefCounted
## Articulated armor rig. Cosmetic motion stays within the fixed competitive hitboxes.
static var armor_meshes: Dictionary = {}
const Geo = preload("res://scripts/geo.gd")
static func joint(parent: Node3D, at: Vector3) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	node.position = at
	return node
static func armor(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> Node3D:
	var root = joint(parent,at)
	if armor_meshes.has(size):
		var cached = MeshInstance3D.new()
		cached.mesh = armor_meshes[size]
		cached.material_override = Geo.material(color)
		root.add_child(cached)
		return root
	# Eight-sided tapered shell: a chest/limb shape, with chamfered corners.
	var ring = [Vector2(-.34,-.5),Vector2(.34,-.5),Vector2(.5,-.3),Vector2(.5,.3),Vector2(.34,.5),Vector2(-.34,.5),Vector2(-.5,.3),Vector2(-.5,-.3)]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var a = ring[i]
		var b = ring[(i+1)%8]
		var top_a = Vector3(a.x*size.x,size.y*.5,a.y*size.z)
		var top_b = Vector3(b.x*size.x,size.y*.5,b.y*size.z)
		var low_a = Vector3(a.x*size.x*.78,-size.y*.5,a.y*size.z*.9)
		var low_b = Vector3(b.x*size.x*.78,-size.y*.5,b.y*size.z*.9)
		for v in [top_a,low_b,low_a,top_a,top_b,low_b,Vector3(0,size.y*.5,0),top_b,top_a,Vector3(0,-size.y*.5,0),low_a,low_b]: st.add_vertex(v)
	st.generate_normals()
	var mesh = MeshInstance3D.new()
	mesh.mesh = st.commit()
	armor_meshes[size] = mesh.mesh
	mesh.material_override = Geo.material(color)
	root.add_child(mesh)
	return root

static func build(parent: Node3D, color: Color, variant: int) -> Dictionary:
	var root = joint(parent,Vector3.ZERO)
	var dark = Color("253b49")
	var light = color.lightened(.22)
	var pelvis = Geo.box(root,Vector3(0,.68,0),Vector3(.46,.19,.30),dark,false,"rubber")
	var torso = joint(root,Vector3(0,1.06,0))
	armor(torso,Vector3.ZERO,Vector3(.56,.59,.32),dark)
	armor(torso,Vector3(0,.045,.14),Vector3(.57,.43,.12),color)
	Geo.box(torso,Vector3(0,.10,.205),Vector3(.35,.09,.035),light)
	for x in [-.16,.16]:
		Geo.box(torso,Vector3(x,-.18,.17),Vector3(.13,.16,.1),Color("b3a57f"),false,"rubber")
	Geo.box(torso,Vector3(0,-.25,.02),Vector3(.58,.08,.35),Color("67747a"),false,"metal")
	Geo.cylinder(root,Vector3(0,1.43,0),.1,.12,dark)
	var head = joint(root,Vector3(0,1.68,0))
	Geo.sphere(head,Vector3.ZERO,.225,color)
	Geo.box(head,Vector3(0,.015,.195),Vector3(.34,.13,.08),Color("122837"))
	Geo.box(head,Vector3(0,.015,.241),Vector3(.27,.045,.018),Color("9bdad6") if variant!=2 else Color("f5d68a"))
	Geo.box(head,Vector3(0,-.13,.13),Vector3(.25,.12,.17),dark)
	if variant==0:
		Geo.box(head,Vector3(0,.15,.015),Vector3(.35,.12,.35),color.darkened(.1))
	elif variant==1:
		Geo.box(head,Vector3(0,.11,.03),Vector3(.45,.06,.35),light)
		Geo.box(torso,Vector3(.24,0,-.20),Vector3(.15,.43,.15),light)
	else:
		Geo.box(torso,Vector3(0,.05,-.25),Vector3(.44,.55,.26),color,false,"panel")
		Geo.box(head,Vector3(-.2,.05,.16),Vector3(.1,.12,.15),Color("d6bb77"))
	# Helmet ear cups, collar, armored shoulders and textile seams.
	for side in [-1,1]:
		var ear = Geo.cylinder(head,Vector3(side*.215,0,0),.085,.045,dark)
		ear.rotation.z = PI/2
		Geo.box(torso,Vector3(side*.23,.05,.21),Vector3(.045,.34,.025),light)
		armor(root,Vector3(side*.4,1.32,0),Vector3(.28,.17,.29),color)
	Geo.cylinder(root,Vector3(0,1.40,0),.18,.08,light)
	var legs: Array = []
	var knees: Array = []
	var arms: Array = []
	var elbows: Array = []
	for side in [-1,1]:
		var leg = joint(root,Vector3(side*.18,.67,0))
		armor(leg,Vector3(0,-.14,0),Vector3(.23,.30,.26),dark)
		var knee = joint(leg,Vector3(0,-.30,0))
		Geo.box(knee,Vector3(0,-.07,.11),Vector3(.18,.18,.08),color)
		armor(knee,Vector3(0,-.14,0),Vector3(.19,.29,.23),dark)
		Geo.box(knee,Vector3(0,-.28,.06),Vector3(.22,.14,.34),Color("182e3a"),false,"rubber")
		legs.append(leg)
		knees.append(knee)
		var arm = joint(root,Vector3(side*.39,1.29,0))
		Geo.sphere(arm,Vector3.ZERO,.145,color)
		armor(arm,Vector3(0,-.13,0),Vector3(.20,.26,.22),color if variant!=1 else dark)
		var elbow = joint(arm,Vector3(0,-.27,0))
		armor(elbow,Vector3(0,-.12,0),Vector3(.18,.25,.20),dark)
		Geo.box(elbow,Vector3(0,-.27,.015),Vector3(.15,.13,.18),Color("78928f"),false,"rubber")
		arms.append(arm)
		elbows.append(elbow)
	Geo.finish_weapon(root)
	return {"root":root,"torso":torso,"head":head,"pelvis":pelvis,"legs":legs,"knees":knees,"arms":arms,"elbows":elbows}

static func animate(rig: Dictionary, speed: float, clock: float, hit: float, reload: float, shot: float, armed: bool) -> void:
	if rig.is_empty(): return
	var stride = minf(speed/5,1)
	var phase = clock*(9.5+stride*2)
	for i in range(2):
		var walk = sin(phase+i*PI)*stride
		rig.legs[i].rotation.x = walk*.55
		rig.knees[i].rotation.x = maxf(0,-walk)*.55
		rig.arms[i].rotation.x = -.95 if armed else -walk*.35
		rig.arms[i].rotation.z = (-.1 if i==0 else .1)
		rig.elbows[i].rotation.x = -.8 if armed else -.15
	if armed:
		rig.arms[0].rotation.z = -.28
		rig.arms[1].rotation.x -= shot*.8
		if reload>0:
			rig.arms[0].rotation.x = -.45+sin(clock*8)*.2
			rig.elbows[0].rotation.x = -1.6
			rig.arms[1].rotation.z = -.2
	rig.torso.rotation = Vector3(hit*.20,0,sin(phase)*stride*.035)
