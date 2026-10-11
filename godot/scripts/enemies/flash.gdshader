shader_type canvas_item;
render_mode unshaded;
// White hit-flash overlay: white where the sprite is opaque, alpha scaled by modulate.
void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);
}
