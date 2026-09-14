shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.02, 0.12, 0.28, 0.95);
uniform vec4 shallow_color : source_color = vec4(0.08, 0.38, 0.58, 0.85);
uniform float wave_speed : hint_range(0.1, 5.0) = 0.8;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.15;
uniform float wave_frequency : hint_range(0.1, 5.0) = 1.2;
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float metallic : hint_range(0.0, 1.0) = 0.1;

void vertex() {
	float wave1 = sin(VERTEX.x * wave_frequency + TIME * wave_speed) * cos(VERTEX.z * wave_frequency + TIME * wave_speed * 0.7);
	float wave2 = cos(VERTEX.x * wave_frequency * 1.5 - TIME * wave_speed * 0.9) * sin(VERTEX.z * wave_frequency * 1.2);
	VERTEX.y += (wave1 + wave2) * wave_amplitude;
}

void fragment() {
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.35);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5;
}
