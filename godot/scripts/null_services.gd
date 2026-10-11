class_name NullFx
extends Node
## No-op juice API so systems can call game.fx.* before the real FX system is loaded.
func shake(_amount: float, _duration := 0.25) -> void: pass
func hitstop(_seconds: float) -> void: pass
func flash(_color: Color, _seconds := 0.15) -> void: pass
func float_text(_world_px: Vector2, _text: String, _color := Color.WHITE) -> void: pass
func burst(_world_px: Vector2, _kind: String, _dir := Vector2.ZERO) -> void: pass
func blood(_world_px: Vector2, _size := 1.0) -> void: pass
