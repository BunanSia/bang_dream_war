# BandPolicyPanel.gd
extends Control

# 宣告完成訊號供 Facade 監聽
signal policy_confirmed

# 1. 只需要綁定存放按鈕的動態容器節點
@onready var goal_container: Container = $VBoxContainer/GoalSection/ButtonContainer
@onready var type_container: Container = $VBoxContainer/TypeSection/ButtonContainer
@onready var confirm_button: Button = $ConfirmButton

# 2. 未來要擴充或改成讀 JSON，只需要修改這兩個資料陣列即可 🚀
var available_goals: Array[String] = [
	"大少女樂團時代", 
	"future world festival"
]

var available_types: Array[String] = [
	"學校社團", 
	"地下樂團", 
	"國際天團"
]

# 暫存玩家當前的選取狀態
var selected_goal: String = ""
var selected_type: String = ""

func _ready() -> void:
	# 連結確認按鈕
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = true
	
	# 讀取玩家樂團當前的方針，作為初始選取比對
	var player_band = GameStateBang.data.bands[GameStateBang.player]
	selected_goal = player_band.get("goal")
	selected_type = player_band.get("type")
	
	# 開始動態刻畫 UI 身體
	_spawn_policy_buttons(available_goals, goal_container, "goal")
	_spawn_policy_buttons(available_types, type_container, "type")
	
	# 初始檢查確認按鈕狀態
	_check_confirm_availability()


## 通用的動態按鈕生成工廠
func _spawn_policy_buttons(items: Array, container: Node, type_category: String) -> void:
	# 先清空編輯器中可能殘留的預覽節點
	for child in container.get_children():
		child.queue_free()
		
	for item_name in items:
		var btn = Button.new()
		btn.text = item_name
		btn.custom_minimum_size = Vector2(200, 50)
		
		# 檢查這個按鈕是不是玩家目前正記錄在案的方針，如果是，幫它亮起
		if type_category == "goal" and item_name == selected_goal:
			btn.modulate = Color(1.2, 1.5, 1.2) # 亮綠色
		elif type_category == "type" and item_name == selected_type:
			btn.modulate = Color(1.2, 1.5, 1.2) # 亮綠色
			
		# 綁定點擊事件，利用 bind 傳遞類別與自身指標
		btn.pressed.connect(_on_policy_button_pressed.bind(item_name, container, type_category))
		
		container.add_child(btn)


## 統一處理所有動態按鈕的點擊事件
func _on_policy_button_pressed(selected_value: String, parent_container: Node, type_category: String) -> void:
	# 1. 記憶當前選取字串
	if type_category == "goal":
		selected_goal = selected_value
	elif type_category == "type":
		selected_type = selected_value
		
	# 2. 視覺排他回饋：讓同一個 Container 底下的兄弟按鈕全部熄滅，只亮起點擊的那一個
	for btn in parent_container.get_children():
		if btn is Button:
			if btn.text == selected_value:
				btn.modulate = Color(1.2, 1.5, 1.2) # 選中的變亮綠色
			else:
				btn.modulate = Color(1.0, 1.0, 1.0) # 其他變回原色
				
	# 3. 檢查確認鈕是否解鎖
	_check_confirm_availability()

## 檢查確認按鈕可用性
func _check_confirm_availability() -> void:
	confirm_button.disabled = (selected_goal == "" or selected_type == "")

## 按下確認，修改資料流並發射訊號
func _on_confirm_pressed() -> void:
	if selected_goal == "" or selected_type == "": return
	
	# 透過事件門面更新數據
	Global.event_facade.execute_action(
		Global.event_facade.update_band_policy,
		[GameStateBang.player, selected_goal, selected_type]
	)
	
	# 發射訊號交給 Facade 統一回收
	policy_confirmed.emit()
