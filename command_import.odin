package callisto_editor

import "importer"
import "callisto/asset"
import "callisto/common"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:runtime"
import "core:strings"
import "core:log"
import "core:hash/xxhash"
import "core:mem"

// `file_type`         The file type to import.
// `input_file_path`   The source file to be imported.
// `output_directory`  The base directory to store the resulting Galileo asset files.
Import_Args :: struct {
    file_type:          Import_File_Type,
    input_file_path:    string,
    output_directory:   string,
}

Import_File_Type :: enum {
    gltf,
}


// TODO: support this command structure. Do reflection on the args struct to get docs, etc.
// cmd_import :: proc(args: ^Import_Args) -> (res: Result)
cmd_import :: proc(args: []string) -> (ok: bool) {
    if len(args) < 4 {
        println(usage_import(args))
        return true
    }
    
    switch args[1] {
        case "gltf":
            return import_gltf(args[2], args[3])
        case: 
            println(usage_import(args))
        return false
    }

    return true
}

usage_import :: proc(args: []string) -> string {
    return #load("help_docs/import.txt")
}

@(init, private)
_register_import :: proc() {
    register_command("import", cmd_import, usage_import)
}

import_gltf :: proc(in_file_path, out_dir: string) -> (ok: bool) {
    // TODO: Make sure in_file and out_dir are valid
    
    
    meshes, materials, textures, models, constructs, ok_import := importer.import_gltf(in_file_path)
    defer {
        for _, i in meshes {
            mesh := meshes[i]
            asset.delete_mesh(&mesh)
        }
        delete(meshes)
    }
    // defer { delete all imported }
    
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
        out_file, mesh_uuid, ok_open := file_overwrite_or_new(out_dir, mesh.name)

        mesh_data := asset.serialize_mesh(mesh)
        defer delete(mesh_data)

        // Create file header
        
        mesh_hash := xxhash.XXH3_64_default(mesh_data)
        header := importer.default_galileo_header(mesh_uuid, .mesh, mesh_hash)

        _, err := os.write(out_file, mem.byte_slice(&header, size_of(importer.Galileo_Header)))
        _, err  = os.write(out_file, mesh_data)
        if err != os.ERROR_NONE {
            log.error("Error writing asset file:", err)
        }
    }

    strings.builder_destroy(&file_name)

    return true
}
