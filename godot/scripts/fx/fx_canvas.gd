class_name FxCanvas
extends Node2D
## Tiny helper: a Node2D whose _draw() is delegated to a Callable (so fx.gd can own several draw layers).

var draw_fn: Callable


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
