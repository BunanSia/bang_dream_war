class_name MainGameUI
extends Node

const logo_path = "res://assets/logo"

@export var markers_parent: Node2D
@export var button_container: Control
@export var flag_container: Node2D
@export var dialogue_ui: CanvasLayer
@export var furniture_icon_container: Control

@export var line_container: Node2D
@export var selection_box: VBoxContainer
@export var data_label: Label
@export var logbox: RichTextLabel

var actionvbox: Control

signal basic_button_pressed(action_name: String)
signal venue_button_pressed(venue_name: String)
signal player_selection_confirmed(selection: String)
signal enemy_selection_confirmed(action_name: String)

func _ready() -> void:
	general_vbox_initialize()
	logbox_generation()

func logbox_generation() -> void:
	logbox = RichTextLabel.new()
	logbox.name = "Dialogue"
	logbox.custom_minimum_size = Vector2(1000, 500)
	logbox.fit_content = true
	logbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	logbox.bbcode_enabled = true
	logbox.scroll_following = true 
	add_child(logbox)
	logbox.show()

func game_log(message: String, color: String = "white") -> void:
	var formatted_text = "[color=%s]%s[/color]\n" % [color, message]
	if logbox:
		logbox.append_text(formatted_text)
	print(message)

func generate_venue_buttons() -> void:
	if not markers_parent or not button_container or not flag_container:
		push_error("UI Error: Missing inspectors assignments.")
		return
		
	for child in button_container.get_children():
		child.queue_free()
	for child in flag_container.get_children():
		child.queue_free()
	for marker in markers_parent.get_children():
		if marker is Marker2D:
			var venue_name: String = marker.name
			var btn := Button.new()

			var texture := TextureRect.new()
			var owner = GameStateBang.data.worldMap[venue_name].owner.band_name
			owner = owner.replace("*", "_")
			var texture_path = logo_path + "/%s.png" % owner
			if ResourceLoader.exists(texture_path):
				var new_texture = load(texture_path)
				texture.texture = new_texture
				texture.global_position = marker.global_position
			flag_container.add_child(texture)

			# Get base sizes
			var tex_size = texture.texture.get_size()
			var rect_size = texture.get_size()

			# Calculate dynamic width and height maintaining aspect ratio
			var scale_factor = min(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
			var dynamic_width = tex_size.x * scale_factor
			var dynamic_height = tex_size.y * scale_factor

			btn.custom_minimum_size = Vector2(dynamic_width, dynamic_height)
			btn.self_modulate.a = 0.2
			btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
			btn.grow_vertical = Control.GROW_DIRECTION_BOTH
			btn.global_position = marker.global_position
			btn.pressed.connect(func(): venue_button_pressed.emit(venue_name))
			button_container.add_child(btn)
	_draw_map_edges()

func general_vbox_initialize() -> void:
	var vbox_container = BasicGameButtonsHBoxContainer.new()
	add_child(vbox_container)
	vbox_container.generate_buttons()
	vbox_container.button_pressed.connect(func(id): basic_button_pressed.emit(id))

func show_data():
	var ap_point = "Action:" + "%s" % GameStateBang.data.bands[GameStateBang.current_band].current_action_points + "\n"
	var supply = "Supply:" + "%s" % GameStateBang.data.bands[GameStateBang.current_band].supply + "\n"
	var money = "Money:" + "%s" % GameStateBang.data.bands[GameStateBang.current_band].money + "\n"
	var venue = "City:" + "%s" % GameStateBang.current_venue + "\n"
	var band = "Band:" + "%s" % GameStateBang.current_band + "\n"
	data_label.text = ap_point + supply + money + venue + band
	if(GameStateBang.current_band != GameStateBang.player):
		var rel = "Relation:" + "%s" % GameStateBang.data.bands[GameStateBang.player].get_relation(GameStateBang.current_band)
		data_label.text += rel
	data_label.set("theme_override_font_sizes/font_size", 24)

func show_player_selection(player_id: String) -> void:
	_refresh_ui()
	actionvbox = PlayerSelectionVBoxContainer.new()
	actionvbox.establish(player_id)
	actionvbox.button_pressed.connect(func(sel): player_selection_confirmed.emit(sel))
	selection_box.add_child(actionvbox)
	show_data()

func show_enemy_selection(owner_name: String, relation_label: String) -> void:
	_refresh_ui()
	actionvbox = OtherBandSelectionVBoxContainer.new()
	actionvbox.establish("%s(%s)" % [owner_name, relation_label])
	actionvbox.button_pressed.connect(func(act): enemy_selection_confirmed.emit(act))
	selection_box.add_child(actionvbox)
	show_data()

func update_selection_label(new_text: String) -> void:
	if actionvbox and actionvbox.has_method("set_label"):
		actionvbox.set_label(new_text)

func _refresh_ui() -> void:
	if actionvbox:
		actionvbox.queue_free()
		actionvbox = null

# Inside MainGameUI.gd

## Updates the visual layout to display icons for all furniture installed at the venue
func refresh_venue_furniture_icons(installed_furniture: Array) -> void:
	# 1. Clear out previous icons from old selections
	for child in furniture_icon_container.get_children():
		child.queue_free()
		
	# 2. If the venue has no upgrades, you can show a label or just leave it empty
	if installed_furniture.is_empty():
		return
		
	# 3. Loop through each furniture item object present at this location
	for item in installed_furniture:
		var tex_rect := TextureRect.new()
		
		# Configure layout rules so icons scale nicely inside your HBoxContainer
		tex_rect.custom_minimum_size = Vector2(40, 40) # Set to your desired icon resolution
		tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		
		# Define path mapping pointing to your dynamic asset database structure
		var asset_path = "res://assets/furniture/%s.png" % item.item_name
		
		if ResourceLoader.exists(asset_path):
			tex_rect.texture = load(asset_path)
		else:
			# Fallback placeholder asset if an icon file is missing
			tex_rect.texture = load("res://assets/furniture/placeholder_building.png")
			
		# Optional: Add a simple tooltip hint so hovering the mouse reveals the name/stats
		tex_rect.tooltip_text = "%s\n+%d HP Recovery" % [item.item_name, item.hp_recovery_bonus]
		
		# 4. Commit to the visual scene layout tree
		furniture_icon_container.add_child(tex_rect)

## 動態根據鄰接矩陣在 Marker 之間繪製 Line2D
func _draw_map_edges() -> void:
	# 先清空可能殘留的舊線條（防呆）
	for child in line_container.get_children():
		child.queue_free()
		
	var venues_count = GameStateBang.adjacency_matrix.size()
	
	# 建立一個臨時陣列，用 Index 快速反查對應的 Marker2D 節點
	# 這樣待會畫線時就不用一直用字串翻箱倒櫃
	var marker_lookup = {}
	for marker in markers_parent.get_children():
		if marker is Marker2D:
			var v_name = marker.name
			if GameStateBang.venue_indices.has(v_name):
				var idx = GameStateBang.venue_indices[v_name]
				marker_lookup[idx] = marker
	# 🎯 開始遍歷鄰接矩陣
	for i in range(venues_count):
		for j in range(venues_count):
			# 💡 關鍵優化：只在 j > i 時才畫，確保 A<->B 之間只會有一條 Line2D 實例
			if j > i:
				# 如果矩陣記錄為 1，代表這兩個 Index 對應的場地有連線
				if GameStateBang.adjacency_matrix[i][j] == 1:
					var marker_a = marker_lookup.get(i)
					var marker_b = marker_lookup.get(j)
					
					if marker_a and marker_b:
						# 呼叫畫線工廠，把這兩點連起來
						_create_line_between(marker_a.global_position, marker_b.global_position)

## 建立單條 Line2D 的工廠函數
func _create_line_between(pos_a: Vector2, pos_b: Vector2) -> void:
	var line := Line2D.new()
	
	# 1. 塞入起點與終點的 global_position
	line.add_point(pos_a)
	line.add_point(pos_b)
	
	# 2. 🎨 樣式與外觀設定 (你可以根據獨立樂團的風格自由調整)
	line.width = 2.0                                # 線條粗細
	line.default_color = Color("ff4570", 0.6)       # 帶有一點透明度的粉紅/桃紅色霓虹感
	line.antialiased = true                         # 開啟抗鋸齒，讓斜線不毛躁
	
	# 3. 讓線條的頭尾變成圓角，看起來更精緻
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# 塞進地圖的線條圖層中
	line_container.add_child(line)
