shader_type canvas_item;
// Port of shaders.lua (post, haze, dust mask) + render.lua cfg, plus sanity/HP driven effects.
// Full-screen pass on a high CanvasLayer. Compatibility-renderer safe: one screen-texture read
// (plus two more for chromatic aberration only when it is active).
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float time = 0.0;
// render.lua cfg
uniform float grain_amount : hint_range(0.0, 0.2) = 0.020;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.20;
uniform float desat : hint_range(0.0, 1.0) = 0.08;
uniform float contrast : hint_range(0.7, 1.4) = 1.05;
uniform float exposure : hint_range(0.6, 1.6) = 1.12;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.10;
uniform float haze_alpha : hint_range(0.0, 1.0) = 0.025;
uniform float haze_parallax : hint_range(0.0, 1.0) = 0.14;
uniform vec2 cam_px = vec2(0.0);
uniform float dust_intensity : hint_range(0.0, 2.0) = 0.55;
// game-state driven
uniform float sanity_fx : hint_range(0.0, 1.0) = 0.0;     // 0 at >=25% sanity, 1 at 0%  (VCR tracking)
uniform float sanity_tint : hint_range(0.0, 1.0) = 0.0;   // purple edge below 40% sanity
uniform float hp_danger : hint_range(0.0, 1.0) = 0.0;     // low-HP red vignette
uniform float heartbeat : hint_range(0.0, 1.0) = 0.0;     // pulses the vignette (0..1 envelope)
uniform float hit_pulse : hint_range(0.0, 1.0) = 0.0;     // damage taken, decays in script
uniform float aberration : hint_range(0.0, 1.0) = 0.0;    // extra chromatic aberration (hits, insanity)
uniform float slowmo : hint_range(0.0, 1.0) = 0.0;        // near-miss slow-mo: desaturate + punch contrast
uniform vec4 shock = vec4(0.5, 0.5, 0.0, 0.0);            // shockwave: centre uv, ring radius (uv.y units), strength (0 = off)
uniform vec4 shock2 = vec4(0.5, 0.5, 0.0, 0.0);           // second concurrent shockwave
uniform float flicker = 0.0;                              // 0..1 low-sanity light stutter (multiplies exposure down)

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// drifting dust motes: one candidate per cell, only visible where the scene is bright (headlamp)
float dust(vec2 uv, vec2 aspect, float t) {
	float acc = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		vec2 g = (uv * aspect * (9.0 + fl * 7.0)) + vec2(t * (0.03 + fl * 0.02), -t * (0.02 + fl * 0.015));
		vec2 id = floor(g);
		vec2 f = fract(g);
		float h = hash21(id + fl * 17.0);
		vec2 pos = vec2(0.5) + 0.35 * vec2(sin(t * (0.4 + h) + h * 6.28), cos(t * (0.5 + h) + h * 9.0));
		float d = length(f - pos);
		float r = 0.045 + 0.03 * fract(h * 7.0);
		float on = step(0.55, h);
		acc += on * smoothstep(r, r * 0.3, d) * (0.6 + 0.4 * sin(t * 2.0 + h * 40.0));
	}
	return acc;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 aspect = vec2(res.x / res.y, 1.0);

	// ---- sanity: VCR tracking wobble (horizontal displacement bands) ----
	float shift = 0.0;
	if (sanity_fx > 0.0) {
		float band = floor(uv.y * (20.0 + sanity_fx * 40.0));
		float bh = hash21(vec2(band, floor(time * (4.0 + sanity_fx * 8.0))));
		shift += (bh - 0.5) * step(0.82 - sanity_fx * 0.25, bh) * 0.03 * sanity_fx;
		shift += sin(uv.y * 40.0 + time * 6.0) * 0.0015 * sanity_fx;
		// rolling bar
		float roll_speed = 0.4 + sanity_fx * 0.8;
		float roll_y = fract(time * roll_speed * 0.7);
		float rd = 1.0 - clamp(abs(uv.y - roll_y) / (0.03 + sanity_fx * 0.05), 0.0, 1.0);
		shift += rd * 0.004 * sanity_fx * sin(time * 30.0);
	}
	uv.x += shift;

	// ---- low sanity: slow breathing warp of the whole image (grows as sanity falls) ----
	if (sanity_tint > 0.0) {
		float w = sanity_tint * sanity_tint * 0.0045 + sanity_fx * 0.002;
		uv += vec2(sin(uv.y * 17.0 + time * 1.7), cos(uv.x * 13.0 + time * 1.3)) * w;
	}

	// ---- shockwaves (bomb): refract the image around an expanding ring ----
	for (int i = 0; i < 2; i++) {
		vec4 sw = i == 0 ? shock : shock2;
		if (sw.w > 0.0) {
			vec2 sd = (uv - sw.xy) * vec2(aspect.x, 1.0);
			float sl = length(sd);
			float ring = sl - sw.z;
			float prof = exp(-ring * ring * 380.0) * sw.w;
			uv -= normalize(sd + vec2(0.0001)) * prof * 0.045 / vec2(aspect.x, 1.0);
		}
	}

	// ---- heartbeat / hit "breathing" zoom toward the centre ----
	vec2 dc = uv - vec2(0.5);
	float zoom = heartbeat * 0.006 + hit_pulse * 0.012;
	uv = vec2(0.5) + dc * (1.0 - zoom);

	// ---- chromatic aberration (radial) ----
	float ab = aberration * 0.006 + hit_pulse * 0.004 + sanity_fx * 0.004;
	vec3 c;
	if (ab > 0.0004) {
		vec2 dir = (uv - vec2(0.5)) * (0.4 + length(uv - vec2(0.5)) * 1.6);
		c.r = texture(screen_tex, uv + dir * ab * 1.5).r;
		c.g = texture(screen_tex, uv).g;
		c.b = texture(screen_tex, uv - dir * ab * 1.5).b;
	} else {
		c = texture(screen_tex, uv).rgb;
	}

	c *= exposure * (1.0 - flicker * 0.55);

	// ---- haze: slow low-frequency luminous noise, screen-space with camera parallax ----
	if (haze_alpha > 0.0) {
		vec2 hp = uv * 3.0 + (cam_px * haze_parallax) / 600.0 + vec2(time * 0.01, -time * 0.008);
		float hn = (vnoise(hp * 6.0) - 0.5) * haze_strength;
		c *= 1.0 + hn * haze_alpha * 8.0;
		c += vec3(hn * haze_alpha * 1.5) * dot(c, vec3(0.333));
	}

	float l = dot(c, vec3(0.299, 0.587, 0.114));

	// ---- dust motes, additive, masked by scene brightness ----
	if (dust_intensity > 0.0) {
		float dm = dust(uv, aspect, time);
		c += vec3(1.0, 0.97, 0.85) * dm * dust_intensity * 0.12 * smoothstep(0.08, 0.5, l);
	}

	c = mix(c, vec3(l), clamp(desat + sanity_fx * 0.35 + hp_danger * 0.15 + slowmo * 0.45, 0.0, 1.0));
	c = (c - 0.5) * (contrast + sanity_fx * 0.08 + slowmo * 0.12) + 0.5;

	// ---- vignette ----
	vec2 d = uv - vec2(0.5);
	float v = 1.0 - smoothstep(0.25, 0.85, dot(d, d) * 1.5);   // (reversed-edge smoothstep is undefined in GLSL)
	float vs = clamp(vignette_strength + sanity_fx * 0.25 + heartbeat * 0.12, 0.0, 1.0);
	c *= mix(1.0 - vs, 1.0, v);

	// ---- sanity edge tint (main.lua: purple edges below 40% sanity) ----
	float edge = 1.0 - v;
	c = mix(c, vec3(0.15, 0.0, 0.2) * 0.8 + c * 0.3, sanity_tint * edge * 0.5);

	// ---- low HP / hit: red vignette ----
	float red = clamp(hp_danger * (0.55 + 0.45 * heartbeat) + hit_pulse * 0.9, 0.0, 1.0) * smoothstep(0.1, 1.0, edge + hit_pulse * 0.3);
	c = mix(c, vec3(0.55, 0.02, 0.02) + c * vec3(0.35, 0.1, 0.1), red * 0.75);

	// ---- sanity: scanlines, static ----
	if (sanity_fx > 0.3) {
		float sl = step(0.5, fract(FRAGCOORD.y * 0.25));
		c *= 1.0 - sl * (sanity_fx - 0.3) * 0.12;
	}
	if (sanity_fx > 0.0) {
		float sn = hash21(floor(FRAGCOORD.xy * 0.5) + floor(time * 30.0) * 7.31);
		c += vec3(step(0.985 - sanity_fx * 0.01, sn) * sanity_fx * 0.18);
	}

	// ---- film grain ----
	float n = hash21(uv * (res * 0.15) + time * 60.0);
	c += (n - 0.5) * (grain_amount + sanity_fx * 0.05);

	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
