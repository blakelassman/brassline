extends RefCounted
## Four objective districts. A and B have independent long/short entrances,
## a defender rotation corridor, central cut-through and elevated overwatch.
const Geo = preload("res://scripts/geo.gd")
const Maps = preload("res://scripts/maps.gd")
const NAMES = ["FOUNDRY • REACTOR","DOCK • CUSTOMS","SUNSPIRE • VAULT","RELAY • UPLINK"]
const BLOCKS = [Vector3(-10,4,0),Vector3(10,4,PI)]
static func footprints() -> Array:
	return [Rect2(-16,-1,12,10),Rect2(4,-1,12,10),Rect2(-8,-17,16,1),Rect2(-8,17,16,1)]
static func build(parent: Node3D, index: int) -> void:
	var wall = [Color("aa7058"),Color("607d88"),Color("d2a97c"),Color("6e8993")][index]
	var trim = [Color("718d8c"),Color("ceab68"),Color("b47558"),Color("76b7be")][index]
	Geo.box(parent,Vector3(0,-.25,0),Vector3(64,.5,62),Color("7b817a"),true,"tile" if index==2 else "concrete")
	for i in range(2): Maps.building(parent,BLOCKS[i],wall,trim,index,i)
	for side in [-1,1]:
		Geo.box(parent,Vector3(side*31,2.5,0),Vector3(.5,5,62),wall,true,"brick")
		Geo.box(parent,Vector3(0,2.5,side*30),Vector3(62,5,.5),wall,true,"brick")
		Geo.box(parent,Vector3(0,2,side*17),Vector3(16,4,1),wall,true,"brick")
		# Mid-street doglegs break spawn-to-spawn sightlines without sealing rotations.
		Geo.box(parent,Vector3(side*2.2,1.6,side*10.5),Vector3(4.4,3.2,.65),trim,true,"panel")
		# Outer routes: roofed colonnades, shallow cover and two open site approaches.
		for z in [-18,-2,13]:
			Geo.box(parent,Vector3(side*28,1.9,z),Vector3(.55,3.8,.55),wall,true,"brick")
		Geo.box(parent,Vector3(side*28,3.9,-2.5),Vector3(5,.25,34),trim,true,"panel")
		for z in [17,-20]:
			Geo.crate(parent,Vector3(side*20,.7,z),Vector3(3,1.4,2.5),trim)
		# Site-back shelter opens toward the site, leaving the far rotation alley clear.
		Geo.box(parent,Vector3(side*21,2.4,-15),Vector3(7,.3,5),wall,true,"metal")
		Geo.box(parent,Vector3(side*24.3,1.2,-15),Vector3(.4,2.4,5),wall,true,"brick")
		for x in [-1,1]: Geo.box(parent,Vector3(side*21+x*3.3,1.2,-17.3),Vector3(.4,2.4,.4),trim,true,"metal")
		# Boostable site cover, outside the clear 2.8m planting circle.
		Geo.crate(parent,Vector3(side*17,1,-9),Vector3(2.2,2,3),trim)
		var boundary = StaticBody3D.new()
		parent.add_child(boundary)
		for axis in range(2):
			var shape = CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			shape.shape.size = Vector3(.5,45,64) if axis==0 else Vector3(64,45,.5)
			shape.position = Vector3(side*31.5,22,0) if axis==0 else Vector3(0,22,side*30.5)
			boundary.add_child(shape)
		for z in [-23,-10,5,21]:
			Geo.box(parent,Vector3(side*36,5,z),Vector3(6,10,8),wall.darkened(.25),false,"brick")
	for i in range(2):
		var at = Vector3(-21 if i==0 else 21,.024,-9)
		var color = Color("efb655") if i==0 else Color("72cbd1")
		for side in [-1,1]:
			Geo.box(parent,at+Vector3(side*2.8,0,0),Vector3(.10,.025,5.6),color)
			Geo.box(parent,at+Vector3(0,0,side*2.8),Vector3(5.6,.025,.10),color)
		Geo.sign_text(parent,at+Vector3(0,2.9,-4.5),"A" if i==0 else "B",96,color)
		Geo.sign_text(parent,at+Vector3(0,.4,-4.5),["REACTOR","CUSTOMS","VAULT","UPLINK"][index],22,color)
	# Each district changes mid cover and long-lane angles, while site approaches
	# and spawn distances remain learnable. Decoration never adds stair collision.
	match index:
		0:
			for x in [-25,25]:
				Geo.cylinder(parent,Vector3(x,1.1,7),.9,2.2,trim)
				Geo.box(parent,Vector3(x,1.1,7),Vector3(1.8,2.2,1.8),trim,true,"metal")
		1:
			for x in [-23,23]:
				Geo.box(parent,Vector3(x,1.3,4),Vector3(2.4,2.6,5),wall,true,"panel")
			for x in [-13,13]: Geo.box(parent,Vector3(x,5.5,-22),Vector3(.6,11,.6),trim,true,"metal")
			Geo.box(parent,Vector3(0,11,-22),Vector3(27,.7,.8),trim)
		2:
			for x in [-24,24]:
				Geo.box(parent,Vector3(x,.55,6),Vector3(2,1.1,3),trim,true,"tile")
				Geo.sphere(parent,Vector3(x,1.5,6),.9,Color("587e60"))
		3:
			for x in [-22,22]:
				Geo.box(parent,Vector3(x,1.1,7),Vector3(3,2.2,2),wall,true,"panel")
				Geo.beam(parent,Vector3(x,2.2,7),Vector3(x,8,7),.16,trim)
