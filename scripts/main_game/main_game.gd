extends Node

@onready var ui = $MapUI/StaticScreenLayer/MainGameUI
@onready var camera: Camera2D = $Camera2D

var data
var event_facade: GameEventFacade

# 在你的腳本頂部宣告這個陣列
var ai_queue: Array[String] = []
var current_ai_brain: BandBrainAI = null

func _ready() -> void:
	# 如果還沒有資料，直接呼叫大腦的 session 初始化
	if not GameStateBang.data or GameStateBang.data.is_empty():
		GameStateBang.init_game_session(PlotMode.PlotMode.STORY, "NEW_GAME")
		
	# 順暢指回乾淨的本地變數
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

func refresh_venues():
	ui.generate_venue_buttons()

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
			process_turn_rollover()
		"Check member":
			GameStateBang.current_band = GameStateBang.player
			event_facade.execute_action(event_facade.start_managing, [])
		"Recruit":
			var recruit_brain = RecruitController.new()
			if not recruit_brain.has_poster_wall():
				Global.event_facade.game_log("❌ 你需要先在自己的 Livehouse 購買並佈置「海報牆 (Poster Wall)」才能發佈招募啟事！", "red")
			event_facade.execute_action(event_facade.start_recruit, [])
		"Policy":
			event_facade.execute_action(event_facade.start_setting_policy, [])
		"Save":
			event_facade.execute_action(event_facade.save_game_session, [])
		"Victory":
			var player_name = GameStateBang.player
			var player_band = GameStateBang.data.bands.get(player_name)
			
			if not player_band: return
			
			# 🔥 直接把樂團的單一目標丟進去，1 行代碼秒殺判定
			if VictoryChecker.check_victory(player_band.goal):
				ui.game_log("🎉 宿願達成！恭喜制霸東京搖滾界！", "green")
			else:
				ui.game_log("❌ 少女們的理想尚未實現，繼續進攻下一座 Livehouse 吧！", "green")

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
			event_facade.execute_action(event_facade.start_managing, [])
		"Purchase":
			# Inside your Main Map View / GameEngine.gd
			open_furniture_shop()

func open_furniture_shop() -> void:
	event_facade.execute_action(event_facade.start_shopping, [])

func _on_ui_enemy_choice(action: String) -> void:
	match action:
		"Check members":
			event_facade.execute_action(event_facade.start_managing, [])
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
	_ai_round()
	GameStateBang.next_turn()
	ui.game_log("☀️ 新的一天開始，全體樂團精神抖擻，AP 已重置！", "green")

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
		band.process_turn_finance(data.worldMap)

## 當玩家點擊「結束回合」按鈕
func _ai_round() -> void:
	# 1. 每次開始 AI 回合時，確保已經連線到 Facade 的戰鬥結束信號
	if not Global.event_facade.battle_resolved.is_connected(_on_battle_resolved):
		Global.event_facade.battle_resolved.connect(_on_battle_resolved)
		
	# 2. 建立待辦清單 (Queue)
	ai_queue.clear()
	for b_name in GameStateBang.data.bands:
		if b_name != GameStateBang.player:
			ai_queue.append(b_name)
			
	# 3. 拔出第一根蘿蔔，啟動連鎖反應
	_process_next_ai()

## 抽取並執行下一位 AI
func _process_next_ai() -> void:
	# 如果清單空了，代表全體 AI 執行完畢
	if ai_queue.size() == 0:
		GameStateBang.set_turn_band(GameStateBang.player)
		return
		
	var current_ai_band = ai_queue.pop_front()
	GameStateBang.set_turn_band(current_ai_band)
	var ai_personality = "AGGRESSIVE" if current_ai_band == "RAISE A SUILEN" else "BALANCED"
	
	current_ai_brain = BandBrainAI.new(Global.event_facade, current_ai_band, ai_personality)
	
	# 監聽這個 AI 的「和平結束」信號
	current_ai_brain.ai_process_complete.connect(_on_ai_peaceful_complete)
	
	# 啟動思考
	current_ai_brain.process_turn()

## 狀況 A：AI 把 AP 花光，沒有引發戰爭 (和平結束)
func _on_ai_peaceful_complete() -> void:
	# 解除綁定，避免記憶體洩漏
	current_ai_brain.ai_process_complete.disconnect(_on_ai_peaceful_complete)
	
	# 呼叫下一位
	_process_next_ai()

## 狀況 B：AI 引發戰爭，玩家打完仗後回到大地圖 (戰爭結束)
func _on_battle_resolved() -> void:
	# 戰鬥結束了，因為之前的設定，發動戰爭的 AI 會直接中斷剩餘回合。
	# 我們在這裡直接無縫接軌，叫下一位 AI 出場！
	_process_next_ai()
