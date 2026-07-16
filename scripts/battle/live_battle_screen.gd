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
var controller: BattleController # 🔥 轉由外部或主控制器指派注入
var is_processing_action: bool = false
var retreat_btn: Button
var exit_btn: Button

func _init() -> void:
	controller = BattleController.new()

## 🆕 配合全新轉場流，改由主控制器叫起畫面並完成信號對接
func start_interactive_battle(attacker: Band, defender: Band, venue: Venue) -> void:
	# 🚨 注意：大腦此時已由主控制器在外部建立完成並指派給 controller 變數。
	# 我們在這裡純粹進行「信號綁定」與「舞台畫面初始化」。
	
	# 1. 綁定大腦的信號到 UI
	controller.log_requested.connect(_on_log_requested)
	controller.groove_updated.connect(_update_groove_ui)
	controller.hp_updated.connect(_update_all_hp_bars)
	controller.attacker_selected.connect(_highlight_attacker)
	controller.turn_started.connect(_refresh_card_filters)
	controller.venue_ready.connect(_setup_background)
	controller.battle_ended.connect(_on_battle_ended)
	
	_setup_retreat_button() # 戰鬥一開始，生成逃跑按鈕
	
	# 2. 🔥 核心變更：不再傳入 Band 大物件去抓全員，而是讓 UI 改刷「真正上台著名單」
	controller.venue_ready.connect(func(_bg): _build_rosters_from_engaged())

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
		
	# 詢問大腦：這個目標合法嗎？
	if not controller.is_target_legal(controller.selected_attacker, target_member):
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
	
	var all_cards = attacker_container.get_children() + defender_container.get_children()
	for card in all_cards:
		if card.get("member_data") == attacker_data:
			card.modulate = Color(1.5, 1.5, 1.0, 1.0)
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0) 
			
	refresh_targetable_overlays()

func refresh_targetable_overlays() -> void:
	if controller.selected_attacker == null: return
	
	var is_attacker_turn = controller.current_state == controller.TurnState.CHOOSE_ATTACKER
	var target_grid = defender_container if is_attacker_turn else attacker_container
	
	for card in target_grid.get_children():
		var defender = card.member_data
		# 🎯 這裡修正為直接傳入當前攻擊者與防守者進行合法度判定
		if controller.is_target_legal(controller.selected_attacker, defender) and defender.hp > 0:
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

# ==========================================
# 🎨 核心重構：只為上台的參戰精英動態生成卡片
# ==========================================
func _build_rosters_from_engaged() -> void:
	# 1. 乾淨清空排版容器
	for child in attacker_container.get_children(): child.queue_free()
	for child in defender_container.get_children(): child.queue_free()
	
	var space_x = 200 
	var space_y = 300 
	attacker_container.add_theme_constant_override("h_separation", space_x)
	attacker_container.add_theme_constant_override("v_separation", space_y)
	defender_container.add_theme_constant_override("h_separation", space_x)
	defender_container.add_theme_constant_override("v_separation", space_y)
	
	# 2. 🎯 精準對位：從大腦中撈出「真正上場的人」，生成進攻方卡片
	for member in controller.attacker_engaged_members:
		var card = card_scene.instantiate()
		attacker_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_target_clicked)
		
	# 3. 🎯 生成防守方卡片
	for member in controller.defender_engaged_members:
		var card = card_scene.instantiate()
		defender_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_target_clicked)

## 當回合狀態改變時，重置並過濾所有卡片的視覺狀態
func _refresh_card_filters(is_player_turn: bool) -> void:
	var active_container = attacker_container if is_player_turn else defender_container
	var target_container = defender_container if is_player_turn else attacker_container
	
	for card in active_container.get_children():
		if card.member_data.hp <= 0:
			card.modulate = Color(0.3, 0.3, 0.3, 0.5) 
			card.disabled = true
			continue
			
		if controller.acted_this_turn.has(card.member_data):
			card.modulate = Color(0.6, 0.6, 0.6, 1.0) 
			card.disabled = true
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0) 
			card.disabled = true 
			
	for card in target_container.get_children():
		if card.member_data.hp <= 0:
			card.modulate = Color(0.3, 0.3, 0.3, 0.5) 
			card.disabled = true
		else:
			card.modulate = Color(1.0, 1.0, 1.0, 1.0) 
			card.disabled = true 

# ==========================================
# 按鈕生成與生命週期管理
# ==========================================
func _setup_retreat_button() -> void:
	retreat_btn = Button.new()
	retreat_btn.text = "撤退 (Retreat)"
	retreat_btn.custom_minimum_size = Vector2(200, 50)
	
	$SceneLayout/FooterPanel.add_child(retreat_btn)
	retreat_btn.pressed.connect(_on_retreat_pressed)

func _on_retreat_pressed() -> void:
	if is_processing_action: return 
	controller.force_retreat()

func _on_battle_ended(attacker_won: bool) -> void:
	if retreat_btn:
		retreat_btn.queue_free()
		retreat_btn = null
		
	exit_btn = Button.new()
	exit_btn.text = "確認並返回地圖 (Confirm & Return)"
	exit_btn.custom_minimum_size = Vector2(200, 50)
	
	if attacker_won:
		exit_btn.modulate = Color(0.5, 1.0, 0.5)
	else:
		exit_btn.modulate = Color(1.0, 0.5, 0.5)
		
	$SceneLayout/FooterPanel.add_child(exit_btn)
	
	# 🎯 配合先前修改的 stop_invation 進行連動釋放
	exit_btn.pressed.connect(Global.event_facade.stop_invation)
