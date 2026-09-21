extends Node
const Loadouts=preload("res://scripts/loadouts.gd")
var game: Node
var checks=0
var failures=[]
var root=""
var join_port=27917
func check(ok: bool, title: String) -> void:
 checks+=1; print("PASS " if ok else "FAIL ",title)
 if not ok: failures.append(title)
func mark(key: String) -> void:
 var f=FileAccess.open(root+key,FileAccess.WRITE); f.store_string("1")
func marked(key: String) -> bool: return FileAccess.file_exists(root+key)
func wait_for(condition: Callable, seconds: float=12) -> bool:
 var until=Time.get_ticks_msec()+int(seconds*1000)
 while not condition.call() and Time.get_ticks_msec()<until: await get_tree().physics_frame
 return condition.call()
func freeze() -> void:
 for actor in game.net.actors() if game.net.running else game.combat.actors(): actor.set_physics_process(false)
func run(g: Node) -> void:
 game=g
 var args=OS.get_cmdline_user_args()
 for arg in args:
  if arg.begins_with("--coord="): root=arg.trim_prefix("--coord=")+"/"
  if arg.begins_with("--join-port="): join_port=arg.trim_prefix("--join-port=").to_int()
 await get_tree().physics_frame
 if "--role=host" in args: await host_test()
 elif "--role=client" in args: await client_test()
 else: await unit_test()
 print("ARMORY_RESULT ",checks-failures.size(),"/",checks)
 if game.net.running: await game.net.leave()
 get_tree().quit(0 if failures.is_empty() else 1)
func unit_test() -> void:
 await game.start_mode("training")
 var p=game.player; p.set_physics_process(false); p.set_process(false)
 for id in Loadouts.IDS:
  var spec=Loadouts.CLASSES[id]
  var threshold=Loadouts.Progress.threshold(spec.level)
  check(Loadouts.allowed(id,threshold)==id,"Unlock available at its level: "+id)
  if threshold>0: check(Loadouts.allowed(id,threshold-1)=="vanguard","Locked class rejected below level: "+id)
  p.set_class(id); p.weapon=0; p.refill(); p.fire_cooldown=0; p.equip_cooldown=0; p.fire_blocked_until_release=false
  p.shoot()
  check(p.ammo[0]==spec.weapon.mag-1 and is_equal_approx(p.fire_cooldown,spec.weapon.cooldown),"Live shot uses class magazine and recovery: "+id)
  p.start_reload(); p.advance_weapon_state(spec.weapon.reload+.01)
  check(p.ammo[0]==spec.weapon.mag and p.reload_timer==0,"Reload fills the correct class magazine: "+id)
  check(p.viewmodel.models[0].has_node("ClassParts"),"Class weapon silhouette is present: "+id)
  var target=game.targets[0]; target.set_physics_process(false); target.reset(); target.team=2
  p.position=Vector3(0,10,0); target.position=Vector3(0,10,-5)
  await get_tree().physics_frame
  var direction=(target.global_position+Vector3.UP*.8-p.camera.global_position).normalized()
  game.shoot_ray(p.camera.global_position,direction,0,false,p)
  check(target.health==100-spec.weapon.body,"Actual body hit uses the class damage: "+id)
 check(Loadouts.allowed("forged",999999)=="vanguard","Unknown class is rejected")
 p.set_class("marksman"); p.refill(); p.fire_cooldown=0; p.equip_cooldown=0
 Input.action_press("fire"); p.fire_requested=true; p._physics_process(.02)
 var remaining=p.ammo[0]
 for i in range(30): p._physics_process(.02)
 Input.action_release("fire")
 check(p.ammo[0]==remaining,"Holding fire does not turn the DMR into an automatic weapon")
 p.fire_cooldown=.04; p.fire_requested=true; p.fire_blocked_until_release=false
 p._physics_process(.02); p._physics_process(.025)
 check(p.ammo[0]==remaining-1,"A tap just before recovery ends is buffered once")
 p.fire_cooldown=0; p.viewmodel.on_shot(); p.viewmodel.update_pose(.5)
 check(p.viewmodel.root.position.is_finite() and absf(p.viewmodel.recoil_position)<2,"Weapon spring stays stable through a long frame")
 p.set_class("vanguard"); p.refill(); p.viewmodel.update_pose(0)
 Input.action_press("aim"); p.viewmodel.update_pose(.016)
 check(p.viewmodel.aim_blend>0 and p.viewmodel.aim_blend<1,"Weapon ADS eases instead of snapping")
 Input.action_release("aim")
 game.prefs.data.weapon_motion=0; p.velocity=Vector3(6,0,0); p.viewmodel.update_pose(.2)
 check(absf(p.viewmodel.root.rotation.z)<.001,"Motion slider removes bob and strafe lean")
 game.prefs.data.weapon_motion=1
 var prefs=game.Preferences.new("user://armory_profile_test.json")
 prefs.data.xp=Loadouts.Progress.threshold(10); prefs.data.selected_class="marksman"; prefs.save()
 var loaded=game.Preferences.new(prefs.path); loaded.load_profile()
 check(loaded.data.selected_class=="marksman" and loaded.data.xp==prefs.data.xp,"Unlocked loadout and XP survive profile reload")
 DirAccess.remove_absolute(prefs.path); DirAccess.remove_absolute(prefs.path+".bak")
 await game.net.host(27926,"",false); freeze()
 var n=game.net
 n.peers[1].progress.profiles.YOU=0
 n._queue_class(1,"marksman")
 check(n.peers[1].selected_class=="vanguard","Host rejects a locked class request")
 n.peers[1].progress.profiles.YOU=Loadouts.Progress.threshold(3)
 n._queue_class(1,"raider")
 check(p.class_id=="vanguard","Changing class cannot refill or replace the current life")
 p.life_id+=1; p.reset_at(p.position)
 check(p.class_id=="raider" and p.ammo[0]==32,"Pending class applies on the next authoritative spawn")
 var clip={"map":game.current_map,"id":987,"result_team":p.team,"result_match":true}
 game.replays.present_final(clip,"SCORE LIMIT")
 check(game.replays.outro_title=="GAME WON" and game.replays.fade_alpha()==0,"Victory animation keeps the arena visible")
 game.replays.stop(false); clip.id+=1; clip.result_team=3-p.team; clip.result_match=false
 game.replays.present_final(clip,"BOMB DEFUSED")
 check(game.replays.outro_title=="ROUND LOST","Results are relative to the viewer's team")
 game.replays.reset()
func host_test() -> void:
 check(await game.net.host(27917,"armory",false),"Armory host starts")
 freeze(); mark("host")
 check(await wait_for(func(): return game.net.peers.size()==2),"Armory client joins")
 var n=game.net; var peer=0
 for id in n.peers:
  if id!=1: peer=id
 if peer==0: return
 var actor=n.slots[n.peers[peer].slot].actor
 actor.set_physics_process(false)
 check(actor.class_id=="raider" and actor.ammo[0]==32,"Handshake applies the unlocked SMG on the server")
 check(await wait_for(func(): return marked("ready")),"Client receives authoritative class")
 n._queue_class(peer,"marksman")
 check(n.peers[peer].selected_class=="raider","Server rejects a class above the remote player's level")
 mark("select")
 check(await wait_for(func(): return n.peers[peer].selected_class=="vanguard"),"Client queues an unlocked class through RPC")
 check(actor.class_id=="raider","Queued selection preserves the current life")
 actor.health=0; n.replay_wait.erase(peer); n._respawn_human(actor)
 check(actor.class_id=="vanguard" and actor.ammo[0]==24,"Respawn applies the queued rifle loadout")
 check(await wait_for(func(): return marked("respawned")),"Client reconciles the new class and ammunition")
 mark("done")
func client_test() -> void:
 check(await wait_for(func(): return marked("host")),"Host available")
 game.prefs.data.xp=Loadouts.Progress.threshold(3); game.progression.profiles.YOU=game.prefs.data.xp
 game.prefs.data.selected_class="raider"; game.prefs.data.killcams=false
 game.net.join("127.0.0.1",join_port,"armory")
 check(await wait_for(func(): return game.net.is_client_ready() and game.player.class_id=="raider" and game.player.ammo[0]==32),"Selected unlocked class replicates to client")
 check(game.player.ammo[0]==32 and game.player.weapon_stats(0).name=="KESTREL SMG","Client prediction uses the same SMG stats")
 mark("ready"); await wait_for(func(): return marked("select"))
 game.net.select_class("vanguard")
 check(await wait_for(func(): return game.player.class_id=="vanguard" and game.player.ammo[0]==24),"Next-life class and ammo arrive together")
 mark("respawned"); await wait_for(func(): return marked("done"))
