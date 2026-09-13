extends RefCounted
## Articulated armor rig. Cosmetic motion stays within the fixed competitive hitboxes.
const Geo = preload("res://scripts/geo.gd")
static func joint(parent: Node3D, at: Vector3) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	node.position = at
	return node
static func build(parent: Node3D, color: Color, variant: int) -> Dictionary:
	var root = joint(parent,Vector3.ZERO)
	var dark = Color("253b49")
	var light = color.lightened(.22)
	var pelvis = Geo.box(root,Vector3(0,.68,0),Vector3(.46,.19,.30),dark,false,"rubber")
	var torso = joint(root,Vector3(0,1.06,0))
	Geo.box(torso,Vector3.ZERO,Vector3(.56,.59,.32),dark,false,"rubber")
	Geo.box(torso,Vector3(0,.045,.14),Vector3(.57,.43,.10),color,false,"panel")
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
	var legs: Array = []
	var knees: Array = []
	var arms: Array = []
	var elbows: Array = []
	for side in [-1,1]:
		var leg = joint(root,Vector3(side*.18,.67,0))
		Geo.box(leg,Vector3(0,-.14,0),Vector3(.20,.30,.24),dark,false,"rubber")
		var knee = joint(leg,Vector3(0,-.30,0))
		Geo.box(knee,Vector3(0,-.07,.11),Vector3(.18,.18,.08),color)
		Geo.box(knee,Vector3(0,-.14,0),Vector3(.17,.29,.20),dark,false,"rubber")
		Geo.box(knee,Vector3(0,-.28,.06),Vector3(.22,.14,.34),Color("182e3a"),false,"rubber")
		legs.append(leg)
		knees.append(knee)
		var arm = joint(root,Vector3(side*.39,1.29,0))
		Geo.sphere(arm,Vector3.ZERO,.145,color)
		Geo.box(arm,Vector3(0,-.13,0),Vector3(.18,.26,.20),color if variant!=1 else dark)
		var elbow = joint(arm,Vector3(0,-.27,0))
		Geo.box(elbow,Vector3(0,-.12,0),Vector3(.16,.25,.18),dark,false,"rubber")
		Geo.box(elbow,Vector3(0,-.27,.015),Vector3(.15,.13,.18),Color("78928f"),false,"rubber")
		arms.append(arm)
		elbows.append(elbow)
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
