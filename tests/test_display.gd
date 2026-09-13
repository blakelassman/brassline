extends Node
var checks = 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ",label)
	if not value: failures.append(label)
func settle() -> void:
	for i in range(5): await get_tree().process_frame
func run(game: Node) -> void:
	var window = game.get_window()
	game.prefs.data.fullscreen = false
	game.prefs.data.resolution_width = 1280
	game.prefs.data.resolution_height = 720
	game.apply_display_settings()
	await settle()
	check(window.mode==Window.MODE_WINDOWED and window.size==Vector2i(1280,720),"1280x720 window setting changes the actual Window size")
	game.prefs.data.resolution_width = 1024
	game.prefs.data.resolution_height = 768
	game.apply_display_settings()
	await settle()
	check(window.size==Vector2i(1024,768),"Custom window dimensions apply")
	check(window.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_KEEP and window.content_scale_size==Vector2i(1600,900),"Custom aspect ratios preserve the native 16:9 play area")
	game.prefs.data.fullscreen = true
	game.apply_display_settings()
	await settle()
	check(window.mode==Window.MODE_FULLSCREEN,"Borderless fullscreen applies through the Window API")
	var applied = game.applied_display
	for index in range(4):
		await game.start_mode("training",index)
		await settle()
		check(window.mode==Window.MODE_FULLSCREEN and game.applied_display==applied,"Match start preserves fullscreen without another display change")
	game.prefs.data.sensitivity = .003
	game.apply_settings()
	check(window.mode==Window.MODE_FULLSCREEN,"Changing mouse sensitivity does not reset display mode")
	game.prefs.data.fullscreen = false
	game.prefs.data.resolution_width = 1280
	game.prefs.data.resolution_height = 720
	game.apply_display_settings()
	await settle()
	check(window.mode==Window.MODE_WINDOWED and window.size==Vector2i(1280,720),"Leaving fullscreen restores the selected window resolution")
	print("DISPLAY_RESULT ",checks-failures.size(),"/",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
