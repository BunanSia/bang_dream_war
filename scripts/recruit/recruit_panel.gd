# RecruitPanel.gd
extends Control

@onready var member_grid: GridContainer = $ListScroll/GridContainer
@onready var avatar_rect: TextureRect = $ProfilePanel/Avatar
@onready var name_label: Label = $ProfilePanel/NameLabel
@onready var info_label: RichTextLabel = $ProfilePanel/InfoLabel
@onready var recruit_button: Button = $ProfilePanel/RecruitButton
@onready var close_button: Button = $FooterPanel/CloseButton

signal done_recruitment()
var selected_member_data: Dictionary = {}
# 🔥 更換為專屬的招募控制器
var controller: RecruitController

func _ready() -> void:
	recruit_button.pressed.connect(_on_recruit_pressed)
	close_button.pressed.connect(_on_return_pressed)
	
	# 🔥 初始化專屬招募大腦
	controller = RecruitController.new()
	add_child(controller)
	
	# 監聽招募大腦的刷新訊號
	controller.recruit_market_refreshed.connect(_on_market_refreshed)
	
	_build_recruit_list()

## 建立自由成員卡片清單
func _build_recruit_list() -> void:
	for child in member_grid.get_children():
		child.queue_free()
		
	var pool = controller.get_available_recruits()
	if pool.is_empty():
		name_label.text = "空空如也"
		info_label.text = "[color=gray]目前地圖上沒有流浪的樂手...[/color]"
		info_label.fit_content = true
		recruit_button.disabled = true
		avatar_rect.texture = load("res://assets/icons/default.png")
		return
		
	for member_data in pool:
		var card = Button.new()
		card.text = "%s (%s)" % [member_data.name, member_data.part]
		card.custom_minimum_size = Vector2(250, 60)
		# 點擊卡片時，切換選取狀態
		card.pressed.connect(_on_member_card_selected.bind(member_data))
		member_grid.add_child(card)
		
	# 預設自動選取市場第一個自由人
	_on_member_card_selected(pool[0])

## 當點選某個自由團員時，更新右側詳細預覽面板
func _on_member_card_selected(member_data: Dictionary) -> void:
	selected_member_data = member_data
	
	# 1. 渲染頭像
	if ResourceLoader.exists(member_data.avatar):
		avatar_rect.texture = load(member_data.avatar)
	else:
		avatar_rect.texture = load("res://assets/icons/default.png")
		
	# 2. 渲染名字與詳細數據
	name_label.text = member_data.name
	
	var text = "[color=black]"
	text += "樂器專長: [b]%s[/b]\n" % member_data.part
	text += "演奏表現 (Perf): %d\n" % member_data.perf
	text += "耐力係數 (Stam): %d\n" % member_data.stam
	text += "合約聘金: [color=gold]$%d[/color]\n" % member_data.cost
	text += "消耗行動點: %d AP\n\n" % member_data.ap_cost
	text += "背景簡介:\n%s" % member_data.desc
	text += "[/color]"
	info_label.text = text
	
	# 3. 🧠 透過專屬大腦精確判斷這個人能不能買
	recruit_button.disabled = not controller.can_recruit_member(member_data)

## 按下招募按鈕
func _on_recruit_pressed() -> void:
	if not selected_member_data.is_empty():
		controller.recruit_member(selected_member_data)

## 當有人被成功招募、市場洗牌時觸發
func _on_market_refreshed() -> void:
	_build_recruit_list()

func _on_return_pressed() -> void:
	done_recruitment.emit()
