extends VBoxContainer

class_name PlotSelectionVBoxContainer

# The list of labels for your buttons
var button_labels = ["STORY", "FREEPLAY", "TUTORIAL"]

func _ready():
	generate_buttons()

func generate_buttons():
	for text in button_labels:
		# 1. Create a new Button instance
		var new_btn = Button.new()
		
		# 2. Set the text
		new_btn.text = text
		
		# 3. Connect the "pressed" signal using a lambda
		# This allows us to pass the specific text to the function
		new_btn.pressed.connect(func(): _on_button_pressed(text))
		
		# 4. Add it to the scene tree (as a child of this container)
		add_child(new_btn)

func _on_button_pressed(label):
	GameStateBang.plot_mode = label
	get_tree().change_scene_to_file("res://scenes/band_selection.tscn")
