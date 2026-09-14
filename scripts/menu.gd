extends PanelContainer
const Preferences = preload("res://scripts/preferences.gd")
var collection_menu: Node
var game: Node
var resume_button: Button
var pages: Dictionary = {}
var nav_buttons: Dictionary = {}
var level_label: Label
var status_label: Label
var bind_status: Label
var bindings: Dictionary = {}
var waiting = ""
var waiting_slot = 0
var nickname: LineEdit
var address: LineEdit
var secret: LineEdit
var port: SpinBox
var host_button: Button
var join_button: Button
var leave_button: Button
var gold = Color("f1bd58")
var ink = Color("f4ecd7")
var muted = Color("acc0c5")
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel",style(Color(.035,.075,.095,.96),0))
	var margin = MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	add_child(margin)
	var shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation",20)
	margin.add_child(shell)
	var top = HBoxContainer.new()
	shell.add_child(top)
	label(top,"BRASSLINE",46,ink).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(top,"MULTIPLAYER  /  0.9.0",15,gold)
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation",32)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	var nav = VBoxContainer.new()
	nav.custom_minimum_size.x = 255
	nav.add_theme_constant_override("separation",10)
	columns.add_child(nav)
	label(nav,"YOUR PROFILE",12,muted)
	level_label = label(nav,"LEVEL 1",24,gold)
	label(nav,"Progress saves automatically.",13,muted)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 20
	nav.add_child(spacer)
	for page in ["PLAY","ONLINE","LOCKER","CHALLENGES","SETTINGS","CONTROLS"]:
		nav_buttons[page] = button(nav,page,func(): show_page(page))
	resume_button = button(nav,"RESUME",func(): game.set_active(true))
	resume_button.hide()
	leave_button = button(nav,"LEAVE SERVER",func(): await game.net.leave())
	leave_button.hide()
	spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	button(nav,"QUIT GAME",func(): game.quit_game())
	var content = PanelContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_stylebox_override("panel",style(Color("142b34"),24))
	columns.add_child(content)
	for name in ["PLAY","ONLINE","LOCKER","CHALLENGES","SETTINGS","CONTROLS"]:
		var page = VBoxContainer.new()
		page.add_theme_constant_override("separation",14)
		content.add_child(page)
		pages[name] = page
	_build_play(pages.PLAY)
	_build_online(pages.ONLINE)
	_build_settings(pages.SETTINGS)
	_build_controls(pages.CONTROLS)
	collection_menu = preload("res://scripts/collection_menu.gd").new()
	add_child(collection_menu)
	collection_menu.build(self)
	status_label = label(shell,"",14,muted)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 40
	show_page("PLAY")
func style(color: Color, padding: int) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = color
	result.set_content_margin_all(padding)
	return result
func label(parent: Node, text: String, size: int = 16, color: Color = ink) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_color",color)
	parent.add_child(result)
	return result
func button(parent: Node, text: String, callback: Callable) -> Button:
	var result = Button.new()
	result.text = text
	result.custom_minimum_size.y = 44
	result.add_theme_font_size_override("font_size",17)
	result.add_theme_color_override("font_color",ink)
	result.add_theme_stylebox_override("normal",style(Color("25424a"),10))
	result.add_theme_stylebox_override("hover",style(Color("3b5c61"),10))
	result.add_theme_stylebox_override("pressed",style(Color("735b31"),10))
	result.pressed.connect(func(): game.menu_sound(); callback.call())
	parent.add_child(result)
	return result
func field(parent: Node, title: String, value: String, placeholder: String = "") -> LineEdit:
	label(parent,title,13,muted)
	var result = LineEdit.new()
	result.text = value
	result.placeholder_text = placeholder
	result.custom_minimum_size.y = 42
	parent.add_child(result)
	return result
func show_page(name: String) -> void:
	waiting = ""
	for key in pages: pages[key].visible = key==name
	for key in nav_buttons:
		nav_buttons[key].add_theme_stylebox_override("normal",style(gold if key==name else Color("25424a"),10))
		nav_buttons[key].add_theme_color_override("font_color",Color("142b34") if key==name else ink)
func _build_play(page: VBoxContainer) -> void:
	label(page,"PICK YOUR ARENA",28,ink)
	label(page,"Movement. Precision. One more round.",16,muted)
	var picker = OptionButton.new()
	for name in game.Maps.NAMES: picker.add_item(name)
	picker.custom_minimum_size.y = 48
	picker.add_theme_font_size_override("font_size",20)
	page.add_child(picker)
	var description = label(page,game.Maps.DESCRIPTIONS[0],16,muted)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 56
	picker.item_selected.connect(func(index): game.selected_map = index; description.text = game.Maps.DESCRIPTIONS[index])
	button(page,"01   AIM TRAINING",func(): await game.start_mode("training"))
	label(page,"Practice shots, boost jumps and movement at your own pace.",14,muted)
	button(page,"02   ENDLESS 5v5 BOTS",func(): await game.start_mode("combat"))
	label(page,"You + four allies versus five bots. No time or score limit.",14,muted)
	button(page,"03   ONLINE TEAM DEATHMATCH",func(): show_page("ONLINE"))
	label(page,"First team to 250 kills. Ten minutes max. Vote for the next map.",14,gold)
func _build_online(page: VBoxContainer) -> void:
	label(page,"PLAY WITH FRIENDS",28,ink)
	label(page,"Humans split evenly across teams. Bots keep every match 5v5.",15,muted)
	nickname = field(page,"PLAYER NAME",game.prefs.data.name)
	nickname.max_length = 18
	nickname.text_changed.connect(func(value): game.prefs.data.name = Preferences.clean_name(value); game.prefs.dirty = true)
	address = field(page,"HOST ADDRESS  /  JOINING ONLY",game.prefs.data.last_address,"Public IP or hostname")
	address.max_length = 253
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",20)
	page.add_child(row)
	var port_col = VBoxContainer.new()
	row.add_child(port_col)
	label(port_col,"UDP PORT",13,muted)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = game.prefs.data.port
	port.custom_minimum_size = Vector2(150,42)
	port_col.add_child(port)
	var secret_col = VBoxContainer.new()
	secret_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(secret_col)
	secret = field(secret_col,"PASSWORD  /  OPTIONAL","","Leave blank for no password")
	secret.secret = true
	secret.max_length = 64
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	page.add_child(row)
	host_button = button(row,"HOST & PLAY",func():
		_save_connection()
		await game.net.host(int(port.value),secret.text))
	join_button = button(row,"JOIN SERVER",func():
		_save_connection()
		game.net.join(address.text,int(port.value),secret.text))
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var help = label(page,"HOST: select a map on Play, then host here. Forward this UDP port to your PC and allow the game through Windows Firewall. Friends use your public IP.\n\nSame PC: 127.0.0.1. Same home: host's local IPv4. See HOSTING.txt for the short setup guide.",14,muted)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
func _save_connection() -> void:
	game.prefs.data.last_address = address.text.strip_edges()
	game.prefs.data.port = int(port.value)
	game.save_profile()
func _build_settings(page: VBoxContainer) -> void:
	label(page,"SETTINGS",28,ink)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",12)
	scroll.add_child(rows)
	_slider(rows,"Mouse sensitivity","sensitivity",.0003,.012,.0001)
	label(rows,"Scope sensitivity automatically follows your field of view.",14,muted)
	label(rows,"AUDIO",13,muted)
	_slider(rows,"Master volume","volume",0,1,.01)
	_slider(rows,"Gunfire & explosions","weapons_volume",0,1,.01)
	_slider(rows,"Footsteps & equipment","effects_volume",0,1,.01)
	_slider(rows,"Hit confirmations & rewards","feedback_volume",0,1,.01)
	_slider(rows,"Background air & drone","ambience_volume",0,1,.01)
	label(rows,"The background stays faint. Set it to zero for a silent backdrop.",14,muted)
	label(rows,"GRAPHICS",13,muted)
	var quality = OptionButton.new()
	for name in ["LOW","BALANCED","HIGH / shadows + anti-aliasing"]: quality.add_item(name)
	quality.selected = game.prefs.data.quality
	quality.custom_minimum_size.y = 42
	quality.item_selected.connect(func(index): game.prefs.data.quality = index; _settings_changed())
	rows.add_child(quality)
	_slider(rows,"Frame rate cap","fps_limit",30,240,1)
	var fullscreen = CheckButton.new()
	fullscreen.text = "Fullscreen (borderless)"
	fullscreen.button_pressed = game.prefs.data.fullscreen
	rows.add_child(fullscreen)
	var presets = OptionButton.new()
	for name in ["1280 × 720","1600 × 900","1920 × 1080","2560 × 1440","3840 × 2160","Custom"]: presets.add_item(name)
	rows.add_child(presets)
	var dimensions = HBoxContainer.new()
	rows.add_child(dimensions)
	var width = SpinBox.new()
	var height = SpinBox.new()
	width.min_value = 960
	width.max_value = 7680
	height.min_value = 540
	height.max_value = 4320
	width.value = game.prefs.data.resolution_width
	height.value = game.prefs.data.resolution_height
	for item in [width,height]:
		item.custom_minimum_size = Vector2(165,38)
		dimensions.add_child(item)
	var sizes = [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]
	var selected = sizes.find(Vector2i(width.value,height.value))
	presets.selected = selected if selected>=0 else 5
	presets.item_selected.connect(func(index):
		if index<5:
			width.value = sizes[index].x
			height.value = sizes[index].y)
	var sync_preset = func(_value):
		var found = sizes.find(Vector2i(width.value,height.value))
		presets.selected = found if found>=0 else 5
	width.value_changed.connect(sync_preset)
	height.value_changed.connect(sync_preset)
	button(rows,"APPLY DISPLAY",func():
		game.prefs.data.fullscreen = fullscreen.button_pressed
		game.prefs.data.resolution_width = int(width.value)
		game.prefs.data.resolution_height = int(height.value)
		game.apply_display_settings()
		game.save_profile())
	var hint = label(rows,"16:9 play area. Other shapes use black bars. Fullscreen uses your desktop size with the selected render resolution; oversized windows fit your screen.",14,muted)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
func _slider(page: Node, title: String, key: String, low: float, high: float, step: float) -> void:
	var caption = label(page,title+"  "+str(game.prefs.data[key]),16,ink)
	var slider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = game.prefs.data[key]
	slider.custom_minimum_size.y = 24
	page.add_child(slider)
	slider.value_changed.connect(func(value):
		game.prefs.data[key] = value
		caption.text = title+"  "+str(snappedf(value,.0001))
		_settings_changed())
func _settings_changed() -> void:
	game.apply_settings()
	game.prefs.dirty = true
func _build_controls(page: VBoxContainer) -> void:
	label(page,"YOUR KEYS. YOUR MOVEMENT.",28,ink)
	label(page,"Click a binding, then press a key, mouse button or scroll wheel.",15,muted)
	bind_status = label(page,"Two bindings per action. Conflicting keys are reassigned.",14,gold)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",6)
	scroll.add_child(rows)
	for action in Preferences.DEFAULT_KEYS:
		var row = HBoxContainer.new()
		rows.add_child(row)
		label(row,Preferences.LABELS[action],15,ink).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bindings[action] = []
		for slot in range(2):
			var key_button = button(row,"",func():
				waiting = action
				waiting_slot = slot
				bind_status.text = "Press a key for "+Preferences.LABELS[action]+"…")
			key_button.custom_minimum_size = Vector2(145,34)
			bindings[action].append(key_button)
	var footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation",14)
	page.add_child(footer)
	button(footer,"CANCEL BINDING",func(): waiting = ""; bind_status.text = "Binding cancelled.")
	button(footer,"RESTORE DEFAULTS",func():
		waiting = ""
		game.prefs.data.bindings = Preferences.DEFAULT_KEYS.duplicate(true)
		game.prefs.apply_bindings()
		game.save_profile()
		_refresh_bindings())
	_refresh_bindings()
func _refresh_bindings() -> void:
	for action in bindings:
		for slot in range(2):
			var codes = game.prefs.data.bindings[action]
			bindings[action][slot].text = Preferences.key_label(codes[slot] if codes.size()>slot else 0)
func _input(event: InputEvent) -> void:
	if not visible or waiting.is_empty(): return
	var code = 0
	if event is InputEventKey and event.pressed and not event.echo: code = event.physical_keycode if event.physical_keycode!=0 else event.keycode
	elif event is InputEventMouseButton and event.pressed: code = -event.button_index
	if code==0: return
	# A click on the visible cancel control should cancel, rather than bind Mouse 1.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var hovered = get_viewport().gui_get_hovered_control()
		if hovered is Button and hovered.text=="CANCEL BINDING": return
	bind_status.text = game.prefs.bind(waiting,waiting_slot,code)
	waiting = ""
	_refresh_bindings()
	get_viewport().set_input_as_handled()
func _process(_delta: float) -> void:
	if not visible: return
	level_label.text = "LEVEL %d  /  1000" % game.progression.level_for("YOU")
	status_label.text = game.prefs.error if not game.prefs.error.is_empty() else game.net.status
	host_button.disabled = game.net.running or game.changing_map
	join_button.disabled = host_button.disabled
	leave_button.visible = game.net.running
	resume_button.visible = game.has_started and (not game.net.running or game.net.session_ready)
