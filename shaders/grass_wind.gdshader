shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.22, 0.40, 0.16);
uniform vec3 tip_color : source_color = vec3(0.50, 0.76, 0.28);
uniform float wind_speed : hint_range(0.1, 5.0) = 2.4;
uniform float wind_strength : hint_range(0.01, 1.5) = 0.32;

varying vec3 v_world_pos;
varying float v_height_factor;

void vertex() {
    vec4 w_origin = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
    vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
    v_world_pos = world_pos.xyz;
    
    // Bottom root is anchored to ground (0.0), top sways
    v_height_factor = clamp(max(0.0, VERTEX.y) * 1.3, 0.0, 1.0);
    
    // Continuous multi-frequency wind wave across manor world
    float time = TIME * wind_speed;
    float wave1 = sin(time + w_origin.x * 0.35 + w_origin.z * 0.28);
    float wave2 = cos(time * 1.4 + w_origin.x * 0.5 - w_origin.z * 0.42) * 0.45;
    float gust = sin(time * 0.4 + w_origin.x * 0.12 + w_origin.z * 0.08) * 0.5 + 0.5;
    
    float total_wave = (wave1 + wave2) * (0.75 + gust * 0.6);
    
    // Wind vector in X-Z space with subtle downward compression when bending
    vec3 wind_dir = normalize(vec3(0.9, 0.0, 0.45));
    float sway = total_wave * wind_strength * (v_height_factor * v_height_factor);
    vec3 wind_offset = wind_dir * sway;
    wind_offset.y = -abs(sway) * 0.22;
    
    VERTEX += wind_offset;
}

void fragment() {
    vec4 tex = texture(grass_texture, UV);
    vec3 col = mix(base_color, tip_color, v_height_factor);
    vec3 final_color = tex.rgb * col * 1.5;
    
    ALBEDO = final_color;
    ROUGHNESS = 0.82;
    SPECULAR = 0.16;
}
