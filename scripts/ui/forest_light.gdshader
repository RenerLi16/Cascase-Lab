shader_type canvas_item;
render_mode unshaded;

// Eight public on/off lamps. Max blending caps overlaps. Relight the original
// surface colors so tree detail remains visible, rather than overlaying discs.
uniform vec3 beacons[8];
uniform vec2 world_extent;
void fragment() {
    vec4 surface = texture(TEXTURE, UV);
    vec2 world = UV * world_extent - vec2(320.0);
    float light = 0.0;
    for (int i = 0; i < 8; i++) {
        vec2 delta = (world - beacons[i].xy) / vec2(130.0, 105.0);
        light = max(light, exp(-dot(delta, delta) * 1.7) * beacons[i].z);
    }
    vec3 night = surface.rgb * vec3(0.46, 0.56, 0.70);
    vec3 warm = surface.rgb * vec3(3.6, 2.12, 1.05);
    COLOR = vec4(mix(night, warm, light * 0.92), surface.a);
}
