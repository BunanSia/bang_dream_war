extends Control

# References to the buttons (Optional, but good for styling)
@onready var new_game_btn = $MarginContainer/VBoxContainer/NewGameBtn
@onready var continue_btn = $MarginContainer/VBoxContainer/ContinueBtn
@onready var exit_btn = $MarginContainer/VBoxContainer/ExitBtn

func _ready():
	# Connect the signals
	pass

func _on_continue_pressed():
	# Logic for loading GameState from a file would go here
	load_game()

func load_game():
	print("Loading Game...")

func _on_exit_pressed():
	print("Exiting Game...")
	get_tree().quit() # Replaces: gaming = false

func setup_initial_game_state():
	# Reset GameState singleton for a fresh run
	print("Initialize new game")
	get_tree().change_scene_to_file("res://scenes/plot_selection.tscn")
	# ... etc

func _on_new_game_pressed() -> void:
	# Replaces: Select your Band logic
	# You can transition to a 'Band Selection' screen or start directly
	setup_initial_game_state()
