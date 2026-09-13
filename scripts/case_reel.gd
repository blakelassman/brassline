extends Control
const Collection = preload("res://scripts/cosmetics.gd")
const Icons = preload("res://scripts/feed_icons.gd")
var cards: Array = []
var progress = 1.0
var font: Font
func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 136
	font = ThemeDB.fallback_font
func _draw() -> void:
	if font==null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b1c25"))
	if cards.is_empty():
		draw_string(font,Vector2(20,60),"THE DISTRICT COLLECTION",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("f1bd58"))
		draw_string(font,Vector2(20,89),"50 finishes. Five rarity tiers. Yours to collect.",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("acc0c5"))
		return
	var travel = 24.0*(1-pow(1-clampf(progress,0,1),4))
	for i in range(cards.size()):
		var item = cards[i]
		var x = size.x*.5+(i-travel)*158-74
		if x>size.x or x+148<0: continue
		var color = Collection.COLORS[item.rarity]
		draw_rect(Rect2(x,8,148,120),Color(item.base).darkened(.45))
		draw_rect(Rect2(x,124,148,4),color)
		if item.slot=="armor":
			draw_circle(Vector2(x+74,35),9,color)
			draw_colored_polygon(PackedVector2Array([Vector2(x+54,49),Vector2(x+94,49),Vector2(x+87,73),Vector2(x+61,73)]),color)
		else:
			Icons.draw_icon(self,Vector2(x+46,40),{"rifle":"RIFLE","pistol":"HEAVY PISTOL","sword":"SWORD","sniper":"LONGSHOT"}[item.slot],color)
		draw_string(font,Vector2(x+10,95),item.name,HORIZONTAL_ALIGNMENT_LEFT,134,15,Color("f4ecd7"))
		draw_string(font,Vector2(x+10,115),Collection.LABELS[item.slot].to_upper(),HORIZONTAL_ALIGNMENT_LEFT,134,11,color)
	draw_line(Vector2(size.x*.5,0),Vector2(size.x*.5,size.y),Color("f1bd58"),2)
	draw_colored_polygon(PackedVector2Array([Vector2(size.x*.5-7,0),Vector2(size.x*.5+7,0),Vector2(size.x*.5,10)]),Color("f1bd58"))
