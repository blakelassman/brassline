extends Node
const Loadouts = preload("res://scripts/loadouts.gd")
var menu: Node
var progress: Label
var xp_bar: ProgressBar
var buttons: Dictionary = {}
func build(owner_menu: Node) -> void:
 menu=owner_menu
 var page=menu.pages.LOADOUTS
 menu.label(page,"CLASSES & ARMORY",28,menu.ink)
 progress=menu.label(page,"",15,menu.gold)
 xp_bar=ProgressBar.new(); xp_bar.show_percentage=false; xp_bar.custom_minimum_size.y=8; page.add_child(xp_bar)
 menu.label(page,"Each class changes your primary. Pistol, sword, sniper and grenades stay available.",14,menu.muted).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 var scroll=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; page.add_child(scroll)
 var grid=GridContainer.new(); grid.columns=2; grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(grid)
 grid.add_theme_constant_override("h_separation",12); grid.add_theme_constant_override("v_separation",12)
 for id in Loadouts.IDS:
  var spec=Loadouts.CLASSES[id]; var w=spec.weapon
  var card=PanelContainer.new(); card.size_flags_horizontal=Control.SIZE_EXPAND_FILL; card.add_theme_stylebox_override("panel",menu.style(Color("1d3942"),14)); grid.add_child(card)
  var col=VBoxContainer.new(); col.add_theme_constant_override("separation",8); card.add_child(col)
  menu.label(col,spec.title+"  /  LV "+str(spec.level),18,menu.gold)
  menu.label(col,w.name,20,menu.ink)
  menu.label(col,spec.role,13,menu.muted)
  var desc=menu.label(col,spec.detail,13,menu.ink); desc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; desc.custom_minimum_size=Vector2(240,44)
  menu.label(col,"%d damage  /  %d head\n%d rounds  /  %.2fs reload" % [w.body,w.head,w.mag,w.reload],13,menu.muted)
  buttons[id]=menu.button(col,"",func(): choose(id))
 menu.label(page,"Applies next life or next round. Training lets you try any class immediately.",13,menu.muted).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 refresh()
func choose(id: String) -> void:
 var game=menu.game
 var training=game.mode=="training" and not game.net.running
 if not training and Loadouts.allowed(id,game.progression.xp_for("YOU"))!=id: return
 if training:
  game.player.set_class(id); game.player.refill(); game.player.viewmodel.update_pose(0)
  game.notify("TRAINING LOADOUT",Loadouts.CLASSES[id].weapon.name)
  game.set_active(true)
 # Trials never persist a locked online loadout.
 if Loadouts.allowed(id,game.progression.xp_for("YOU"))==id:
  game.prefs.data.selected_class=id; game.save_profile(); game.net.select_class(id)
 refresh()
func refresh() -> void:
 if menu==null: return
 var game=menu.game
 var level=game.progression.level_for("YOU"); var xp=game.progression.xp_for("YOU")
 var next="All classes unlocked. Keep climbing to level 1000."
 for id in Loadouts.IDS:
  var spec=Loadouts.CLASSES[id]
  if level<spec.level:
   next="Next: %s at level %d  /  %d XP to unlock" % [spec.title,spec.level,Loadouts.Progress.threshold(spec.level)-xp]
   break
 progress.text="%s  /  LEVEL %d  /  %d XP\n%s" % [Loadouts.rank_title(level),level,xp,next]
 var floor_xp=Loadouts.Progress.threshold(level)
 var goal=Loadouts.Progress.threshold(mini(1000,level+1))
 xp_bar.value=100 if level==1000 else 100.0*(xp-floor_xp)/maxi(1,goal-floor_xp)
 for id in buttons:
  var unlocked=Loadouts.allowed(id,xp)==id
  var trial=game.mode=="training" and not game.net.running
  buttons[id].disabled=not unlocked and not trial
  buttons[id].text=("SELECTED" if game.prefs.data.selected_class==id else "EQUIP NEXT LIFE") if unlocked else ("TRY IN TRAINING" if trial else "UNLOCK AT LEVEL %d" % Loadouts.CLASSES[id].level)
func _process(_delta: float) -> void:
 if menu!=null and menu.pages.LOADOUTS.visible: refresh()
