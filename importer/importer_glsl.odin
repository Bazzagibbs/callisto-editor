package callisto_importer

import "base:runtime"
import "core:log"
import "core:c"
import "core:os/os2"

import glsl "glslang"
import "../callisto"

VULKAN_VERSION :: glsl.Target_Client_Version.VULKAN_1_3

@(init, private)
_register_shader :: proc() {
    register_file_handler("glsl", importer_shader, usage_shader, short_desc_shader)
}


importer_shader :: proc(options: []Option_Pair, input_files: []string, output_dir: string) -> Command_Result {
    res := Command_Result.Ok

    for input_file in input_files {
        file_data, err := os2.read_entire_file_from_path(input_file)
        if (err != nil) {
            log.error("Error opening file:", input_file)
            res = .File_System_Error
            continue
        }

        stage := shader_parse_options_stage(options)
        
        shader_data := shader_compile(stage, file_data)
        // TODO
        file_overwrite_or_new
        delete(file_data)
    }

    return res
}

usage_shader :: proc(args: []string) -> string {
    return `import glsl [--option=value] <..input_files> <output_dir>

options:
    --stage=fragment    Which stage is this program? Available values:
                            vertex
                            fragment (default)
                            compute
`
}

short_desc_shader :: proc() -> string {
    return "Compile GLSL shaders to SPIRV"
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
    log.error("Shader #include \"LOCAL\" not implemented: this should include relative to the project directory")
    unimplemented()
}

shader_include_resolver_free_result :: proc "c" (ctx: rawptr, include_res: ^glsl.Include_Result) -> c.int {
    context = (^runtime.Context)(ctx)^
    unimplemented()
}
