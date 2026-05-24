extends VBoxContainer
class_name BandSelectionVBoxContainer

var bands
var selected_band_name

# 🛠️ 透過 Export 綁定右側的 UI 組件，讓左邊能直接遙控右邊
@export var banner_display: TextureRect
@export var intro_display: RichTextLabel
@export var confirm_button: Button

# 圖片與Banner的存放路徑（可根據你的專案結構調整）
const BANNER_PATH_TEMPLATE = "res://assets/logo/%s.png"

func _ready() -> void:
	# 防呆防線：確保此時 GameStateBang 已經被基本初始化（加載了基礎 JSON 資料）
	# 如果你的資料還在 config 裡，也可以改成 ConfigManager.load_config("STORY")["bands"]
	var data = GameStateBang._preload_static_bands()
	if data:
		bands = data
		generate_buttons(data)
	else:
		push_error("Selection Error: 找不到全域樂團資料庫，請確保開局配置已讀取！")
	confirm_button.pressed.connect(_on_confirm_pressed)
	intro_display.fit_content = true

## 動態根據 JSON 載入的樂團 Key 清單生成按鈕
func generate_buttons(bands: Array) -> void:
	# 先清空可能殘留的設計期假按鈕
	for child in get_children():
		child.queue_free()
		
	for band in bands:
		var b_name = band["name"]
		var new_btn := Button.new()
		new_btn.text = b_name
		new_btn.custom_minimum_size = Vector2(180, 45) # 給按鈕一個舒服的最小點擊尺寸
		
		# 連結按鈕點擊，傳入點擊的樂團名字
		new_btn.pressed.connect(func(): _on_band_selected(b_name))
		add_child(new_btn)


## 當玩家點擊左側其中一個樂團按鈕（不轉場，只展示）
func _on_band_selected(selected_band_name: String) -> void:
	# 1. 核心暫存：先把玩家選定的對象記在 GameState 全域變數中
	GameStateBang.player = selected_band_name
	print("🎯 [Selection] 玩家選取了：", selected_band_name)
	
	# 2. 獲取該樂團物件，動態組裝介紹內文
	var band_obj
	for band in bands:
		if(band["name"] == selected_band_name):
			band_obj = band
			break
	var intro_text = "[b][font_size=24]%s[/font_size][/b]\n\n" % selected_band_name
	intro_text += "[color=gray]初始團員名冊：[/color]\n"
	
	# 走訪成員列表，把動態數值亮給玩家看
	for m in band_obj["members"]:
		intro_text += "• [b]%s[/b] (%s) - Perf: %d | Stam: %d\n" % [m["name"], m["part"], m["perf"], m["stam"]]
		
	# 3. 刷新右側 UI 顯示
	if intro_display:
		intro_display.text = intro_text
		
	# 4. 動態更換 Banner 橫幅
	if banner_display:
		# 預防符號衝突（如 Pastel*Palettes 轉檔名可能變 Pastel_Palettes）
		var safe_name = selected_band_name.replace("*", "_")
		var full_path = BANNER_PATH_TEMPLATE % safe_name
		
		if ResourceLoader.exists(full_path):
			banner_display.texture = load(full_path)
		else:
			banner_display.texture = null # 沒圖就清空或放預設 placeholder
			
	# 5. 既然玩家已經明確選了一個團，右下角的 Confirm 按鈕終於解鎖！
	if confirm_button:
		confirm_button.disabled = false
		confirm_button.text = "帶著 %s 出征！" % selected_band_name
	self.selected_band_name = selected_band_name

func _on_confirm_pressed() -> void:
	GameStateBang.player = selected_band_name
	if GameStateBang.player != "":
		print("🚀 [System] 最終鎖定樂團！正在進入大江戶征服大地圖...")
		get_tree().change_scene_to_file("res://scenes/main_game.tscn")
