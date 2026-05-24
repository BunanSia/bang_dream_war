extends HBoxContainer

class_name BasicGameButtonsHBoxContainer

signal button_pressed(event_name)

# The list of labels for your buttons
var data
var basic_buttons = ["Victory", "Save", "Policy", "Recruit", "Check member", "End turn", "Exit game"]

func _ready():
	pass

func generate_buttons():
	for basic_btn in basic_buttons:
		# 1. Create a new Button instance
		var new_btn = Button.new()
		# 2. Set the text
		new_btn.text = basic_btn
		
		# 3. Connect the "pressed" signal using a lambda
		# This allows us to pass the specific text to the function
		new_btn.pressed.connect(func(): _on_button_pressed(basic_btn))
		# 4. Add it to the scene tree (as a child of this container)
		add_child(new_btn)

func _on_button_pressed(name):
	button_pressed.emit(name)
