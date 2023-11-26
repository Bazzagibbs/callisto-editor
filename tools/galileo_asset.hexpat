#pragma pattern_limit 9999999
#include <type/guid.pat>
#include <type/types/rust.pat>
#include <std/core.pat>
#include <std/array.pat>

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
struct uvec4_8 {
    u8  r   [[color("FF0000")]];
    u8  g   [[color("00FF00")]];
    u8  b   [[color("0000FF")]];
    u8  a   [[color("333333")]];
};
struct uvec2_16 {
    u16 x [[color("CC00CC")]];
    u16 y [[color("00CCCC")]];
};

struct uvec4_16 {
    u16 x [[color("CC0000")]];
    u16 y [[color("00CC00")]];  
    u16 z [[color("0000CC")]];
    u16 w [[color("CCCC00")]];
};
    
struct vec3 {
    float x [[color("CC0000")]];
    float y [[color("00CC00")]];
    float z [[color("0000CC")]];
};
    
struct vec4 {
    float x [[color("CC0000")]];
    float y [[color("00CC00")]];
    float z [[color("0000CC")]];
    float w [[color("CCCC00")]];
};

struct AABB {
    vec3 center;
    vec3 extents;
};
    
    

//////////
// MESH //
//////////
namespace Mesh {    
 
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
        u8      extension_channel_count;
        u32     next_extension;          
    };
    
    
    struct Extension_Info {};
    
    struct Vertex_Group {
        i32 idx = std::core::array_index();
           
        u32 index_count = parent.vert_group_infos[idx].index_count;
        u32 vertex_count = parent.vert_group_infos[idx].vertex_count;
        u8  texcoord_channel_count = parent.vert_group_infos[idx].texcoord_channel_count;
        u8  color_channel_count = parent.vert_group_infos[idx].color_channel_count;
        u8  joint_weight_channel_count = parent.vert_group_infos[idx].joint_weight_channel_count;
        u8  ext_channel_count = parent.vert_group_infos[idx].extension_channel_count;
      
        i32         indices[index_count];
        vec3        position[vertex_count];
        vec3        normal[vertex_count];
        vec4        tangent[vertex_count];
        uvec2_16    texcoords[vertex_count * texcoord_channel_count];
        uvec4_8     colors[vertex_count * color_channel_count];
        uvec4_16    joints[vertex_count * joint_weight_channel_count];
        uvec4_16    weights[vertex_count * joint_weight_channel_count];
    };
    
    struct Body {
        Manifest            manifest;
        Vertex_Group_Info   vert_group_infos[manifest.vert_group_count];
        Extension_Info      ext_infos[manifest.extension_count];
        Vertex_Group        vert_groups[manifest.vert_group_count];
    };

}
//////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////


struct Asset {
    Header              header;
    
    match (header.asset_type) {
        (Asset_Type::Mesh): Mesh::Body; 
    }
   
};

Asset asset @ 0x00;