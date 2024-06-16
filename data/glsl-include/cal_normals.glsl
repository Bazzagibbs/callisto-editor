vec3 cal_bitangent(vec3 normal, vec4 tangent) {
    vec3 n_normal = normalize(normal);
    vec3 n_tangent = normalize(tangent.xyz);
    float sign = tangent.w;
    return cross(n_normal, n_tangent) * sign;
}


mat3 cal_tbn(vec3 normal, vec4 tangent) {
    vec3 n_normal = normalize(normal);
    vec3 n_tangent = normalize(tangent.xyz);
    float sign = tangent.w;
    vec3 n_bitangent = cross(n_normal, n_tangent) * sign;
    return mat3(n_tangent, n_bitangent, n_normal);
}


vec3 cal_texture_normal(sampler2D normal_map, vec2 texcoords, mat3 tbn) {
    return tbn * texture(normal_map, texcoords).rgb;
}
