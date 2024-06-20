package callisto_importer

import "base:runtime"
import "core:log"
import "core:c"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:slice"
import "core:path/filepath"
import "core:mem"
import "core:bytes"

import glsl "glslang"
import "../common"
import "../callisto"

VULKAN_VERSION :: glsl.Target_Client_Version.VULKAN_1_3

@(init, private)
_register_shader :: proc() {
    register_file_handler("glsl", importer_shader, usage_shader, short_desc_shader)
}


importer_shader :: proc(options: []Option_Pair, input_files: []string, output_dir: string) -> Command_Result {
    res := Command_Result.Ok

    stage, is_stage_overridden := shader_parse_options_stage(options)

    for input_file in input_files {
        file_data, err := os2.read_entire_file_from_path(input_file, context.allocator)

        if (err != nil) {
            log.error("Error opening file:", input_file)
            res = .File_System_Error
            continue
        }
        
        file_src := strings.clone_to_cstring(string(file_data))
        defer delete(file_src)
        delete(file_data)
       

        if !is_stage_overridden { 
            ext := filepath.ext(input_file)
            ext  = strings.trim_left(ext, ".")

            stage_parse_ok: bool
            stage, stage_parse_ok = shader_file_ext_to_stage(ext)
            if !stage_parse_ok {
                stage = .FRAGMENT
            }
        }
        
        shader_data, compile_res := shader_compile(stage, file_src)
        if compile_res != .Ok {
            log.error("Shader compilation failed:", compile_res)
            res = .Execution_Error
            continue
        }
        
        // TODO: get reflection data

        defer shader_data_delete(shader_data)


        // Write SPIRV to asset file
        out_file, uuid, ok := common.file_overwrite_or_new(output_dir, filepath.base(input_file))
        if !ok {
            log.error("Error opening or creating the output file for", filepath.base(input_file))
            res = .File_System_Error
            continue
        }
        common.file_package_galileo_asset(out_file, .shader, uuid, shader_data_to_galileo_bytes(&shader_data))

    }

    return res
}

usage_shader :: proc(args: []string) -> string {
    return `import glsl [--option=value] <..input_files> <output_dir>

options:
    --stage=<value>     Set the stage of the input shaders. Determined by file extension by default,
                        and is "frag" if file extension is not recognised.
                        Available values:
                            vert    - vertex shader
                            frag    - fragment shader
                            comp    - compute shader
                            tesc    - tessellation control shader
                            tese    - tessellation evaluation shader
                            geom    - geometry shader
                            rgen    - ray generation shader
                            rint    - ray intersection shader
                            rahit   - ray any-hit shader
                            rchit   - ray closest-hit shader
                            rmiss   - ray miss shader
                            rcall   - ray callable shader
`
}

short_desc_shader :: proc() -> string {
    return "Compile GLSL shaders to SPIRV"
}

shader_parse_options_stage :: proc(options: []Option_Pair) -> (stage_override: glsl.Stage, is_overridden: bool) {
    for option in options {
        if option.key == "stage" {
            stage, ok := shader_file_ext_to_stage(option.val)
            if ok {
                return stage, true
            }
        }
    }

    return .FRAGMENT, false
}

shader_file_ext_to_stage :: proc(ext: string) -> (stage: glsl.Stage, ok: bool) {
    switch ext {
    case "vert"  : return .VERTEX, true
    case "frag"  : return .FRAGMENT, true
    case "comp"  : return .COMPUTE, true
    case "tesc"  : return .TESSCONTROL, true
    case "tese"  : return .TESSEVALUATION, true
    case "geom"  : return .GEOMETRY, true
    case "rgen"  : return .RAYGEN, true
    case "rint"  : return .INTERSECT, true
    case "rahit" : return .ANYHIT, true
    case "rchit" : return .CLOSESTHIT, true
    case "rmiss" : return .MISS, true
    case "rcall" : return .CALLABLE, true
    }

    return {}, false
}

Shader_Data :: struct {
    // input_layout
    spirv: []u32,
}


// Allocates: when res == .Ok, shader_data must be deleted with `shader_data_delete()`
shader_compile :: proc(stage: glsl.Stage, source: cstring) -> (shader_data: Shader_Data, res: callisto.Result) {
    return shader_compile_vulkan(stage, source)
}


// Allocates: when res == .Ok, shader_data must be deleted with `shader_data_delete()`
shader_compile_vulkan :: proc(stage: glsl.Stage, source: cstring) -> (shader_data: Shader_Data, res: callisto.Result) {
    callback_ctx := context

    input := glsl.Input {
        language                          = .GLSL,
        stage                             = stage,
        client                            = .VULKAN,
        client_version                    = VULKAN_VERSION,
        target_language                   = .SPV,
        target_language_version           = .SPV_1_6,
        code                              = source,
        default_version                   = 100,
        default_profile                   = {.NO_PROFILE},
        force_default_version_and_profile = false,
        forward_compatible                = false,
        messages                          = {},
        resource                          = glsl.default_resource(),
        /* include callbacks */
        callbacks = {
            include_system      = shader_include_resolver_system,
            include_local       = shader_include_resolver_local,
            free_include_result = shader_include_resolver_free_result,
        },
        callbacks_ctx = &callback_ctx,
    }
    
    shader := glsl.shader_create(&input)
    defer glsl.shader_delete(shader)

    ok := glsl.shader_preprocess(shader, &input)
    if !ok {
        log.error("GLSL preprocessing failed")
        log.error(glsl.shader_get_info_log(shader))
        log.error(glsl.shader_get_info_debug_log(shader))
        log.infof("Source code:\n%v", input.code)
        return {}, .Unknown
    }

    ok = glsl.shader_parse(shader, &input)
    if !ok {
        log.error("GLSL parsing failed")
        log.error(glsl.shader_get_info_log(shader))
        log.error(glsl.shader_get_info_debug_log(shader))
        log.infof("Preprocessed code:\n%v", glsl.shader_get_preprocessed_code(shader))
        return {}, .Unknown
    }

    program := glsl.program_create()
    defer glsl.program_delete(program)

    glsl.program_add_shader(program, shader)

    ok = glsl.program_link(program, {.SPV_RULES, .VULKAN_RULES})
    if !ok {
        log.error("GLSL linking failed")
        log.error(glsl.shader_get_info_log(shader))
        log.error(glsl.shader_get_info_debug_log(shader))
        return {}, .Unknown
    }

    glsl.program_SPIRV_generate(program, stage)

    size := glsl.program_SPIRV_get_size(program)
    
    data := Shader_Data {
        spirv = make([]u32, size),
    }

    glsl.program_SPIRV_get(program, raw_data(data.spirv))

    messages := glsl.program_SPIRV_get_messages(program)
    if messages != nil {
        log.info(messages)
    }

    return {}, .Ok
}


// **Allocates using the provided allocator**
shader_data_to_galileo_bytes :: proc(shader_data: ^Shader_Data, allocator := context.allocator) -> []byte {
    return bytes.join({
        slice.bytes_from_ptr(raw_data(shader_data.spirv), len(shader_data.spirv) * 4), // int slice to byte slice
    }, nil)
    
}


shader_data_delete :: proc(shader_data: Shader_Data) {
    delete(shader_data.spirv)
}

shader_include_resolver_system :: proc "c" (ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^glsl.Include_Result {
    context = (^runtime.Context)(ctx)^
    log.error("Shader #include <SYSTEM> not implemented: this should include from Callisto's built-in shader snippets")
    unimplemented()
}

shader_include_resolver_local :: proc "c" (ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^glsl.Include_Result {
    context = (^runtime.Context)(ctx)^
    log.error(`"Shader #include "LOCAL" not implemented: this should include relative to the project directory`)
    unimplemented()
}

shader_include_resolver_free_result :: proc "c" (ctx: rawptr, include_res: ^glsl.Include_Result) -> c.int {
    context = (^runtime.Context)(ctx)^
    unimplemented()
}
