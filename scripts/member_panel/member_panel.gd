## MemberPanel.gd
## 純 UI 控制：負責接收大腦資料、排版並渲染視圖
extends Node

signal done_managing

@export var markers_parent: Node2D
@export var button_container: Control
@export var character_icon: TextureRect

# UI 核心組件
@onready var panel_train: Control = $LeftColumn/TrainPanel
@onready var panel_detailed_info: Control = $LeftColumn/DetailedInfoPanel
@onready var panel_rest: Control = $LeftColumn/RestPanel
@onready var panel_upgrade: Control = $LeftColumn/UpgradePanel
@onready var panel_others: Control = $LeftColumn/OthersPanel
@onready var panel_equip: Control = $LeftColumn/EquipPanel
@onready var panel_compare: Control = $LeftColumn/ComparePanel
@onready var compare_table: Tree = $LeftColumn/ComparePanel/CompareTree # 使用 Tree 來畫表格最快最整齊

@onready var equip_grid: GridContainer = $LeftColumn/EquipPanel/GridContainer
@onready var equip_desc_label: RichTextLabel = $LeftColumn/EquipPanel/DescriptionLabel

# ==========================================
# 動作功能按鈕節點 (Action Buttons)
# ==========================================
@onready var rest_button: Button = $LeftColumn/RestPanel/RestButton
@onready var upgrade_button: Button = $LeftColumn/UpgradePanel/UpgradeButton
@onready var train_button: Button = $LeftColumn/TrainPanel/TrainButton
@onready var layoff_button: Button = $LeftColumn/OthersPanel/LayoffButton
@onready var equip_buy_btn: Button = $LeftColumn/EquipPanel/BuyButton

const TAB_FILE_NAMES = ["train", "rest", "upgrade", "details", "strengthen", "others"]
const TAB_SIZE = Vector2(100, 60)

# 核心架構：大腦 Controller 指標
var controller: ManagementController
var current_table: Tree

# 排版快照位置
var table_position: Vector2
var buttons_position: Vector2
var tabs_position_start: Vector2
var tabs_position: Dictionary = {}
var current_active_tab: int = 4 # 預設開啟詳細面板
var first_member_item

# 1. 把舊的 popup preload 換成 shop_slot
var shop_slot_scene = preload("res://scenes/shop_slot.tscn") # 確保路徑正確

func _ready() -> void:
	setup_ui()
	
	# 1. 初始化大腦控制核心
	var current_band_id = GameStateBang.current_band
	controller = ManagementController.new(current_band_id)
	add_child(controller)
	
	# 2. 監聽大腦的刷新通知
	controller.data_refreshed.connect(_on_controller_data_refreshed)

	rest_button.pressed.connect(_on_rest_button_pressed)
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	train_button.pressed.connect(_on_train_button_pressed_ui)
	layoff_button.pressed.connect(_on_layoff_button_pressed)
	equip_buy_btn.pressed.connect(_on_buy_equipment_button_pressed)
	# 3. 初始排版與建構
	_initialize_mock_positions()
	spawn_dynamic_tabs()
	_refresh_entire_view()

## 當資料庫或數據產生變動，大腦呼叫我們刷新畫面
func _on_controller_data_refreshed() -> void:
	_refresh_entire_view()

func _refresh_entire_view() -> void:
	# 重新拉取樂團清單建立表格
	_build_member_table_view(controller.current_band)
	_update_character_icon(controller.selected_member.name if controller.selected_member else "")
	_refresh_active_tab_panel()

# ==========================================
# UI 渲染核心 (View Renderers)
# ==========================================
func _refresh_active_tab_panel() -> void:
	var all_panels = [
		panel_detailed_info, panel_rest, panel_upgrade, 
		panel_others, panel_train, panel_equip, panel_compare
	]
	for p in all_panels:
		p.visible = false
		
	if not controller.has_selected_member():
		$Info.text = "請由右方列表中選取一位樂團團員..."
		return

	_render_info_summary_label()

	# ==========================================================
	# 🔥 核心修正：陣營檢查分流
	# ==========================================================
	if not controller.is_player_band():
		# 點到對手樂團了！強制開啟對比模式，攔截後續所有操作分頁
		_render_band_comparison_view()
		return
	# ==========================================================

	# 如果是玩家自己的樂團，才允許執行原本的操作面板
	match current_active_tab:
		1: panel_train.visible = true 
		2: _render_rest_view()
		3: _render_upgrade_view()
		4: _render_details_view()
		5: _render_equip_view() 
		6: _render_others_view()

func _render_info_summary_label() -> void:
	var m = controller.selected_member
	$Info.text = "團員簡介 (Performer Profile)\n\n" + \
				"姓名 (Name): %s\n位置 (Part): %s\n" % [m.name, m.part] + \
				"等級 (Level): %d (經驗值 XP: %d)\n" % [m.level, m.xp] + \
				"體力狀態 (HP): %d / %d\n" % [m.hp, m.max_hp] + \
				"演奏表現 (Perf): %d\n耐力係數 (Stam): %d" % [m.get_total_performance(), m.stam]

func _render_rest_view() -> void:
	panel_rest.visible = true
	var data = controller.get_rest_data()
	
	$LeftColumn/RestPanel/SupplyLabel.text = "目前樂團補給 (Current Supply): %d / %d" % [data.current_supply, data.max_supply]
	$LeftColumn/RestPanel/MemberHPLabel.text = "團員體力 (Member HP): %d / %d" % [data.member_hp, data.member_max_hp]
	$LeftColumn/RestPanel/RestButton.disabled = not data.can_rest

func _render_details_view() -> void:
	panel_detailed_info.visible = true
	var profile_blurb = controller.selected_member.get("bio")
	$LeftColumn/DetailedInfoPanel/RichTextLabel.text = "[color=black]\n[i]%s[/i]\n[/color]" % profile_blurb

func _render_upgrade_view() -> void:
	panel_upgrade.visible = true
	var data = controller.get_upgrade_data()
	
	if data.max_tier_reached:
		$LeftColumn/UpgradePanel/InfoLabel.text = "[color=black]該成員已達到最高職業限界... (Max Tier Reached.)[/color]"
		$LeftColumn/UpgradePanel/UpgradeButton.disabled = true
		return
		
	var text = "[color=black]"
	text += "可晉升至 (Promotion Target): [b]%s[/b]\n" % data.next_title
	text += "等級需求 (Level Req): %d / [color=yellow]%d\n" % [data.current_level, data.req_level]
	text += "資金花費 (Cost): $%d (擁有: $%d)\n" % [data.cost, data.current_money]
	text += "[/color]"
	
	$LeftColumn/UpgradePanel/InfoLabel.text = text
	$LeftColumn/UpgradePanel/UpgradeButton.disabled = not data.can_upgrade

func _render_others_view() -> void:
	panel_others.visible = true
	$OthersPanel/WarningLabel.text = "⚠️ 警告: 您正在準備解除 [color=red]%s[/color] 的職務。\n解雇後該成員與其全部附帶裝備將被永久清除。" % controller.selected_member.name

# ==========================================
# 訊號與按鈕事件接尾 (UI Signal Event Handlers)
# ==========================================

func _on_equip_slot_focused(item_data: Dictionary) -> void:
	var desc = item_data.get("desc", "該裝備沒有詳細說明。")
	equip_desc_label.text = "[color=black]%s[/color]" % desc

func _on_tab_button_pressed(tab_index: int) -> void:
	current_active_tab = tab_index
	
	# 🔥 刪除原本 tab_index == 5 就 instantiate popup 的例外處理！
	# 現在它會直接順暢地進入 _refresh_active_tab_panel()
	_refresh_active_tab_panel()

func _on_tree_item_clicked() -> void:
	var selected_item = current_table.get_selected()
	if selected_item:
		var member_name = selected_item.get_text(0)
		controller.select_member_by_name(member_name)
		current_active_tab = 4 # 點選人頭時預設切回詳細資料分頁
		_refresh_entire_view()

# 點擊面板功能按鈕，直接派發命令給大腦
func _on_rest_button_pressed() -> void: controller.rest_current_member()
func _on_upgrade_button_pressed() -> void: controller.upgrade_current_member()
func _on_train_button_pressed_ui() -> void: controller.train_current_member() # 對應原 train 鈕
func _on_layoff_button_pressed() -> void: controller.layoff_current_member()
func _on_buy_equipment_button_pressed() -> void: controller.buy_equipment_for_member()

func _on_player_selection_selected(btn_name: String) -> void:
	if btn_name == "Return":
		done_managing.emit()

# ==========================================
# 輔助排版工具 (Layout Generaters)
# ==========================================

func _build_member_table_view(owner_band: Object) -> void:
	if current_table: current_table.queue_free()
	
	var table = Tree.new()
	current_table = table
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.global_position = table_position
	table.custom_minimum_size = Vector2(800, 400) 
	table.add_theme_font_size_override("font_size", 28)
	
	table.columns = 6
	var headers = ["Name", "Part", "Perf", "Stam", "Max HP", "HP"]
	for col in range(headers.size()):
		table.set_column_title(col, headers[col])
	table.column_titles_visible = true
	
	var root = table.create_item()
	table.hide_root = true
	
	for m in owner_band.members:
		var row = table.create_item(root)
		row.set_text(0, m.name)
		row.set_text(1, m.part)
		row.set_text(2, str(m.perf))
		row.set_text(3, str(m.stam))
		row.set_text(4, str(m.max_hp))
		row.set_text(5, str(m.hp))
		# 順便記住第一個走訪到的團員節點
		if first_member_item == null:
			first_member_item = row
		# 緩衝高亮選取狀態：如果剛才大腦記錄了這個人，表格重製時幫他點回去
		if controller.selected_member && m.name == controller.selected_member.name:
			row.select(0)
			
	for i in range(table.columns): table.set_column_expand(i, true)
	add_child(table)
	table.item_selected.connect(_on_tree_item_clicked)
	# 2. 自動點擊第一個人
	if not controller.has_selected_member() and first_member_item != null:
		# 先偷偷把名字餵給大腦，當作「我們已經選好了」
		var first_name = first_member_item.get_text(0)
		controller.select_member_by_name(first_name)
		
		# 這裡下達 select(0) 會觸發 _on_tree_item_clicked
		first_member_item.select(0)

func _update_character_icon(member_name: String) -> void:
	if not character_icon: return
	character_icon.texture = null
	if member_name == "": return
	
	var path = "res://assets/icons/%s.png" % member_name
	if ResourceLoader.exists(path):
		character_icon.texture = load(path)

func spawn_dynamic_tabs() -> void:
	for i in range(TAB_FILE_NAMES.size()):
		var tab_index = i + 1
		if not tabs_position.has(tab_index): continue
		var target_pos = tabs_position[tab_index]
		
		var tex_rect := TextureRect.new()
		tex_rect.name = "TabIcon_" + TAB_FILE_NAMES[i]
		tex_rect.global_position = target_pos
		tex_rect.custom_minimum_size = TAB_SIZE
		tex_rect.size = TAB_SIZE
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var path = "res://assets/tabs/%s.png" % TAB_FILE_NAMES[i]
		if ResourceLoader.exists(path): tex_rect.texture = load(path)
		add_child(tex_rect)
		
		var overlay_btn := Button.new()
		overlay_btn.name = "TabBtn_" + TAB_FILE_NAMES[i]
		overlay_btn.global_position = target_pos
		overlay_btn.custom_minimum_size = TAB_SIZE
		overlay_btn.size = TAB_SIZE
		overlay_btn.flat = true 
		overlay_btn.pressed.connect(_on_tab_button_pressed.bind(tab_index))
		add_child(overlay_btn)

func _initialize_mock_positions() -> void:
	var start_y = tabs_position_start.y
	var spacing_y = 75
	for i in range(1, 7):
		tabs_position[i] = Vector2(tabs_position_start.x, start_y + ((i - 1) * spacing_y))

func setup_ui():
	for marker in markers_parent.get_children():
		match marker.name:
			"Table": table_position = marker.global_position
			"Buttons": buttons_position = marker.global_position
			"TabPositions": tabs_position_start = marker.global_position
	setup_buttons()

func setup_buttons():
	var vbox_container = MemberActionVBoxContainer.new()
	vbox_container.button_pressed.connect(_on_player_selection_selected)
	add_child(vbox_container)
	vbox_container.global_position = buttons_position

func _render_equip_view() -> void:
	panel_equip.visible = true
	controller.select_equipment({}) # 每次切換進來時，預設不選取任何裝備
	
	# 初始化按鈕與文字狀態
	equip_buy_btn.disabled = true
	equip_desc_label.text = "請點擊列表中的裝備..."
	
	for child in equip_grid.get_children():
		child.queue_free()
		
	var items = controller.get_equipment_data()
	if items.is_empty():
		equip_desc_label.text = "目前沒有可用的裝備。"
		return
		
	for item_data in items:
		var slot = shop_slot_scene.instantiate()
		equip_grid.add_child(slot)
		slot.setup(item_data)
		
		# 滑鼠懸停：顯示介紹
		slot.slot_focused.connect(_on_equip_slot_focused)
		
		# 🔥 滑鼠點擊 (on element selected)：呼叫選取函數，並把資料綁定傳過去
		slot.pressed.connect(_on_equip_slot_selected.bind(item_data))

## 當玩家「點擊」某個 ShopSlot 時觸發
func _on_equip_slot_selected(item_data: Dictionary) -> void:
	# 1. 告訴大腦玩家選了什麼
	controller.select_equipment(item_data)
	
	# 2. 更新面板文字與按鈕狀態
	var cost = item_data.get("cost", 0)
	var desc = item_data.get("desc", "")
	
	var text = "[color=black]目標裝備: [b]%s[/b]\n" % item_data.get("name", "Unknown")
	text += "資金花費: $%d (擁有: $%d)\n\n" % [cost, controller.current_band.money]
	text += "%s[/color]" % desc
	equip_desc_label.text = text
	
	# 3. 如果錢夠，購買按鈕就會亮起；錢不夠就會反灰 disabled
	equip_buy_btn.disabled = not controller.can_buy_equipment()

## 渲染敵我樂團情報對比面板
func _render_band_comparison_view() -> void:
	panel_compare.visible = true
	
	# 1. 清空舊的表格內容
	compare_table.clear()
	compare_table.columns = 3
	compare_table.hide_root = true
	
	# 設定表頭
	compare_table.set_column_title(0, "情報項目")
	compare_table.set_column_title(1, "我方樂團")
	compare_table.set_column_title(2, "對手樂團")
	compare_table.column_titles_visible = true
	
	var root = compare_table.create_item()
	compare_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 2. 獲取雙方資料
	var my_band_id = GameStateBang.player
	var enemy_band_id = controller.current_band_id
	var my_band = GameStateBang.data.bands[my_band_id]
	var enemy_band = controller.current_band
	
	# 假設我們以當前大地圖玩家停駐的場地、或該對手佔領的代表性場地來計算總強度
	# 這裡先預設一個代表性的場地，或是從當前情境撈取的 venue_id
	var current_venue_id = "CiRCLE" 
	
	var my_strength = Global.event_facade.execute_action(
		Global.event_facade.get_band_strength_for_venue, [my_band_id, current_venue_id])
	var enemy_strength = Global.event_facade.execute_action(
		Global.event_facade.get_band_strength_for_venue, [enemy_band_id, current_venue_id])

	# 3. 定義要對比的資料列陣列
	var rows_data = [
		{"label": "💰 樂團資金", "my": "$%d" % my_band.money, "enemy": "$%d" % enemy_band.money},
		{"label": "📦 物資補給", "my": str(my_band.supply), "enemy": str(enemy_band.supply)},
		{"label": "⚔️ 預估總戰力", "my": str(my_strength), "enemy": str(enemy_strength)}
	]
	
	# 4. 填充表格資料
	for data in rows_data:
		var row = compare_table.create_item(root)
		row.set_text(0, data.label)
		row.set_text(1, data.my)
		row.set_text(2, data.enemy)
		
		# 視覺微調：如果是我方佔優勢的項目，把字體標成綠色；劣勢標成紅色
		if data.label == "⚔️ 預估總戰力":
			if my_strength > enemy_strength:
				row.set_custom_color(1, Color.GREEN)
				row.set_custom_color(2, Color.RED)
			elif my_strength < enemy_strength:
				row.set_custom_color(1, Color.RED)
				row.set_custom_color(2, Color.GREEN)
	compare_table.custom_minimum_size = Vector2(500, 400) 
	compare_table.add_theme_font_size_override("font_size", 20)
	# 讓欄位自動撐滿
	for i in range(3):
		compare_table.set_column_expand(i, true)
