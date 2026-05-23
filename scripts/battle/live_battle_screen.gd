# LiveBattleScreen.gd
extends Control

@onready var attacker_container: GridContainer = $SceneLayout/StageLayout/LeftTeamBox/AttackerRoster
@onready var defender_container: GridContainer = $SceneLayout/StageLayout/RightTeamBox/DefenderRoster
@onready var log_box = $SceneLayout/FooterPanel/BattleLog
@onready var background_sprite = $Battlefield
@onready var groove_meter: ProgressBar = $SceneLayout/HeaderPanel/GrooveMeter
@onready var encore_button: Button = $SceneLayout/HeaderPanel/EncoreButton
@onready var sonic_boom_button: Button = $SceneLayout/HeaderPanel/SonicBoomButton

var card_scene = preload("res://scenes/battle_member_card.tscn")
var controller: BattleController
var is_processing_action: bool = false
var retreat_btn: Button
var exit_btn: Button

func start_interactive_battle(attacker: Band, defender: Band, venue: Venue) -> void:
	# 1. 實例化大腦並加入場景樹 (使其能使用 await timer)
	controller = BattleController.new()
	add_child(controller)
	
	# 2. 綁定大腦的信號到 UI
	controller.log_requested.connect(_on_log_requested)
	controller.groove_updated.connect(_update_groove_ui)
	controller.hp_updated.connect(_update_all_hp_bars)
	controller.attacker_selected.connect(_highlight_attacker)
	controller.turn_started.connect(_refresh_card_filters)
	controller.venue_ready.connect(_setup_background)
	controller.battle_ended.connect(_on_battle_ended) # 綁定結算信號
	
	_setup_retreat_button() # 戰鬥一開始，生成逃跑按鈕
	_build_rosters(attacker, defender)
	
	# 4. 把資料丟給大腦，讓大腦開始跑遊戲邏輯
	controller.setup_battle(attacker, defender, venue)

func _setup_background(bg_path: String) -> void:
	if bg_path != "" and ResourceLoader.exists(bg_path):
		background_sprite.texture = load(bg_path)
		background_sprite.custom_minimum_size = Vector2(1920, 1080)
	else:
		_on_log_requested("[系統] 找不到場地背景圖片: " + bg_path, "red")

# ==========================================
# 玩家輸入處理 (Input Handling)
# ==========================================
func _on_target_clicked(target_member) -> void:
	if is_processing_action or not controller._check_is_player_round(): 
		return
		
	var target_band = controller.defender_band if controller.current_state == controller.TurnState.CHOOSE_ATTACKER else controller.attacker_band
	
	# 詢問大腦：這個目標合法嗎？
	if not controller.is_target_legal(controller.selected_attacker, target_member, target_band):
		_on_log_requested("[無效目標] 前排仍有隊員在阻擋護航！", "orange")
		return
		
	is_processing_action = true
	controller.execute_combat_turn(controller.selected_attacker, target_member)
	is_processing_action = false

# ==========================================
# 介面更新回應 (UI Updates)
# ==========================================
func _highlight_attacker(attacker_data) -> void:
	_on_log_requested("★ 輪到 [ %s ] (%s) 進行演出準備！" % [attacker_data.name, attacker_data.part], "yellow")
	
	# 尋找是哪張卡片並發亮
	var all_cards = attacker_container.get_children() + defender_container.get_children()
	for card in all_cards:
		if card.get("member_data") == attacker_data:
			card.modulate = Color(1.5, 1.5, 1.0, 1.0)
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0) # 重置其他人
			
	refresh_targetable_overlays()

func refresh_targetable_overlays() -> void:
	if controller.selected_attacker == null: return
	
	var is_attacker_turn = controller.current_state == controller.TurnState.CHOOSE_ATTACKER
	var target_grid = defender_container if is_attacker_turn else attacker_container
	var target_band = controller.defender_band if is_attacker_turn else controller.attacker_band
	
	for card in target_grid.get_children():
		var defender = card.member_data
		if controller.is_target_legal(controller.selected_attacker, defender, target_band) and defender.hp > 0:
			card.modulate = Color(0.4, 0.8, 0.7, 1.0) 
			card.disabled = false
		else:
			card.modulate = Color(0.4, 0.4, 0.4, 0.8)
			card.disabled = true

func _update_groove_ui(energy: float, encore_cost: float, sonic_cost: float) -> void:
	groove_meter.value = energy
	encore_button.disabled = energy < encore_cost
	sonic_boom_button.disabled = energy < sonic_cost

func _on_log_requested(msg: String, color: String) -> void:
	log_box.append_text("[color=%s]%s[/color]\n" % [color, msg])

func _update_all_hp_bars() -> void:
	for card in attacker_container.get_children(): card.update_hp_display()
	for card in defender_container.get_children(): card.update_hp_display()

func _build_rosters(attacker, defender) -> void:
	# 1. Clean out the previous visual grid setups
	for child in attacker_container.get_children(): child.queue_free()
	for child in defender_container.get_children(): child.queue_free()
	
	# 2. Configure clean, grid-based spacing boundaries
	# This handles the structural gap between columns and rows independently
	var space_x = 200 # Distance between columns
	var space_y = 300 # Distance between rows
	
	attacker_container.add_theme_constant_override("h_separation", space_x)
	attacker_container.add_theme_constant_override("v_separation", space_y)
	
	defender_container.add_theme_constant_override("h_separation", space_x)
	defender_container.add_theme_constant_override("v_separation", space_y)
	
	# 3. Dynamic Spawning logic maps directly into the 3-column rows automatically!
	# Spawn Attackers
	for member in attacker.members:
		var card = card_scene.instantiate()
		attacker_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_target_clicked)
		
	# Spawn Defenders
	for member in defender.members:
		var card = card_scene.instantiate()
		defender_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_target_clicked)

## 當回合狀態改變時，重置並過濾所有卡片的視覺狀態
func _refresh_card_filters(is_player_turn: bool) -> void:
	# 1. 取得當前行動方與防守方的 UI 容器
	var active_container = attacker_container if is_player_turn else defender_container
	var target_container = defender_container if is_player_turn else attacker_container
	
	# 2. 處理行動方 (己方) 的卡片
	for card in active_container.get_children():
		if card.member_data.hp <= 0:
			card.modulate = Color(0.3, 0.3, 0.3, 0.5) # 死亡：半透明灰暗
			card.disabled = true
			continue
			
		# 如果大腦說這個人這回合已經動過了，我們就把他變暗，且不允許點擊
		if controller.acted_this_turn.has(card.member_data):
			card.modulate = Color(0.6, 0.6, 0.6, 1.0) # 已行動：稍微變暗
			card.disabled = true
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0) # 未行動：正常亮度
			card.disabled = true # 行動方是自動輪替的，所以平常也不用點擊
			
	# 3. 處理防守方 (敵方) 的卡片
	for card in target_container.get_children():
		if card.member_data.hp <= 0:
			card.modulate = Color(0.3, 0.3, 0.3, 0.5) # 死亡：半透明灰暗
			card.disabled = true
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0) # 活著：正常亮度
			card.disabled = true # 先全部鎖住，等待後續 refresh_targetable_overlays 來解鎖

# ==========================================
# 按鈕生成與生命週期管理
# ==========================================

## 建立逃跑按鈕 (隨時可按)
func _setup_retreat_button() -> void:
	retreat_btn = Button.new()
	retreat_btn.text = "逃跑 (Retreat)"
	retreat_btn.custom_minimum_size = Vector2(200, 50)
	
	# 將按鈕加入 Footer 面板中
	$SceneLayout/FooterPanel.add_child(retreat_btn)
	retreat_btn.pressed.connect(_on_retreat_pressed)

## 玩家點擊逃跑
func _on_retreat_pressed() -> void:
	if is_processing_action: return # 如果正在播攻擊動畫就不給按
	
	# 直接命令大腦執行撤退邏輯
	controller.force_retreat()

## 收到大腦「戰鬥結束」的信號
func _on_battle_ended(attacker_won: bool) -> void:
	# 1. 銷毀逃跑按鈕
	if retreat_btn:
		retreat_btn.queue_free()
		retreat_btn = null
		
	# 2. 生成結算離開按鈕
	exit_btn = Button.new()
	exit_btn.text = "確認並返回地圖 (Confirm & Return)"
	exit_btn.custom_minimum_size = Vector2(200, 50)
	
	# 這裡你可以依照 attacker_won 來決定按鈕顏色，例如贏了是綠色，輸了是紅色
	if attacker_won:
		exit_btn.modulate = Color(0.5, 1.0, 0.5)
	else:
		exit_btn.modulate = Color(1.0, 0.5, 0.5)
		
	$SceneLayout/FooterPanel.add_child(exit_btn)
	
	# 3. 綁定離開事件，呼叫 Global Facade 切換場景
	exit_btn.pressed.connect(Global.event_facade.stop_invation)
