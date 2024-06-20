package callisto_importer

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:strings"
import "core:strconv"
import "core:math"
import "core:fmt"
import "core:slice"
import "core:mem"
import "core:math/linalg"
import "core:hash/xxhash"
import "core:os/os2"

import "vendor:cgltf"
import "../common"
import cc "../callisto/common"
import "../callisto/asset"

@(init, private)
_register_gltf :: proc() {
    register_file_handler("gltf", importer_gltf, usage_gltf, short_desc_gltf);
}


importer_gltf :: proc(options: []Option_Pair, input_files: []string, output_dir: string) -> Command_Result {
    for input_file in input_files {
        meshes, materials, textures, models, constructs, ok_import := import_gltf_file(input_file)
        defer {
            for _, i in meshes {
                mesh := meshes[i]
                asset.delete_mesh(&mesh)
            }
            delete(meshes)
        }
        
        unique_file_names := make(map[string]int) // Only store strings owned by assets, not created by sb
        defer delete(unique_file_names)
        
        file_name := strings.builder_make()
      
        for _, i in meshes {
            mesh := &meshes[i]
           
            strings.builder_reset(&file_name)

            count := unique_file_names[mesh.name]
            if count == 0 {
                fmt.sbprint(&file_name, mesh.name)
            }
            else {
                fmt.sbprintf(&file_name, "%s.%3d", mesh.name, unique_file_names[mesh.name]) // mesh.001
                mesh.name = strings.to_string(file_name)
            }
            unique_file_names[mesh.name] += 1

            // TODO: check if file with same name exists from before we started writing. If so, copy and reuse its UUID.
            out_file, mesh_uuid, ok_open := common.file_overwrite_or_new(output_dir, mesh.name)

            mesh_data := asset.serialize_mesh(mesh)
            defer delete(mesh_data)

            // Create file header
            
            mesh_hash := xxhash.XXH3_64_default(mesh_data)
            header := default_galileo_header(mesh_uuid, .mesh, mesh_hash)

            _, err := os2.write(out_file, mem.byte_slice(&header, size_of(asset.Galileo_Header)))
            _, err  = os2.write(out_file, mesh_data)
            if err != {} {
                log.error("Error writing asset file:", err)
            }
        }

        strings.builder_destroy(&file_name)


    }

    return .Ok
}


usage_gltf :: proc(args: []string) -> string {
    return "import gltf <..input_files> <output_directory>"
}

short_desc_gltf :: proc() -> string {
    return "Import glTF 3D models/scenes"
}


import_gltf_file :: proc(model_path: string) -> (
    meshes:     []asset.Mesh,
    materials:  []asset.Material, 
    textures:   []asset.Texture, 
    models:     []asset.Model, 
    constructs: []asset.Construct,
    ok: bool) {
        model_path_cstr := strings.clone_to_cstring(model_path)
        defer delete(model_path_cstr)
        file_data, res := cgltf.parse_file({}, model_path_cstr); if res != .success {
        // file_data, err := gltf.load_from_file(model_path, true); if err != nil {
            log.error("Error loading file:", res)
            return {}, {}, {}, {}, {}, false
        }
        defer cgltf.free(file_data)
        res = cgltf.load_buffers({}, file_data, model_path_cstr); if res != .success {
            #partial switch res {
            case .file_not_found:
                log.error("Error loading file buffers:", res, "\nIs the .gltf supposed to have other files with it?")
            case:
                log.error("Error loading file buffers:", res)
            }
            return {}, {}, {}, {}, {}, false
        }

        meshes = make([]asset.Mesh, len(file_data.meshes))

        for src_mesh, mesh_idx in file_data.meshes {

            // Get total buffer size for all primitives
            total_buf_size := 0
            vertex_group_count := len(src_mesh.primitives)

            Prim_Temp_Info :: struct {
                bounds_center:              [3]f32,
                bounds_extents:             [3]f32,
                bound_min:                  [3]f32,
                bounds_max:                 [3]f32,

                buffer_slice_size:          int,

                index_count:                int,
                vertex_count:               int,
                element_size:               int,
                n_texcoord_channels:        u64,
                n_color_channels:           u64,
                n_joint_weight_channels:    u64,
            }
            primitive_temp_infos := make([]Prim_Temp_Info, vertex_group_count)
            defer delete(primitive_temp_infos)

            for primitive, vert_group_idx in src_mesh.primitives {
                prim_info := &primitive_temp_infos[vert_group_idx]

                // mandatory:            position          normal            tangent
                prim_info.element_size = size_of([3]f32) + size_of([3]f32) + size_of([4]f32)

                prim_info.index_count = int(primitive.indices.count)

                has_normals, has_tangents: bool

                for attribute in primitive.attributes {
                    accessor := attribute.data
                    #partial switch attribute.type {
                    case .position: 
                        prim_info.vertex_count = int(accessor.count)

                    case .normal:
                        has_normals = true

                    case .tangent:
                        has_tangents = true

                    case .texcoord:  // Multi-channel attribute
                        prim_info.n_texcoord_channels = math.max(prim_info.n_texcoord_channels, u64(attribute.index) + 1)
                        prim_info.element_size += size_of([2]u16)

                    case .color:
                        prim_info.n_color_channels = math.max(prim_info.n_color_channels, u64(attribute.index) + 1)
                        prim_info.element_size += size_of([4]u8)

                    case .joints: 
                        prim_info.n_joint_weight_channels = math.max(prim_info.n_joint_weight_channels, u64(attribute.index) + 1)
                        prim_info.element_size += size_of([4]u16) * 2 // Joints and weights channels are 1:1

                    case .custom: // TODO: support custom attributes as an extension
                        log.warn("Custom attributes not implemented:", attribute.name)
                    }
                    
                }

                prim_info.buffer_slice_size = (prim_info.index_count * size_of(u32)) + prim_info.element_size * prim_info.vertex_count
                total_buf_size += prim_info.buffer_slice_size

                if has_normals == false {
                    // vertex_group_calculate_flat_normals(vertex_group)
                    // TODO: Discard provided tangents
                    has_tangents = false
                    log.warn("Mesh is missing normals. Normal generation not implemented.")
                    // return {}, {}, {}, {}, {}, false
                } 

                if has_tangents == false {
                    log.warn("Mesh is missing tangents. Tangent generation not implemented.")
                    // return {}, {}, {}, {}, {}, false
                    // vertex_group_calculate_tangents(vertex_group)
                }
            }

            meshes[mesh_idx] = asset.make_mesh(vertex_group_count, total_buf_size)
            mesh := &meshes[mesh_idx]
            if src_mesh.name != nil {
                mesh.name = strings.clone_from_cstring(src_mesh.name) 
            } else {
                mesh.name = strings.clone("mesh")
            }
            
            mesh_min := cc.vec3{max(f32), max(f32), max(f32)}
            mesh_max := cc.vec3{min(f32), min(f32), min(f32)}
            slice_begin := 0
            
           
            for primitive, vert_group_idx in src_mesh.primitives {
                vert_group := &mesh.vertex_groups[vert_group_idx]
                prim_info := &primitive_temp_infos[vert_group_idx]
                
                vert_group.buffer_slice = mesh.buffer[slice_begin:prim_info.buffer_slice_size]

                vert_group.index_count                  = u32(prim_info.index_count)
                vert_group.vertex_count                 = u32(prim_info.vertex_count)
                vert_group.texcoord_channel_count       = u8(prim_info.n_texcoord_channels)
                vert_group.color_channel_count          = u8(prim_info.n_color_channels)
                vert_group.joint_weight_channel_count   = u8(prim_info.n_joint_weight_channels)
                vert_group.total_channel_count          = 3 + vert_group.texcoord_channel_count + vert_group.color_channel_count + (vert_group.joint_weight_channel_count * 2)
                
                temp_cursor := vert_group.index_offset
                vert_group.index_offset = temp_cursor
                indices := asset.make_subslice_of_type(u32, mesh.buffer, &temp_cursor, u64(vert_group.index_count))
                vert_group.position_offset = temp_cursor
                _ = asset.make_subslice_of_type(cc.vec3, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                vert_group.normal_offset = temp_cursor
                _ = asset.make_subslice_of_type(cc.vec3, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                vert_group.tangent_offset = temp_cursor
                _ = asset.make_subslice_of_type(cc.vec4, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))

                vert_group.texcoord_offset = temp_cursor
                if vert_group.texcoord_channel_count > 0 {
                    _ = asset.make_subslice_of_type([2]u16, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count) * u64(vert_group.texcoord_channel_count))
                }
                vert_group.color_offset = temp_cursor
                if vert_group.color_channel_count > 0 {
                    _ = asset.make_subslice_of_type(cc.color32, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count) * u64(vert_group.color_channel_count))
                }
                vert_group.joint_offset = temp_cursor
                if vert_group.joint_weight_channel_count > 0 {
                    _ = asset.make_subslice_of_type([4]u16, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count) * u64(vert_group.joint_weight_channel_count))
                }
                vert_group.weight_offset = temp_cursor
                if vert_group.joint_weight_channel_count > 0 {
                    _ = asset.make_subslice_of_type([4]u16, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count) * u64(vert_group.joint_weight_channel_count))
                }

                gltf_unpack_indices(primitive.indices, indices)
                
                for attribute in primitive.attributes {
                    // Copy buffers
                    #partial switch attribute.type {
                    case .position:
                        min := cc.vec3(attribute.data.min.xyz)
                        max := cc.vec3(attribute.data.max.xyz)
                        mesh_min.x = math.min(min.x, mesh_min.x)
                        mesh_min.y = math.min(min.y, mesh_min.y)
                        mesh_min.z = math.min(min.z, mesh_min.z)
                        mesh_max.x = math.max(max.x, mesh_max.x)
                        mesh_max.y = math.max(max.y, mesh_max.y)
                        mesh_max.z = math.max(max.z, mesh_max.z)

                        vert_group.bounds.center, vert_group.bounds.extent = cc.min_max_to_center_extents(min, max)
                        
                        temp_cursor = vert_group.position_offset
                        temp_slice := asset.make_subslice_of_type([3]f32, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([3]f32, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex positions")
                        }
                        for &val in temp_slice {
                            gltf_change_basis_to_gali(&val)
                        }
                    case .normal:
                        temp_cursor = vert_group.normal_offset
                        temp_slice := asset.make_subslice_of_type([3]f32, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([3]f32, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex normals")
                        }
                        for &val in temp_slice {
                            gltf_change_basis_to_gali(&val)
                        }
                    case .tangent:
                        temp_cursor = vert_group.tangent_offset
                        temp_slice := asset.make_subslice_of_type([4]f32, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([4]f32, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex tangents")
                        }
                        for &val in temp_slice {
                            fake_val := transmute(^[3]f32)(&val)
                            gltf_change_basis_to_gali(fake_val)
                        }
                    case .texcoord: 
                        temp_cursor = asset.get_vertex_group_channel_offset([2]u16, u64(vert_group.vertex_count), vert_group.texcoord_offset, u8(attribute.index))
                        temp_slice := asset.make_subslice_of_type([2]u16, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([2]u16, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex UVs")
                        }
                    case .color: 
                        temp_cursor = asset.get_vertex_group_channel_offset([4]u8, u64(vert_group.vertex_count), vert_group.color_offset, u8(attribute.index))
                        temp_slice := asset.make_subslice_of_type([4]u8, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([4]u8, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex colors")
                        }
                    case .joints: 
                        temp_cursor = asset.get_vertex_group_channel_offset([4]u16, u64(vert_group.vertex_count), vert_group.joint_offset, u8(attribute.index))
                        temp_slice := asset.make_subslice_of_type([4]u16, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([4]u16, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex colors")
                        }
                        // These need to be non-normalized
                    case .weights: 
                        temp_cursor = asset.get_vertex_group_channel_offset([4]u16, u64(vert_group.vertex_count), vert_group.weight_offset, u8(attribute.index))
                        temp_slice := asset.make_subslice_of_type([4]u16, mesh.buffer, &temp_cursor, u64(vert_group.vertex_count))
                        ok = gltf_unpack_attribute([4]u16, attribute.data, temp_slice); if !ok {
                            log.error("Error unpacking vertex colors")
                        }
                    // case .custom:

                    }
                }
            }
            mesh.bounds.center, mesh.bounds.extent = cc.min_max_to_center_extents(mesh_min, mesh_max)
        }

        // TODO: make models from mesh/material pairs
        // models = make([]asset.Model, len(file_data.meshes))

        return meshes, {}, {}, {}, {}, true
    }


gltf_unpack_attribute :: proc($T: typeid/[$N]$E, accessor: ^cgltf.accessor, out_data: []T) -> (ok: bool) {
    assert(accessor.count == len(out_data))

    n_components_in_element := N
    insert_alpha := false

    if N == 4 && accessor.type == .vec3 {
        n_components_in_element = 3
        insert_alpha = true
    }
    
    n_components := int(accessor.count) * n_components_in_element
    
    available_floats := cgltf.accessor_unpack_floats(accessor, nil, uint(n_components))
    float_storage := make([]f32, available_floats)
    defer delete(float_storage)
    
    written_data := cgltf.accessor_unpack_floats(accessor, raw_data(float_storage), uint(n_components))
    if written_data == 0 {
        log.error("Accessor could not unpack floats")
        return false
    }

    if insert_alpha {
        temp_out_data := (transmute([^]E)raw_data(out_data))[:n_components]
        dst_idx := 0
        for src_value, src_idx in float_storage {
            temp_out_data[dst_idx] = E(src_value * f32(max(E)))
            dst_idx += 1
            if src_idx % 3 == 2 {
                // Insert alpha afterwards
                temp_out_data[dst_idx] = E(src_value * f32(max(E)))
                dst_idx += 1
            }
        }
    } 
    else {
        // transmute destination buffer to flat slice
        temp_out_data := (transmute([^]E)raw_data(out_data))[:n_components]
        for src_value, src_idx in float_storage {
            if accessor.normalized {
                temp_out_data[src_idx] = E(math.round_f32(src_value * f32(max(E))))
            } else {
                temp_out_data[src_idx] = E(src_value)
            }
        }
    }

    return true
}

gltf_unpack_indices :: proc(accessor: ^cgltf.accessor, out_indices: []u32) {
    assert(accessor.count == len(out_indices))
    for idx in 0..<accessor.count {
        out_indices[idx] = u32(cgltf.accessor_read_index(accessor, idx))
    }
}


gltf_unpack_construct :: proc() -> asset.Construct {
    return {}
}


GLTF_TO_GALI_BASIS :: matrix[4, 4]f32 {
    1,  0,  0,  0,
    0,  0,  1,  0,
    0,  -1, 0,  0,
    0,  0,  0,  1,
}

gltf_change_basis_to_gali :: proc(vector: ^[3]f32) {
    vector^ = ([4]f32{vector.x, vector.y, vector.z, 1} * GLTF_TO_GALI_BASIS).xyz
}
