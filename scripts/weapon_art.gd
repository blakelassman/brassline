extends RefCounted
## Shared, original weapon silhouettes for world actors and first-person finishing.
const Geo = preload("res://scripts/geo.gd")
static func tube(parent: Node3D, at: Vector3, radius: float, length: float, color: Color) -> MeshInstance3D:
	var part = Geo.cylinder(parent,at,radius,length,color)
	part.rotation.x = PI/2
	return part
static func detail(parent: Node3D, weapon: int) -> void:
	var dark = Color("1b2b34")
	var metal = Color("758b90")
	var brass = Color("ba9659")
	if weapon==2:
		# Faceted blade with a pointed tip and a contrasting fuller.
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face in [[Vector3(-.04,0,-.6),Vector3(0,.022,-.65),Vector3(0,0,-.88)], [Vector3(0,.022,-.65),Vector3(.04,0,-.6),Vector3(0,0,-.88)]]:
			for v in face: st.add_vertex(v)
			for v in [face[2],face[1]-Vector3.UP*.025,face[0]]: st.add_vertex(v)
		st.generate_normals()
		st.index()
		var mesh = MeshInstance3D.new()
		mesh.mesh = st.commit()
		mesh.material_override = Geo.material(metal)
		parent.add_child(mesh)
		for z in [.26,.29,.32,.35,.38,.41]:
			tube(parent,Vector3(0,0,z),.038,.016,brass)
		Geo.sphere(parent,Vector3(0,0,.45),.044,brass)
		return
	# Sculpted shoulder stocks, trigger guards and a vented fore-end.
	if weapon in [0,3]:
		var stock = Geo.box(parent,Vector3(0,-.045,.43),Vector3(.12,.17,.38),dark)
		stock.rotation.x = -.12
		Geo.box(parent,Vector3(0,-.015,.56),Vector3(.15,.21,.045),dark,false,"rubber")
		Geo.box(parent,Vector3(0,.06,.38),Vector3(.14,.05,.24),metal)
		for side in [-1,1]:
			for i in range(6):
				Geo.box(parent,Vector3(side*.074,.025,-.19-i*.038),Vector3(.015,.045,.019),dark)
		for i in range(10): Geo.box(parent,Vector3(0,.10,-.29+i*.048),Vector3(.145,.022,.019),dark)
		# Rear aperture and front sight are real silhouettes.
		for side in [-1,1]: Geo.box(parent,Vector3(side*.025,.15,.15),Vector3(.012,.08,.028),metal)
		if weapon==3:
			tube(parent,Vector3(0,.17,-.27),.077,.07,dark)
			tube(parent,Vector3(0,.17,.065),.073,.025,dark)
			Geo.cylinder(parent,Vector3(0,.25,-.10),.025,.055,brass)
	else:
		Geo.box(parent,Vector3(0,-.12,.16),Vector3(.115,.16,.145),dark,false,"rubber")
		for side in [-1,1]:
			Geo.box(parent,Vector3(side*.052,.126,.15),Vector3(.025,.025,.045),metal)
			Geo.sphere(parent,Vector3(side*.065,-.1,.17),.014,brass)
	Geo.box(parent,Vector3(0,-.16,.06),Vector3(.07,.018,.15),dark)
	Geo.box(parent,Vector3(0,-.105,-.01),Vector3(.07,.12,.018),dark)
	Geo.box(parent,Vector3(0,-.09,.055),Vector3(.018,.06,.018),brass)

static func world(parent: Node3D, weapon: int) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var metal = Color("768a8c")
	var dark = Color("253940")
	if weapon==2:
		Geo.box(root,Vector3(0,0,-.22),Vector3(.06,.025,.80),metal)
		Geo.box(root,Vector3(0,0,.22),Vector3(.28,.06,.045),Color("ba9659"))
	elif weapon==1:
		Geo.box(root,Vector3(0,.045,.03),Vector3(.125,.13,.41),metal)
	else:
		Geo.box(root,Vector3.ZERO,Vector3(.14,.16,.58),metal)
		tube(root,Vector3(0,.025,-.5 if weapon==0 else -.64),.035,.5 if weapon==0 else .76,dark)
		Geo.box(root,Vector3(0,-.19,-.1),Vector3(.09,.22,.14),dark)
		if weapon==3: tube(root,Vector3(0,.17,-.1),.063,.33,dark)
	if weapon!=2: Geo.box(root,Vector3(0,-.13,.15),Vector3(.10,.23,.12),dark)
	detail(root,weapon)
	Geo.finish_weapon(root)
	preload("res://scripts/optimizer.gd").batch(root)
	return root
