#include <type/guid.pat>
#include <type/types/rust.pat>
#include <std/core.pat>

enum Asset_Type : u32 {
    Mesh = 1,
};

struct Header {
    char        magic[4];
    u32         spec_ver;
    type::GUID  asset_uuid;
    Asset_Type  asset_type;    
    u64         checksum;
};





////////////
// COMMON //
////////////

struct uvec2_16 {
    u16 x;
    u16 y;
};
    
struct vec3 {
    float x;
    float y;
    float z;
};
    
struct vec4 {
    float x;
    float y;
    float z;
    float w;
};

struct AABB {
    vec3 center;
    vec3 extents;
};
    
    

//////////
// MESH //
//////////
    
struct Manifest {
    AABB    bounds;
    u32     vert_group_count;
    u32     extension_count;
    u64     buffer_size;
    u32     next_extension;
};
    

    
struct Vertex_Group_Info {
    AABB    bounds;
    u64     buffer_slice_begin_idx;
    u64     buffer_slice_size;
    u32     index_count;
    u32     vertex_count;
    u8      texcoord_channel_count;
    u8      color_channel_count;
    u8      joint_weight_channel_count;
    u32     next_extension;          
};

    
struct Extension_Info {};

struct Vertex_Group {
    i32 idx = std::core::array_index();

    i32     indices[parent.vert_group_infos[idx].index_count];
    vec3    position[parent.vert_group_infos[idx].vertex_count];
    vec3    normal[parent.vert_group_infos[idx].vertex_count];
    vec4    tangent[parent.vert_group_infos[idx].vertex_count];
};


//////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////


struct Asset {
    Header              header;
    Manifest            manifest;
    Vertex_Group_Info   vert_group_infos[manifest.vert_group_count];
    Extension_Info      ext_infos[manifest.extension_count];
    Vertex_Group        vert_groups[manifest.vert_group_count];
};

Asset asset @ 0x00;