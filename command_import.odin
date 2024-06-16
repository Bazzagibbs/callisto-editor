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


cmd_import :: proc(args: []string) -> Command_Result {
    log.info("args:", args)

    if len(args) < 4 {
        log.info(usage_import(args)) // This will print importer-specific usage if available
        return .Input_Error
    }

    handler, exists := importer.file_handler_registry[args[1]]
    
    if !exists {
        log.info(usage_import(args))
        return .Input_Error
    }
   


    // Parse options
    // Parse input files
    // Parse output directory

    options := make([dynamic]importer.Option_Pair)
    paths := make([dynamic]string)
    defer delete(options)
    defer delete(paths)

    for arg in args[2:] {
        if strings.has_prefix(arg, "--") { // Arg is option
            split := strings.split(arg[2:], "=")
            
            option := importer.Option_Pair {
                key = split[0]
            }
            if len(split) > 1 {
                option.val = split[1]
            }

            delete(split)

            append(&options, option)
        }
        else { // Arg is path
            append(&paths, arg)
        }
    }

    n_paths := len(paths)
    if n_paths < 2 {
        log.info(usage_import(args))
        return .Input_Error
    }

    // Output dir is last path in array
    return handler.import_file(options[:], paths[:n_paths-1], paths[n_paths-1])
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
    import <file_type> [options] <..input_files> <output_directory>

Arguments:
    file_type         The type of file to import. Supported file types:`)

importer.sb_printf_short_descs(&b, "                          %-12v %v\n")

fmt.sbprintln(&b,`
    options           Depends on file type. Run "help import <file_type>" for valid options.
    input_files       One or more source files to be imported.
    output_directory  The base directory to store Galileo asset files.`)


    return strings.to_string(b)
}

