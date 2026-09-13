extends RefCounted
## Merge static draw geometry while leaving all physics shapes and animated joints intact.
static var vertex_material: StandardMaterial3D
static func collect(node: Node3D, root: Node3D, excluded: Array, meshes: Array) -> void:
	for child in node.get_children():
		if child in excluded: continue
		if child is MeshInstance3D and child.mesh!=null and child.material_override is Material:
			var mat = child.material_override
			if mat is ShaderMaterial or (mat is StandardMaterial3D and mat.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and not mat.emission_enabled):
				meshes.append(child)
		elif child is Node3D: collect(child,root,excluded,meshes)
static func batch(root: Node3D, excluded: Array = [], vertex_colors: bool = false) -> int:
	if "--no-batching" in OS.get_cmdline_user_args(): return 0
	var meshes: Array = []
	collect(root,root,excluded,meshes)
	var groups: Dictionary = {}
	for instance in meshes:
		var mat = instance.material_override
		var key = str(mat.get_instance_id()) if mat is ShaderMaterial else ("color" if vertex_colors else str([mat.albedo_color,mat.roughness,mat.metallic,mat.albedo_texture,mat.normal_texture,mat.uv1_scale,mat.uv1_triplanar,mat.normal_scale]))
		if not groups.has(key): groups[key] = []
		groups[key].append(instance)
	var removed = 0
	for group in groups.values():
		if group.size()<2: continue
		var use_colors = vertex_colors and group[0].material_override is StandardMaterial3D
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for instance in group:
			var transform = root.global_transform.affine_inverse()*instance.global_transform
			if use_colors:
				var arrays = instance.mesh.surface_get_arrays(0)
				var vertices = arrays[Mesh.ARRAY_VERTEX]
				var normals = arrays[Mesh.ARRAY_NORMAL]
				var indices = arrays[Mesh.ARRAY_INDEX]
				if indices==null or indices.is_empty(): indices = range(vertices.size())
				var normal_basis = transform.basis.inverse().transposed()
				for i in indices:
					st.set_color(instance.material_override.albedo_color)
					st.set_normal((normal_basis*normals[i]).normalized())
					st.add_vertex(transform*vertices[i])
			else: st.append_from(instance.mesh,0,transform)
		var merged = MeshInstance3D.new()
		merged.mesh = st.commit()
		if use_colors:
			if vertex_material==null:
				vertex_material = StandardMaterial3D.new()
				vertex_material.vertex_color_use_as_albedo = true
				vertex_material.roughness = .85
			merged.material_override = vertex_material
		else: merged.material_override = group[0].material_override
		root.add_child(merged)
		for instance in group:
			instance.hide()
			instance.queue_free()
		removed += group.size()-1
	return removed
static func rig(data: Dictionary) -> void:
	var joints: Array = [data.root,data.torso,data.head]
	joints.append_array(data.legs)
	joints.append_array(data.knees)
	joints.append_array(data.arms)
	joints.append_array(data.elbows)
	for joint in joints: batch(joint,joints,true)
