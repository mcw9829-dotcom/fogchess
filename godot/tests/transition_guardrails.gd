extends SceneTree
var app
var fails := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
 print(("PASS " if ok else "FAIL ")+label)
 if not ok: fails += 1
func run() -> void:
 root.size=Vector2i(1120,760)
 app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
 await create_timer(.3).timeout
 for child in app.get_children():
  if child is Timer: child.stop()
 app.audio.enabled=false
 var tr=app.ui_motion._match_transition()
 if DisplayServer.get_name()=="headless":
  check(not tr.prepare_entry(),"headless entry declines rendering")
  check(not tr.prepare_return(),"headless return declines rendering")
  check(not tr.is_busy() and tr.get_child_count()==0,"headless creates no overlay")
  await app._join({"solo":true})
  check(app.view.has("grid") and app.game.visible,"headless session still enters")
  check(not app.ui_motion.is_transition_busy(),"headless does not gate gameplay")
  app._return_home()
  check(app.home.visible and app.room.is_empty(),"headless return semantics retained")
 else:
  check(tr.prepare_entry(),"prepare first entry")
  tr.start_entry()
  tr.cancel()
  check(tr.prepare_entry(),"prepare replacement entry")
  for n in range(4): await process_frame
  check(tr.phase=="preparing" and tr.direction=="entry","stale layout continuation cannot cancel replacement")
  tr.cancel();tr.cancel()
  await process_frame
  check(not tr.is_busy() and tr.get_child_count()==0,"repeat cancel releases all owned nodes")
  var timeout_count: Array=[0]
  tr.preparation_timed_out.connect(func(): timeout_count[0]+=1)
  check(tr.prepare_entry(),"prepare timeout case")
  tr.preparation_elapsed=9.8
  tr._process(.1)
  check(tr.is_busy() and timeout_count[0]==0,"before ten seconds retains cover")
  tr._process(.11)
  await process_frame
  check(timeout_count[0]==1,"timeout emits once")
  check(not tr.is_busy() and tr.get_child_count()==0,"timeout releases shield and proxies")
  check(app.home.visible and app.room.is_empty(),"timeout integration returns home")
  tr._process(11.0)
  check(timeout_count[0]==1,"idle cannot reemit timeout")
  await app._join({"solo":true})
  for n in range(4): await process_frame
  check(app.ui_motion.is_transition_busy(),"fresh entry works after timeout")
  app.ui_motion.cancel_match_entry()
  app._return_home()
  for n in range(4): await process_frame
  app.ui_motion.cancel_match_entry()
  await process_frame
  check(not app.ui_motion.is_transition_busy(),"entry and immediate return cancellation unlocks")
 print("LOBBY_CHECKS=",6 if DisplayServer.get_name()=="headless" else 12)
 print("LOBBY_FAILURES=",fails)
 app.queue_free();await process_frame;quit(fails)
