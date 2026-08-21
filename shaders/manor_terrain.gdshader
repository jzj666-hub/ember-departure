shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 grass_tint_base : source_color = vec3(0.28, 0.48, 0.20);
uniform vec3 grass_tint_bright : source_color = vec3(0.42, 0.65, 0.26);
uniform vec3 dirt_tint : source_color = vec3(0.45, 0.38, 0.28);

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    v += noise(p) * 0.5;
    v += noise(p * 2.1) * 0.25;
    v += noise(p * 4.3) * 0.125;
    return v;
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 w_pos = v_world_pos;
    vec3 w_norm = normalize(v_world_normal);

    // 1. Textures sampling
    vec4 t_grass = texture(grass_tex, w_pos.xz * 0.25);
    vec4 t_path = texture(path_tex, w_pos.xz * 0.16);
    
    // Triplanar rock sampling on slopes
    vec4 t_rock_x = texture(rock_tex, w_pos.yz * 0.12);
    vec4 t_rock_y = texture(rock_tex, w_pos.xz * 0.12);
    vec4 t_rock_z = texture(rock_tex, w_pos.xy * 0.12);
    vec3 blend_weights = abs(w_norm);
    blend_weights = blend_weights / (blend_weights.x + blend_weights.y + blend_weights.z);
    vec4 t_rock = t_rock_x * blend_weights.x + t_rock_y * blend_weights.y + t_rock_z * blend_weights.z;

    // 2. Multi-tone Grass color
    float grass_noise = fbm(w_pos.xz * 0.06);
    vec3 grass_tint = mix(grass_tint_base, grass_tint_bright, smoothstep(0.3, 0.7, grass_noise));
    vec3 grass_color = t_grass.rgb * grass_tint * 1.5;

    // 3. Road & Courtyard Path Masking
    // Main north-south road from entrance to manor
    float path_main = smoothstep(2.6, 0.2, abs(w_pos.x)) * step(-18.0, w_pos.z) * step(w_pos.z, 14.0);
    // East branch to Blacksmith & Stable
    float path_east = smoothstep(2.2, 0.2, abs(w_pos.z - (-6.0))) * smoothstep(0.0, 4.0, w_pos.x) * step(w_pos.x, 26.0);
    // West branch to Mill & Bell tower
    float path_west = smoothstep(2.2, 0.2, abs(w_pos.z - 4.0)) * smoothstep(0.0, -4.0, w_pos.x) * step(-28.0, w_pos.x);
    // Central courtyard clearing
    float dist_center = length(w_pos.xz);
    float courtyard_dirt = smoothstep(16.0, 4.0, dist_center) * 0.5;

    float total_path_mask = clamp(path_main + path_east + path_west + courtyard_dirt, 0.0, 1.0);

    // 4. Slope / Cliff detection
    float slope = 1.0 - clamp(w_norm.y, 0.0, 1.0);
    float cliff_mask = smoothstep(0.18, 0.45, slope);

    // 5. Blending layers
    vec3 path_color = t_path.rgb * dirt_tint * 1.6;
    vec3 base_terrain = mix(grass_color, path_color, total_path_mask);
    vec3 final_color = mix(base_terrain, t_rock.rgb * 1.1, cliff_mask);

    // Organic micro-variation
    float micro = noise(w_pos.xz * 1.2);
    final_color *= (0.92 + micro * 0.16);

    ALBEDO = final_color;
    ROUGHNESS = mix(0.9, 0.75, max(total_path_mask, cliff_mask));
    SPECULAR = 0.18;
}
