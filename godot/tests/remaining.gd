extends RefCounted
var app: Control
var tree: SceneTree
var check: Callable
func close() -> void:
	for node in app.get_children():
		if node is Window: node.queue_free()
	await tree.process_frame
func button(parent: Node,text: String) -> Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text==text or node.get_meta("action_title","")==text: return node
	return null
func shot(name: String) -> void:
	await tree.create_timer(.2).timeout
	if "--capture" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(false)
		tree.root.get_texture().get_image().save_png("res://tests/"+name+".png")
func run(client: Control,scene: SceneTree,assertion: Callable) -> void:
	app=client; tree=scene; check=assertion
	await close()
	var source: Dictionary = preload("res://original_demo(원본 시연 재현).gd").scenes()
	check.call(source.intro.size()==4 and source.guide.size()==6,"all deployed intro and guide scenes imported")
	var demo := preload("res://intro_demo(인트로 시연).gd").new()
	app.add_child(demo)
	check.call(demo.lit(demo.frames[0],6,1) and [1,1] in demo.spec.terrain.forest,"intro JSON coordinates preserve zone and terrain membership")
	check.call(is_equal_approx(demo.frame_duration(0),float(demo.frames[0].get("hold",4000))/1000),"intro holds use original millisecond timeline")
	check.call(is_equal_approx(demo.frame_duration(demo.frames.size()-1),float(demo.frames.back().get("hold",4000))/1000+1.2),"intro loop keeps final 1.2 second pause")
	demo.queue_free()
	app._help()
	await tree.process_frame
	var demos: Array=[]
	for node in app.find_children("*","Control",true,false):
		if node.get_script()==preload("res://guide_demo(설명용 시연).gd"): demos.append(node)
	check.call(demos.size()==6,"guide exposes six original cards")
	if demos.size()==6:
		demos[0].start(); demos[1].start()
		check.call(not demos[0].running and demos[1].running,"hovering a new card stops the previous demo")
		check.call(demos[0].frames.size()==9 and demos[2].frames.size()==13 and demos[4].frames.size()==13,"guide movement capture and ability frames restored")
		check.call(is_equal_approx(demos[2].frame_duration(2),.85),"guide advances every 850ms")
	await close()
	app._intro(3)
	check.call(button(app,"직접 조작하며 배우기")!=null and button(app,"바로 쉬움 봇 대국")!=null,"intro offers learning and a direct easy-bot path")
	await shot("intro_final")
	tree.root.size=Vector2i(390,844)
	await shot("intro_final_mobile")
	var intro_window: Window
	for node in app.get_children():
		if node is Window and node.visible: intro_window=node
	check.call(intro_window.size.x<=366,"intro final navigation fits mobile viewport")
	tree.root.size=Vector2i(1280,720)
	await tree.process_frame
	await close()
	await app._patchnotes()
	var disclosures: Array=[]
	for node in app.find_children("*","Button",true,false):
		if node.text.begins_with("▾ ") or node.text.begins_with("▸ "): disclosures.append(node)
	check.call(disclosures.size()>3 and disclosures[0].text.begins_with("▾ ") and disclosures[3].text.begins_with("▸ "),"patch notes initially expand only latest three entries")
	if not disclosures.is_empty():
		disclosures[0].pressed.emit()
		check.call(disclosures[0].text.begins_with("▸ "),"patch note disclosure collapses on click")
		disclosures[0].pressed.emit()
	await shot("patchnotes")
	await close()
	await app._leaderboard()
	var toggle := button(app,"레이팅 규칙 보기")
	check.call(toggle!=null,"rating rules modal action available")
	if toggle: toggle.pressed.emit()
	await shot("rating_rules")
	var correct_tier := false
	for node in app.find_children("*","Label",true,false):
		if node.text=="1700~1899": correct_tier=true
	check.call(correct_tier,"descending server tiers display increasing valid intervals")
	await close()
	var saved_me: Dictionary=app.me
	app.me={"name":"LocalPlayer","rating":1000,"tier":"N"}
	await app._match_update({"ok":true,"state":"waiting","waited":29,"window":200,"queue":1})
	check.call(button(app.match_body,"컴퓨터와 한 판")==null,"bot suggestion hidden before 30 seconds")
	await app._match_update({"ok":true,"state":"waiting","waited":30,"window":250,"queue":1})
	check.call(button(app.match_body,"컴퓨터와 한 판")!=null,"bot suggestion appears at 30 seconds")
	await shot("match_waiting")
	await app._match_update({"ok":true,"state":"found","opp":{"name":"LocalOpponent","rating":1100},"secondsLeft":15,"accepted":false,"oppAccepted":false})
	check.call(button(app.match_body,"수락")!=null and button(app.match_body,"거절")!=null,"match offer exposes accept and decline")
	var stable_accept = button(app.match_body,"수락")
	await app._match_update({"ok":true,"state":"found","opp":{"name":"LocalOpponent","rating":1100},"secondsLeft":14,"accepted":false,"oppAccepted":false})
	check.call(button(app.match_body,"수락")==stable_accept,"match countdown preserves accept button instance")
	await shot("match_found")
	tree.root.size=Vector2i(390,844)
	await shot("match_found_mobile")
	check.call(app.match_window.size.x<=366,"match offer resizes inside mobile viewport")
	tree.root.size=Vector2i(1280,720)
	await tree.process_frame
	await app._match_update({"ok":true,"state":"found","opp":{"name":"LocalOpponent","rating":1100},"secondsLeft":12,"accepted":true,"oppAccepted":false})
	check.call(button(app.match_body,"수락함").disabled,"accepted match cannot submit twice")
	app.matching=false; app.match_data={}; app.me=saved_me
	await close()
	var saved_view: Dictionary=app.view
	var saved_seat: String=app.seat
	app.seat="W"
	app.view={"winner":"W","yourColor":"W","oppConnected":true,"rated":true,"ratingDelta":{"delta":16,"rating":1016},"log":["상대 기권"],"rematch":{"me":true,"opp":false}}
	app._render_result()
	check.call(button(app.result_actions,"제안 취소")!=null and "+16" in app.result_sub.text and "기권" in app.result_sub.text,"result preserves rating reason and cancel proposal")
	app.view.rematch={"me":false,"opp":true}; app._render_result()
	check.call(button(app.result_actions,"거절")!=null and button(app.result_actions,"다음 판 수락")!=null,"opponent rematch offer exposes both responses")
	app.view.oppConnected=false; app._render_result()
	check.call(button(app.result_actions,"다음 판 제안")==null and button(app.result_actions,"홈으로")!=null,"departed opponent prevents rematch")
	app.view={"winner":"B","solo":true}; app._render_result()
	check.call(app.result_label.text=="흑 승리" and app.result_sub.text=="혼자 연습","solo result never presents player defeat")
	app.view=saved_view; app.seat=saved_seat; app.result_signature=""
