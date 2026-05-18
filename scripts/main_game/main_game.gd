extends Node

@onready var ui: MainGameUI = $UI/MainGameUI

var data
var event_facade: GameEventFacade

func _ready() -> void:
	if not GameStateBang.data:
		GameStateBang.data = GameInitializer.bootstrap(PlotMode.PlotMode.STORY)
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

func start_invasion(target: String) -> void:
	ui.game_log("--- Select a target to invade ---", "red")
	GameStateBang.attacker = GameStateBang.player
	GameStateBang.defender = data.worldMap[target].owner.band_name
	var attacker = data.bands[GameStateBang.player]
	var defender = data.worldMap[target].owner
	# get_tree().change_scene_to_file("res://scenes/battle.tscn")
	deploy_live_battle_sequence(attacker, defender,
								data.worldMap[target])

# Inside your GameEngine.gd or map controller where invasion is triggered

func deploy_live_battle_sequence(attacker: Band, defender: Band, v: Venue) -> void:
	# Load the combat scene overlay system layout
	var battle_scene = load("res://scenes/live_battle_scene.tscn").instantiate()
	
	# Add it to the tree first so its @onready nodes initialize
	get_tree().root.add_child(battle_scene)
	
	# Fire the interactive controller pipeline setup routine
	battle_scene.start_interactive_battle(attacker, defender, v)

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
			GameStateBang.next_turn()
			process_turn_rollover()

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
			get_tree().change_scene_to_file("res://scenes/member_panel.tscn")
		"Purchase":
			# Inside your Main Map View / GameEngine.gd
			open_furniture_shop()

func open_furniture_shop() -> void:
	var shop_scene = preload("res://scenes/furniture_shop.tscn")
	var shop_instance = shop_scene.instantiate()

	# Add it on top of the screen layout
	add_child(shop_instance)
func _on_ui_enemy_choice(action: String) -> void:
	match action:
		"Check members":
			get_tree().change_scene_to_file("res://scenes/member_panel.tscn")
		"対バン":
			start_invasion(GameStateBang.current_venue)
		"Challenge":
			# Route standard player actions directly through the facade interface!
			event_facade.set_band_relations(GameStateBang.player, GameStateBang.current_band, "Rival")
			var new_rel = data.bands[GameStateBang.player].get_relation(GameStateBang.current_band)
			ui.update_selection_label("%s(%s)" % [GameStateBang.current_band, new_rel])
		"Cooperate":
			# Route standard player actions directly through the facade interface!
			event_facade.set_band_relations(GameStateBang.player, GameStateBang.current_band, "Allied")
			var new_rel = data.bands[GameStateBang.player].get_relation(GameStateBang.current_band)
			ui.update_selection_label("%s(%s)" % [GameStateBang.current_band, new_rel])

func process_turn_rollover() -> void:
	GameStateBang.turn += 1
	
	for band_name in data.bands:
		var band: Band = data.bands[band_name]
		
		# 1. Count how many venues they own in the global map state database
		var controlled_venues = band.venues.size()
		
		# 2. Re-calculate action budget for the new round
		band.refresh_turn_actions(controlled_venues)
		
		# 3. Trigger individual stamina / performance growth gains
		band.process_turn_recovery(data.worldMap)
	process_events()
