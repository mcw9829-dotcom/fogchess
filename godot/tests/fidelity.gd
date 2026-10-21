extends RefCounted
var app: Control
var tree: SceneTree
var check: Callable

func window() -> Window:
	for child in app.get_children():
		if child is Window and child.visible and not child.is_queued_for_deletion(): return child
	return null
func button(text: String) -> Button:
	for node in window().find_children("*","Button",true,false):
		if (node.text==text or node.get_meta("action_title","")==text) and node.is_visible_in_tree(): return node
	return null
func fields() -> Array: return window().find_children("*","LineEdit",true,false)
func error() -> String:
	for node in window().find_children("*","Label",true,false):
		if node.get_meta("form_error",false): return node.text
	return ""
func close() -> void:
	for child in app.get_children():
		if child is Window: child.queue_free()
	await tree.process_frame
func wait_until(predicate: Callable) -> void:
	for i in range(100):
		if predicate.call(): return
		await tree.create_timer(.05).timeout
func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	tree.root.get_texture().get_image().save_png("res://tests/"+name+".png")

func run(client: Control,scene: SceneTree,assertion: Callable) -> void:
	app = client
	tree = scene
	check = assertion
	check.call(app._password_problem("한글Pass123!").is_empty(),"password accepts Unicode letters like original")
	check.call(not app._password_problem("Password 1!").is_empty(),"password rejects whitespace")
	check.call(not app._password_problem("Password123").is_empty(),"password requires special character")
	app._effect_preview()
	await tree.process_frame
	var fx: Control
	for node in window().find_children("*","Control",true,false):
		if node.get_script()==load("res://fx_layer(파티클·전투 이펙트).gd"): fx=node
	check.call(fx!=null and fx.cols==8,"preview uses original 8x8 board")
	for name in ["포획","저격","돌파","스캔","킹 처치","승리","패배","무승부"]:
		fx.clear()
		button(name).pressed.emit()
		await tree.create_timer(.17).timeout
		check.call(not fx.parts.is_empty() or not fx.timers.is_empty(),"native FX preview: "+name)
		if name=="돌파": await shot("fx_barrage")
		if name=="패배": await shot("fx_defeat")
		if name=="스캔": await shot("fx_scan")
		if name=="승리":
			await tree.create_timer(.6).timeout
			await shot("fx_victory")
		if name=="킹 처치":
			await tree.create_timer(.22).timeout
			await shot("fx_king")
	fx.clear()
	fx.flipped = true
	check.call(fx.point([0,0]).is_equal_approx(Vector2(270,270)),"flipped FX tracks black board coordinates")
	fx.flipped = false
	for i in range(650): fx.add({"kind":"dot","pos":Vector2.ZERO})
	check.call(fx.parts.size()==600,"particle budget stays at original 600 cap")
	fx.clear()
	fx.reduced = true
	fx.play({"type":"kill","cells":[[3,4]]})
	check.call(fx.shake==0 and fx.slow==0 and fx.parts.size()<20,"reduced motion suppresses shake/slowmo and lowers particles")
	fx.clear()
	check.call(fx.parts.is_empty() and fx.timers.is_empty(),"closing FX cancels delayed particles")
	for event in app.audio.EVENTS:
		var sound: AudioStreamWAV = load("res://sounds/%s.wav" % event)
		check.call(sound!=null and sound.get_length()>0,"original synthesized sound: "+event)
	app.audio.enabled = false
	var before: int = app.audio.played.size()
	app.audio.cue("fire")
	check.call(app.audio.played.size()==before,"muted effects do not play")
	app.audio.enabled = true
	await close()
	app._feedback()
	await tree.process_frame
	var text: TextEdit = window().find_children("*","TextEdit",true,false)[0]
	var category: OptionButton = window().find_children("*","OptionButton",true,false)[0]
	check.call(category.item_count==4,"feedback has all four original categories")
	button("보내기").pressed.emit()
	check.call(error().contains("3자"),"feedback short-message validation stays in form")
	text.text = "x".repeat(1001)
	text.text_changed.emit()
	check.call(text.text.length()==1000,"feedback enforces 1000-character limit")
	text.text = "로컬 임시 DB 전용 테스트 피드백"
	text.text_changed.emit()
	category.select(1)
	await shot("feedback")
	tree.root.size = Vector2i(390,844)
	await tree.process_frame
	await tree.process_frame
	check.call(window().size.x<=366 and window().position.x>=0,"open feedback resizes within mobile viewport")
	await shot("feedback_mobile")
	tree.root.size = Vector2i(1280,720)
	await tree.process_frame
	button("보내기").pressed.emit()
	await wait_until(func(): return not text.is_visible_in_tree())
	check.call(not text.is_visible_in_tree(),"feedback successful submission shows confirmation")
	await close()
	app._account()
	await tree.create_timer(.15).timeout
	await shot("profile")
	tree.root.size = Vector2i(390,844)
	await tree.process_frame
	await tree.process_frame
	check.call(window().size.x<=366,"profile fits mobile viewport")
	await shot("profile_mobile")
	tree.root.size = Vector2i(1280,720)
	await tree.process_frame
	button("닉네임 변경").pressed.emit()
	fields()[0].text = "!"
	button("저장").pressed.emit()
	check.call(error().contains("닉네임은"),"nickname rejects invalid characters")
	fields()[0].text = "ParityUser"
	button("저장").pressed.emit()
	await wait_until(func(): return app.me.get("name")=="ParityUser")
	check.call(app.me.get("name")=="ParityUser","nickname update refreshes profile")
	button("비밀번호 변경").pressed.emit()
	fields()[0].text = "FormPass123!"
	fields()[1].text = "NewParity123!"
	fields()[1].text_changed.emit(fields()[1].text)
	fields()[2].text = "Mismatch123!"
	button("변경").pressed.emit()
	check.call(error().contains("일치하지"),"password confirmation mismatch blocked")
	await shot("password_form")
	fields()[2].text = "NewParity123!"
	button("변경").pressed.emit()
	await wait_until(func(): return fields().is_empty())
	check.call(fields().is_empty(),"password change succeeds and closes inline form")
	button("복구 코드 재발급").pressed.emit()
	fields()[0].text = "NewParity123!"
	button("발급").pressed.emit()
	await wait_until(func(): return window().title.begins_with("복구 코드"))
	check.call(window().title.begins_with("복구 코드"),"reissue displays one-time code screen")
	var code: String = fields()[0].text
	check.call(code.begins_with("FOG-"),"recovery code format retained")
	await shot("recovery")
	await close()
	app._find_account()
	await tree.process_frame
	fields()[0].text = code
	fields()[1].text = "ResetParity123!"
	button("새 비밀번호로 바꾸고 로그인").pressed.emit()
	await wait_until(func(): return window().title.begins_with("복구 코드"))
	check.call(window().title.begins_with("복구 코드"),"recovery resets password and logs in")
	var old: Dictionary = await app.api.request("/recover/code",{"code":code,"new":"AnotherPass123!"})
	check.call(not old.get("ok"),"used recovery code becomes invalid")
	await close()
