# BattlePreparation.gd
extends Control
class_name BattlePreparation

# 變更信號：改為直接把完整的戰鬥封包拋給 Facade
signal preparation_completed(battle_config: Dictionary)

@onready var member_list_vbox: VBoxContainer = $LeftPanel/MemberListVBox
@onready var team_preview_label: RichTextLabel = $RightPanel/TeamPreviewLabel
@onready var venue_label: Label = $RightPanel/VenueLabel
@onready var confirm_button: Button = $RightPanel/ConfirmSelectionButton

var attacker_band: Band
var defender_band: Band
var current_venue: Venue

# 最終決定的舞台名冊
var final_attacker_team: Array = []
var final_defender_team: Array = []

const TEAM_SIZE_LIMIT = 5

func _ready() -> void:
	var world_map = GameStateBang.data.worldMap
	var bands_db = GameStateBang.data.bands
	
	current_venue = world_map.get(GameStateBang.current_venue)
	attacker_band = bands_db.get(GameStateBang.attacker)
	defender_band = bands_db.get(GameStateBang.defender)
	
	venue_label.text = "🏟️ 當前舞台：%s (%s)" % [current_venue.name, current_venue.type]
	confirm_button.pressed.connect(_on_confirm_selection_button_pressed)
	# 🚀 啟動清晰乾淨的兩段式陣容決定流
	_process_team_selection()


# ==========================================
# 🛠️ 核心重構：進攻/防守解耦，完美相容雙 AI 對決
# ==========================================
func _process_team_selection() -> void:
	var player_name = GameStateBang.player
	var need_player_ui: bool = false
	var target_band_for_ui: Band = null
	
	# 1. 獨立評估進攻方 (Attacker)
	if attacker_band.band_name == player_name:
		need_player_ui = true
		target_band_for_ui = attacker_band
	else:
		final_attacker_team = _auto_select_ai_team(attacker_band, TEAM_SIZE_LIMIT)
		
	# 2. 獨立評估防守方 (Defender)
	if defender_band.band_name == player_name:
		need_player_ui = true
		target_band_for_ui = defender_band
	else:
		final_defender_team = _auto_select_ai_team(defender_band, TEAM_SIZE_LIMIT)
		
	# 3. 根據評估結果，決定要不要生出 UI，或者直接全自動跳過
	if need_player_ui and target_band_for_ui:
		_generate_player_selection_ui(target_band_for_ui)
		_update_preview_ui()
	else:
		# 🔥 核心亮點：如果攻守雙方都是 AI，UI 連顯示都不用，直接閉眼自動確認出局！
		print("🤖 [觀戰模式] 偵測到雙 AI 對決，跳過 UI 選擇，直接啟動自動結算！")
		_on_confirm_selection_button_pressed()


func _auto_select_ai_team(npc_band: Band, count: int) -> Array:
	var team = []
	var alive_members = npc_band.members.filter(func(m): return m.hp > 0)
	alive_members.sort_custom(func(a, b): return a.perf > b.perf)
	
	for i in range(min(count, alive_members.size())):
		team.append(alive_members[i])
	return team


func _generate_player_selection_ui(p_band: Band) -> void:
	for child in member_list_vbox.get_children(): child.queue_free()
	
	for member in p_band.members:
		if member.hp <= 0: continue
		
		var check_box = CheckBox.new()
		check_box.text = "%s (%s) | Perf: %d" % [member.name, member.part, member.perf]
		check_box.toggled.connect(func(is_checked: bool): _on_member_toggled(member, is_checked, check_box, p_band))
		check_box.custom_minimum_size = Vector2(200,100)
		member_list_vbox.add_child(check_box)


func _on_member_toggled(member: Object, is_checked: bool, box_node: CheckBox, p_band: Band) -> void:
	# 決定玩家現在填寫的是進攻表格還是防守表格
	var target_array = final_attacker_team if p_band == attacker_band else final_defender_team
	
	if is_checked:
		if target_array.size() >= TEAM_SIZE_LIMIT:
			box_node.button_pressed = false
			return
		if not target_array.has(member): target_array.append(member)
	else:
		target_array.erase(member)
		
	_update_preview_ui()

func _update_preview_ui() -> void:
	var player_name = GameStateBang.player
	var is_player_attacker = (attacker_band.band_name == player_name)
	var my_team = final_attacker_team if is_player_attacker else final_defender_team
	
	var text = "[b]💡 預計登場陣容：[/b]\n\n"
	for m in my_team:
		text += "• [color=cyan]%s[/color] (%s)\n" % [m.name, m.part]
		
	team_preview_label.text = text
	team_preview_label.fit_content = true
	team_preview_label.custom_minimum_size = Vector2(300,200)
	var max_allowed = min(TEAM_SIZE_LIMIT, (attacker_band if is_player_attacker else defender_band).members.size())
	confirm_button.disabled = (my_team.size() > max_allowed or (my_team.size() == 0 and is_team_alive(my_team)))

func is_team_alive(attack_member: Array):
	for member in attack_member:
		if member.hp <= 0: continue
		else: return true
	return false

# ==========================================
# 🚀 點擊確認：打包成一個字典，直接發射給 Facade
# ==========================================
func _on_confirm_selection_button_pressed() -> void:
	# 將所有上下文與選好的名單包裝成單一 Parcel
	var battle_packet = {
		"attacker_band": attacker_band,
		"defender_band": defender_band,
		"target_venue": current_venue,
		"attacker_team": final_attacker_team,
		"defender_team": final_defender_team
	}
	
	# 🎯 直接丟給全域 Event Facade (或者透過信號向上通知主控)
	if Global.event_facade.has_method("on_battle_roster_ready"):
		Global.event_facade.on_battle_roster_ready(battle_packet)
	else:
		# 備用：拋出訊號讓掛載你的大地圖聽
		emit_signal("preparation_completed", battle_packet)
