package callisto_editor

import "importer"
import "callisto/asset"
import "callisto/common"

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:log"
import "core:hash/xxhash"
import "core:mem"


@(init, private)
_register_import :: proc() {
    register_command("import", cmd_import, usage_import)
}


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
cmd_import :: proc(args: []string) -> Command_Result {
    if len(args) < 4 {
        log.info(usage_import(args))
        return .Input_Error
    }
    
    switch args[1] {
        case "gltf":
            return import_gltf(args[2], args[3])
        case: 
            log.info(usage_import(args))
            return .Input_Error
    }

    return .Ok
}

usage_import :: proc(args: []string) -> string {
    b: strings.Builder
    strings.builder_init(&b, allocator = context.temp_allocator)

    if (len(args) > 1) {
        // Try getting specific help
        handler_record, exists := importer.file_handler_registry[args[1]]
        if !exists {
            fmt.sbprintln(&b, args[1], "file type importer could not be found.")
            return strings.to_string(b)
        } 

        return handler_record.usage(args[1:])
    }

fmt.sbprintln(&b, 
`Import source files into its corresponding Galileo asset files.
If the output directory is not empty, any existing assets will be overwritten
but their UUIDs will be kept.

Usage: 
    import <file_type> [options] <input_files...> <output_directory>

Arguments:
    file_type         The type of file to import. Supported file types:`)

importer.sb_printf_short_descs(&b, "                          %-12v %v\n")

fmt.sbprintln(&b,`
    options           Depends on file type. Run "help import <file_type>" for valid options.
    input_files       One or more source files to be imported.
    output_directory  The base directory to store Galileo asset files.`)


    return strings.to_string(b)
}


import_gltf :: proc(in_file_path, out_dir: string) -> Command_Result {
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

        _, err := os.write(out_file, mem.byte_slice(&header, size_of(asset.Galileo_Header)))
        _, err  = os.write(out_file, mesh_data)
        if err != os.ERROR_NONE {
            log.error("Error writing asset file:", err)
        }
    }

    strings.builder_destroy(&file_name)

    return .Ok
}


