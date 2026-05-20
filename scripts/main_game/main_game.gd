extends Node

@onready var ui = $MapUI/StaticScreenLayer/MainGameUI
@onready var camera: Camera2D = $Camera2D

var data
var event_facade: GameEventFacade

func _ready() -> void:
	if not GameStateBang.data:
		GameStateBang.data = GameInitializer.bootstrap(PlotMode.PlotMode.STORY)
	data = GameStateBang.data
	
	# Instantiate our facade context mapping
	event_facade = GameEventFacade.new(self, ui)
	Global.event_facade = event_facade
	
	# Connect UI Signals
	ui.basic_button_pressed.connect(_on_ui_basic_action)
	ui.venue_button_pressed.connect(_on_ui_venue_selected)
	ui.player_selection_confirmed.connect(_on_ui_player_choice)
	ui.enemy_selection_confirmed.connect(_on_ui_enemy_choice)
	
	ui.generate_venue_buttons()
	GameStateBang.set_turn_band(GameStateBang.player)

func process_events() -> void:
	for ev in data.eventPool:
		if ev.triggered:
			continue
		if ev.trigger_condition.call(GameStateBang.turn, data):
			ui.game_log("\n[!] STORY EVENT: " + ev.description, "yellow")
			# Pass the facade context to the reflection system
			await ev.execute(event_facade)
			ev.triggered = true

# --- UI ACTION INTERCEPTORS ROUTING TO FACADE ---

func _on_ui_basic_action(action_name: String) -> void:
	match action_name:
		"Exit game": get_tree().quit()
		"End turn":
			GameStateBang.data = data
			GameStateBang.next_turn()
			process_turn_rollover()

func _on_ui_venue_selected(venue_name: String) -> void:
	var venue = data.worldMap[venue_name]
	var owner = venue.owner.band_name
	GameStateBang.current_venue = venue_name
	GameStateBang.current_band = owner
	ui.refresh_venue_furniture_icons(venue.installed_furniture)
	if venue.owner.band_name == GameStateBang.player:
		ui.show_player_selection(GameStateBang.player)
	else:
		var rel = data.bands[GameStateBang.player].get_relation(owner)
		ui.show_enemy_selection(owner, rel)

func _on_ui_player_choice(selection: String) -> void:
	match selection:
		"Check member":
			get_tree().change_scene_to_file("res://scenes/member_panel.tscn")
		"Purchase":
			# Inside your Main Map View / GameEngine.gd
			open_furniture_shop()

func open_furniture_shop() -> void:
	var shop_scene = preload("res://scenes/furniture_shop.tscn")
	var shop_instance = shop_scene.instantiate()

	# Add it on top of the screen layout
	add_child(shop_instance)
func _on_ui_enemy_choice(action: String) -> void:
	match action:
		"Check members":
			get_tree().change_scene_to_file("res://scenes/member_panel.tscn")
		"対バン":
			Global.event_facade.execute_action(Global.event_facade.start_invasion, [GameStateBang.player, GameStateBang.current_venue])
		"Challenge":
			# Route standard player actions directly through the facade interface!
			Global.event_facade.execute_action(Global.event_facade.set_band_relations, [GameStateBang.player, GameStateBang.current_band, "Rival"])
			var new_rel = data.bands[GameStateBang.player].get_relation(GameStateBang.current_band)
			ui.update_selection_label("%s(%s)" % [GameStateBang.current_band, new_rel])
		"Cooperate":
			# Route standard player actions directly through the facade interface!
			Global.event_facade.execute_action(Global.event_facade.set_band_relations, [GameStateBang.player, GameStateBang.current_band, "Allied"])
			var new_rel = data.bands[GameStateBang.player].get_relation(GameStateBang.current_band)
			ui.update_selection_label("%s(%s)" % [GameStateBang.current_band, new_rel])

func process_turn_rollover() -> void:
	set_process_input(false)
	_turn_recovery()
	GameStateBang.turn += 1
	ui.game_log("☀️ 新的一天開始，全體樂團精神抖擻，AP 已重置！", "green")
	_ai_round()
	process_events()
	set_process_input(true)

func _turn_recovery():
	for band_name in data.bands:
		var band: Band = data.bands[band_name]
		
		# 1. Count how many venues they own in the global map state database
		var controlled_venues = band.venues.size()
		
		# 2. Re-calculate action budget for the new round
		band.refresh_turn_actions(controlled_venues)
		
		# 3. Trigger individual stamina / performance growth gains
		band.process_turn_recovery(data.worldMap)
		
## 當玩家點擊「結束回合」按鈕
func _ai_round() -> void:
# 1. 建立一個純字串陣列作為待辦清單 (Queue)
	var ai_queue: Array[String] = []
	for b_name in GameStateBang.data.bands:
		if b_name != GameStateBang.player:
			ai_queue.append(b_name)
			
	# 2. 使用 while 迴圈代替 for 迴圈
	# 只要清單裡還有 AI，就一直跑，絕對不怕戰鬥場景中斷指針！
	while ai_queue.size() > 0:
		# 彈出佇列中的第一位 AI 樂團名稱
		var current_ai_band = ai_queue.pop_front()
		
		var ai_personality = "AGGRESSIVE" if current_ai_band == "RAISE A SUILEN" else "BALANCED"
		var ai_brain = BandBrainAI.new(Global.event_facade, current_ai_band, ai_personality)
		
		# 啟動思考
		ai_brain.process_turn()
		
		# 這裡會安全卡住。不論打仗打多久，回來後 while 條件句只會看 ai_queue.size() 
		# 陣列長度是純資料，絕對不會因為場景切換而崩潰或遺失！
		await ai_brain.ai_process_complete
	GameStateBang.set_turn_band(GameStateBang.player)
