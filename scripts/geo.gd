extends RefCounted

static var textures: Dictionary = {}
static var bevel_meshes: Dictionary = {}
static var normals: Dictionary = {}
static var materials: Dictionary = {}

static func surface_texture(kind: String) -> Texture2D:
	if textures.has(kind): return textures[kind]
	var side = 256
	var img = Image.create(side,side,false,Image.FORMAT_RGB8)
	var normal = Image.create(side,side,false,Image.FORMAT_RGB8)
	var heights = PackedFloat32Array()
	heights.resize(side*side)
	var noise = FastNoiseLite.new()
	noise.seed = 2026
	noise.frequency = .095
	for y in range(side):
		for x in range(side):
			var grain = noise.get_noise_2d(x,y)
			var broad = noise.get_noise_2d(x*.14,y*.14)
			var v = .78+grain*.13+broad*.12
			if kind=="gun":
				v = .87+grain*.025+sin(y*2.2)*.012
			elif kind=="metal":
				var dx = absf(fmod(x+y,48)-24)
				var dy = absf(fmod(x-y+512,48)-24)
				v = .68+grain*.04+(.19 if (dx<3 and dy<15) or (dy<3 and dx<15) else 0)
			elif kind=="panel":
				v = .78+grain*.035+sin(x*TAU/32)*.055
				if x%64<3 or y%128<3: v = .38
				if (x%64-7)*(x%64-7)+(y%128-7)*(y%128-7)<5: v = .22
			elif kind=="brick":
				var row = y/32
				var xx = (x+(row%2)*32)%64
				v = .76+grain*.12+broad*.10
				if y%32<3 or xx<3: v = .42
			elif kind=="tile":
				v = .85+grain*.035
				if x%64<3 or y%64<3: v = .36
			elif kind=="wood":
				v = .73+sin(x*.7+noise.get_noise_2d(x*.2,y*.8)*4)*.09+grain*.07
				if x%64<3: v = .35
			elif kind=="rubber":
				v = .7+grain*.09+(.13 if (x+y)%12<3 else 0)
			heights[y*side+x] = v
			img.set_pixel(x,y,Color(v,v,v))
	for y in range(side):
		for x in range(side):
			var dx = heights[y*side+(x+1)%side]-heights[y*side+(x+side-1)%side]
			var dy = heights[((y+1)%side)*side+x]-heights[((y+side-1)%side)*side+x]
			var n = Vector3(-dx*1.6,-dy*1.6,1).normalized()
			normal.set_pixel(x,y,Color(n.x*.5+.5,n.y*.5+.5,n.z*.5+.5))
	img.generate_mipmaps()
	normal.generate_mipmaps()
	textures[kind] = ImageTexture.create_from_image(img)
	normals[kind] = ImageTexture.create_from_image(normal)
	return textures[kind]

static func textured(color: Color, kind: String, world: bool = true) -> StandardMaterial3D:
	var key = color.to_html()+kind+str(world)
	if materials.has(key): return materials[key]
	var mat = material(color)
	mat.albedo_texture = surface_texture(kind)
	mat.normal_enabled = true
	mat.normal_texture = normals[kind]
	mat.normal_scale = .12 if kind=="gun" else .4
	mat.roughness = .48 if kind in ["metal","panel","gun"] else .88
	mat.metallic = .35 if kind in ["metal","panel","gun"] else 0
	mat.uv1_triplanar = world
	mat.uv1_world_triplanar = world
	mat.uv1_scale = Vector3.ONE*.5 if world else Vector3.ONE*2
	materials[key] = mat
	return mat

static func finish_weapon(node: Node) -> void:
	if node is MeshInstance3D:
		var old = node.material_override as StandardMaterial3D
		node.material_override = textured(old.albedo_color,"gun",false).duplicate()
		if node.mesh is BoxMesh:
			var size = node.mesh.size
			if minf(size.x,minf(size.y,size.z))>.025: node.mesh = beveled_box(size)
	for child in node.get_children(): finish_weapon(child)

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = false, kind: String = "") -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mesh = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	if solid or not kind.is_empty():
		mesh.material_override = textured(color,kind if not kind.is_empty() else "concrete")
		root.set_meta("surface",kind if not kind.is_empty() else "concrete")
	root.add_child(mesh)
	if solid:
		var collision = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		root.add_child(collision)
	return root

static func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 16
	shape.rings = 8
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh

static func sign_text(parent: Node3D, pos: Vector3, text: String, size: int = 48, color: Color = Color.WHITE) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.009
	label.modulate = color
	label.outline_size = 0
	parent.add_child(label)
	label.position = pos
	return label

static func beam(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> Node3D:
	var item = box(parent,(a+b)*.5,Vector3(width,width,a.distance_to(b)),color)
	item.look_at(parent.to_global(b),Vector3.FORWARD if absf((b-a).normalized().y)>.99 else Vector3.UP)
	return item

static func crate(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var root = box(parent,pos,size,color,true,"wood")
	for x in [-1,1]:
		for z in [-1,1]:
			box(root,Vector3(x*(size.x*.5-.06),0,z*(size.z*.5+.01)),Vector3(.13,size.y,.06),Color("3f484b"),false,"metal")
	for y in [-1,1]:
		box(root,Vector3(0,y*(size.y*.5-.08),size.z*.5+.02),Vector3(size.x,.14,.08),Color("bbaa84"))
	return root

static func polygon(st: SurfaceTool, vertices: Array, normal: Vector3) -> void:
	if (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).dot(normal)>0: vertices.reverse()
	for i in range(1,vertices.size()-1):
		for v in [vertices[0],vertices[i],vertices[i+1]]:
			st.set_normal(normal)
			st.set_uv(Vector2(v.x+v.z,v.y+v.z)*4)
			st.add_vertex(v)

static func beveled_box(size: Vector3) -> ArrayMesh:
	if bevel_meshes.has(size): return bevel_meshes[size]
	var h = size*.5
	var b = minf(.018,minf(h.x,minf(h.y,h.z))*.24)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in range(3):
		var u = (axis+1)%3
		var v = (axis+2)%3
		for side in [-1,1]:
			var points: Array = []
			for pair in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,1),Vector2(1,-1)]:
				var point = Vector3.ZERO
				point[axis] = h[axis]*side
				point[u] = (h[u]-b)*pair.x
				point[v] = (h[v]-b)*pair.y
				points.append(point)
			var normal = Vector3.ZERO
			normal[axis] = side
			polygon(st,points,normal)
	for axis in range(3):
		var u = (axis+1)%3
		var v = (axis+2)%3
		for su in [-1,1]:
			for sv in [-1,1]:
				var points: Array = []
				for ends in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
					var point = Vector3.ZERO
					point[axis] = (h[axis]-b)*ends.x
					point[u] = (h[u]-(b if ends.y==1 else 0))*su
					point[v] = (h[v]-(b if ends.y==0 else 0))*sv
					points.append(point)
				var normal = Vector3.ZERO
				normal[u] = su
				normal[v] = sv
				polygon(st,points,normal.normalized())
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]:
				var sign = Vector3(x,y,z)
				var points: Array = []
				for axis in range(3):
					var point = (h-Vector3.ONE*b)*sign
					point[axis] = h[axis]*sign[axis]
					points.append(point)
				polygon(st,points,sign.normalized())
	st.index()
	var mesh = st.commit()
	bevel_meshes[size] = mesh
	return mesh
