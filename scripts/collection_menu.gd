extends Node
const Collection = preload("res://scripts/cosmetics.gd")
var menu: Node
var game: Node
var preview: Node
var list: VBoxContainer
var total: Label
var item_title: Label
var item_detail: Label
var equip_button: Button
var open_button: Button
var skip_button: Button
var outcome: Label
var reel: Control
var challenge_rows: Array = []
var challenge_total: Label
var challenges_filter: OptionButton
var slot_filter: OptionButton
var rarity_filter: OptionButton
var show_locked: CheckButton
var selected_id = "armor_standard"
var drop: Dictionary = {}
var spin_time = -1.0
var tick_index = -1
var seen_revision = -1
var seen_challenges = -1
func build(m: Node) -> void:
	menu = m
	game = m.game
	_build_locker(menu.pages.LOCKER)
	_build_challenges(menu.pages.CHALLENGES)
func scroll(parent: Node) -> VBoxContainer:
	var scroll_box = ScrollContainer.new()
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll_box)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",7)
	scroll_box.add_child(rows)
	return rows
func _build_locker(page: VBoxContainer) -> void:
	var heading = HBoxContainer.new()
	page.add_child(heading)
	menu.label(heading,"YOUR LOCKER",28).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total = menu.label(heading,"",14,menu.muted)
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",18)
	page.add_child(columns)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = .9
	columns.add_child(left)
	preview = preload("res://scripts/collection_preview.gd").new()
	left.add_child(preview)
	item_title = menu.label(left,"",24,menu.gold)
	item_detail = menu.label(left,"",13,menu.muted)
	equip_button = menu.button(left,"EQUIP",equip_selected)
	menu.label(left,"Outfits keep team colors. Cosmetics never alter stats.",12,menu.muted).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	columns.add_child(right)
	var filters = HBoxContainer.new()
	right.add_child(filters)
	slot_filter = OptionButton.new()
	slot_filter.add_item("All equipment")
	for slot in Collection.SLOTS: slot_filter.add_item(Collection.LABELS[slot])
	filters.add_child(slot_filter)
	rarity_filter = OptionButton.new()
	rarity_filter.add_item("All rarities")
	for rarity in Collection.RARITIES: rarity_filter.add_item(rarity.capitalize())
	filters.add_child(rarity_filter)
	for picker in [slot_filter,rarity_filter]:
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.item_selected.connect(func(_index): refresh_inventory())
	show_locked = CheckButton.new()
	show_locked.text = "Show unowned collection"
	show_locked.toggled.connect(func(_on): refresh_inventory())
	right.add_child(show_locked)
	list = scroll(right)
	reel = preload("res://scripts/case_reel.gd").new()
	page.add_child(reel)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	page.add_child(actions)
	open_button = menu.button(actions,"OPEN FREE CASE",open_case)
	skip_button = menu.button(actions,"SKIP REVEAL",finish_spin)
	skip_button.hide()
	outcome = menu.label(actions,"Free and unlimited. Every drop goes to your inventory.",14,menu.muted)
	outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.label(page,"Field 70%  ·  Signal 22%  ·  Elite 6%  ·  Mythic 1.75%  ·  Special 0.25% (1 in 400)",13,menu.gold)
	menu.label(page,"Each opening is independent. Duplicates stack. No purchases, keys or trading.",12,menu.muted)
	refresh_inventory()
	select_item(game.cosmetics.last_drop if not game.cosmetics.last_drop.is_empty() else game.cosmetics.equipped.armor)
func refresh_inventory() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var all = Collection.catalog().values()
	all.sort_custom(func(a,b): return a.rarity>b.rarity if a.rarity!=b.rarity else a.id<b.id)
	var count = 0
	for item in all:
		var owned = game.cosmetics.owned.has(item.id)
		if not owned and not show_locked.button_pressed: continue
		if slot_filter.selected>0 and item.slot!=Collection.SLOTS[slot_filter.selected-1]: continue
		if rarity_filter.selected>0 and item.rarity!=rarity_filter.selected-1: continue
		var suffix = "  /  EQUIPPED" if game.cosmetics.equipped[item.slot]==item.id else ("  ×%d" % game.cosmetics.owned[item.id] if owned else "  /  LOCKED")
		var row = menu.button(list,item.name+"  ·  "+Collection.LABELS[item.slot]+suffix,func(): select_item(item.id))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size",14)
		row.add_theme_color_override("font_color",Collection.COLORS[item.rarity])
		count += 1
	if count==0: menu.label(list,"No matching items yet. Try a free case.",14,menu.muted)
	total.text = "%d / %d STYLES  ·  %d OPENED" % [game.cosmetics.owned.size(),Collection.catalog().size(),game.cosmetics.opened]
	seen_revision = game.cosmetics.revision
func select_item(id: String) -> void:
	selected_id = id
	var item = Collection.catalog()[id]
	item_title.text = item.name.to_upper()
	item_title.add_theme_color_override("font_color",Collection.COLORS[item.rarity])
	item_detail.text = "%s  /  %s" % [Collection.LABELS[item.slot],Collection.RARITIES[item.rarity]]
	preview.show_item(id,game.cosmetics.equipped)
	equip_button.disabled = not game.cosmetics.owned.has(id) or game.cosmetics.equipped[item.slot]==id
	equip_button.text = "EQUIPPED" if game.cosmetics.equipped[item.slot]==id else ("EQUIP" if game.cosmetics.owned.has(id) else "FIND IN A FREE CASE")
func equip_selected() -> void:
	var before = game.cosmetics.save_data()
	if not game.cosmetics.equip_item(selected_id): return
	if not game.save_profile():
		game.cosmetics.load_data(before)
		outcome.text = "Could not save. Your previous equipment is still selected."
		return
	game.apply_cosmetics()
	refresh_inventory()
	select_item(selected_id)
func open_case() -> void:
	if spin_time>=0: return
	var before = game.cosmetics.save_data()
	drop = game.cosmetics.open_case()
	# Persist the actual result before its animation; closing cannot lose a reward.
	if not game.save_profile():
		game.cosmetics.load_data(before)
		drop = {}
		outcome.text = "Could not save this opening. Check the profile error below."
		return
	reel.cards.clear()
	# Decorative cards follow the same distribution; no manufactured rare near-misses.
	for i in range(28): reel.cards.append(game.cosmetics.roll_item())
	reel.cards[24] = drop.item
	reel.progress = 0
	spin_time = 0
	tick_index = -1
	open_button.disabled = true
	skip_button.show()
	outcome.text = "Opening the District Collection…"
	refresh_inventory()
func finish_spin() -> void:
	if spin_time<0: return
	spin_time = -1
	reel.progress = 1
	reel.queue_redraw()
	open_button.disabled = false
	open_button.text = "OPEN ANOTHER FREE CASE"
	skip_button.hide()
	var item = drop.item
	outcome.text = "%s · %s%s" % [item.name,Collection.LABELS[item.slot]," · Duplicate ×%d" % drop.count if drop.duplicate else " · NEW!"]
	outcome.add_theme_color_override("font_color",Collection.COLORS[item.rarity])
	select_item(item.id)
	game.sound("case_reveal",-12)
func _build_challenges(page: VBoxContainer) -> void:
	menu.label(page,"MAKE EVERY SHOT COUNT",28)
	challenge_total = menu.label(page,"",16,menu.gold)
	menu.label(page,"Permanent milestones across training, bot matches and online. Streaks reset on death or a new match.",14,menu.muted).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	challenges_filter = OptionButton.new()
	for title in ["All challenges","In progress","Completed"]: challenges_filter.add_item(title)
	challenges_filter.item_selected.connect(func(_index): refresh_challenges())
	page.add_child(challenges_filter)
	var rows = scroll(page)
	for item in game.challenges.catalog():
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel",menu.style(Color("1d3741"),12))
		rows.add_child(panel)
		var col = VBoxContainer.new()
		panel.add_child(col)
		var top = HBoxContainer.new()
		col.add_child(top)
		var title = menu.label(top,item.title,17)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status = menu.label(top,"",14,menu.gold)
		menu.label(col,item.description,13,menu.muted).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var bar = ProgressBar.new()
		bar.custom_minimum_size.y = 5
		bar.show_percentage = false
		bar.max_value = item.goal
		var fill = StyleBoxFlat.new()
		fill.bg_color = menu.gold
		bar.add_theme_stylebox_override("fill",fill)
		col.add_child(bar)
		challenge_rows.append({"item":item,"panel":panel,"status":status,"bar":bar})
	refresh_challenges()
func refresh_challenges() -> void:
	challenge_total.text = "%d / %d COMPLETED" % [game.challenges.unlocked.size(),challenge_rows.size()]
	for row in challenge_rows:
		var done = game.challenges.unlocked.has(row.item.id)
		var value = mini(row.item.goal,int(game.challenges.stats.get(row.item.stat,0)))
		row.status.text = "COMPLETE" if done else "%d / %d" % [value,row.item.goal]
		row.bar.value = value
		row.panel.visible = challenges_filter.selected==0 or (done and challenges_filter.selected==2) or (not done and challenges_filter.selected==1)
	seen_challenges = game.challenges.revision
func _process(delta: float) -> void:
	if game==null: return
	if spin_time>=0:
		spin_time += delta
		reel.progress = minf(1,spin_time/3.2)
		reel.queue_redraw()
		var index = int(24*(1-pow(1-reel.progress,4)))
		if index!=tick_index:
			tick_index = index
			if menu.visible: game.sound("case_tick",-23)
		if spin_time>=3.2: finish_spin()
	if menu.visible:
		if seen_revision!=game.cosmetics.revision: refresh_inventory()
		if seen_challenges!=game.challenges.revision: refresh_challenges()
