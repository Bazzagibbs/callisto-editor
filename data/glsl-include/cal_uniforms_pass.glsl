layout(set=1, binding=0) uniform Cal_Pass_Data {
    mat4 view;
    mat4 proj;
    mat4 view_proj;
    vec3 cam_position_world;
    vec3 cam_position_view;
} cal_pass_data;
