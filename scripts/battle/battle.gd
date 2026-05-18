extends Control

var logbox
var data

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	general_vbox_initialize()
	logbox_generation()
	var attacker = GameStateBang.data.bands[GameStateBang.attacker]
	var defender = GameStateBang.data.bands[GameStateBang.defender]
	var venue = GameStateBang.data.worldMap[GameStateBang.current_venue]
	var ret = handle_battle(attacker, defender, venue)
	GameStateBang.data.bands[GameStateBang.attacker] = ret["attacker"]
	GameStateBang.data.bands[GameStateBang.defender] = ret["defender"]
	GameStateBang.data.worldMap[GameStateBang.current_venue] = ret["venue"]
	return
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func general_vbox_initialize():
	var vbox_container = BattleButtonVBoxContainer.new()
	vbox_container.button_pressed.connect(_on_player_selection_selected)
	add_child(vbox_container)
	vbox_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)

func _on_basic_button_pressed(name):
	match name:
		"Exit game":
			get_tree().quit()

func logbox_generation():
	logbox = RichTextLabel.new()
	logbox.name = "Dialogue"
	# Ensure it's big enough to see
	logbox.custom_minimum_size = Vector2(500, 150)
	logbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	logbox.bbcode_enabled = true
	logbox.scroll_following = true # Automatically scroll to the bottom
	logbox.text = "System Initialized..."
	logbox.show()
	add_child(logbox)

func handle_battle(attacker: Band, defender: Band, v: Venue):
	game_log("\n[b]==================================================[/b]", "yellow")
	game_log("  LIVE BATTLE: [b]%s[/b] vs [b]%s[/b]" % [attacker.band_name, defender.band_name], "white")
	game_log("  LOCATION: %s" % v.name, "white")
	game_log("[b]==================================================[/b]\n", "yellow")

	# Iterators to track which member is currently on stage
	var a_idx: int = 0
	var d_idx: int = 0

	# Battle continues as long as both bands have members with HP
	while a_idx < attacker.members.size() and d_idx < defender.members.size():
		var a_m = attacker.members[a_idx]
		var d_m = defender.members[d_idx]

		game_log(">>> CURRENT MATCHUP: [color=cyan]%s[/color] vs [color=red]%s[/color] <<<" % [a_m.name, d_m.name])

		while a_m.hp > 0 and d_m.hp > 0:
			# 1. Attacker Member strikes
			# Logic: max(8, (perf / 2) - (stam / 4) + rand % 15)
			var dmg_to_d = maxi(8, (a_m.perf / 2) - (d_m.stam / 4) + randi() % 15)
			d_m.hp -= dmg_to_d
			game_log("[INVADER] %s performs! %s HP: %d" % [a_m.name, d_m.name, maxi(0, d_m.hp)], "cyan")

			if d_m.hp <= 0:
				game_log(">> %s is exhausted and leaves the stage! <<" % d_m.name, "orange")
				break

			# 2. Defender Member strikes back
			var dmg_to_a = maxi(8, (d_m.perf / 2) - (a_m.stam / 4) + randi() % 15)
			a_m.hp -= dmg_to_a
			game_log("[DEFENDER] %s replies! %s HP: %d" % [d_m.name, a_m.name, maxi(0, a_m.hp)], "red")

			if a_m.hp <= 0:
				game_log(">> %s is exhausted and leaves the stage! <<" % a_m.name, "orange")
				break
				
			game_log("--------------------------------------------------")
		if(a_m.hp<=0): a_idx += 1
		if(d_m.hp<=0): d_idx += 1

	# --- Final Result Logic ---
	game_log("\n[b]==================================================[/b]", "yellow")
	if a_idx < attacker.members.size():
		game_log("  RESULT: VICTORY! %s cleared the stage!" % attacker.band_name, "green")
		game_log("  %d members still standing." % (attacker.members.size() - a_idx))
		
		# Transfer Venue Ownership
		defender.remove_venue(v)
		attacker.add_venue(v)
		v.owner = attacker
	else:
		game_log("  RESULT: DEFEAT... %s defended the venue!" % defender.band_name, "red")
		game_log("  %d members still standing." % (defender.members.size() - d_idx))
	game_log("[b]==================================================[/b]\n", "yellow")
	_reset_band_hp(attacker)
	_reset_band_hp(defender)
	var ret = {
		"attacker": attacker,
		"defender": defender,
		"venue": v
	}
	return ret

func _reset_band_hp(band: Band):
	for m in band.members:
		if(m.hp<0): m.hp = 0

func game_log(message: String, color: String = "white"):
	# [color=...] is BBCode for styling
	var formatted_text = "[color=%s]%s[/color]\n" % [color, message]
	
	logbox.append_text(formatted_text)
	
	# Also print to terminal so you have a backup for debugging
	print(message)

func _on_player_selection_selected(name):
	if name == "Return":
		get_tree().change_scene_to_file("res://scenes/main_game.tscn")
