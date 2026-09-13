extends RefCounted
## Original silhouettes, drawn without fonts or external game artwork.
static func draw_icon(canvas: CanvasItem, at: Vector2, weapon: String, color: Color) -> void:
	if weapon=="HEADSHOT":
		canvas.draw_circle(at+Vector2(26,8),6,color)
		canvas.draw_rect(Rect2(at+Vector2(23,11),Vector2(6,6)),color)
		for x in [23,29]: canvas.draw_circle(at+Vector2(x,7),1.5,Color("192f37"))
		canvas.draw_line(at+Vector2(16,8),at+Vector2(36,8),color,1)
	elif weapon=="SWORD":
		canvas.draw_line(at+Vector2(12,19),at+Vector2(40,3),color,3)
		canvas.draw_line(at+Vector2(18,9),at+Vector2(24,19),color,2)
	elif weapon=="BLAST":
		canvas.draw_circle(at+Vector2(26,12),6,color)
		canvas.draw_rect(Rect2(at+Vector2(23,3),Vector2(6,4)),color)
	else:
		var length = 48 if weapon=="LONGSHOT" else (25 if weapon=="HEAVY PISTOL" else 40)
		canvas.draw_rect(Rect2(at+Vector2(5,8),Vector2(length,5)),color)
		canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(9,12),at+Vector2(18,12),at+Vector2(15,21),at+Vector2(7,21)]),color)
		if weapon=="LONGSHOT":
			canvas.draw_rect(Rect2(at+Vector2(18,2),Vector2(17,4)),color)
		elif weapon=="RIFLE":
			canvas.draw_rect(Rect2(at+Vector2(25,12),Vector2(6,8)),color)
