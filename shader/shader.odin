package callisto_editor_shader

import "core:log"
import "core:c"
import "core:runtime"

import glsl "glslang"
import "../callisto"

Shader_Data :: struct {
    // input_layout
    spirv: []u32,
}


// Allocates: when res == .Ok, shader_data must be deleted with `shader_data_delete()`
compile :: proc(stage: glsl.Stage, source: cstring) -> (shader_data: Shader_Data, res: callisto.Result) {
    return compile_vulkan(stage, source)
}


// Allocates: when res == .Ok, shader_data must be deleted with `shader_data_delete()`
compile_vulkan :: proc(stage: glsl.Stage, source: cstring) -> (shader_data: Shader_Data, res: callisto.Result) {
    callback_ctx := context

    input := glsl.Input {
        language                          = .GLSL,
        stage                             = stage,
        client                            = .VULKAN,
        client_version                    = .VULKAN_1_3,
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
            include_system      = include_resolver_system,
            include_local       = include_resolver_local,
            free_include_result = include_resolver_free_result,
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

include_resolver_system :: proc "c" (ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^glsl.Include_Result {
    context = (^runtime.Context)(ctx)^
    unimplemented()
}

include_resolver_local :: proc "c" (ctx: rawptr, header_name: cstring, includer_name: cstring, include_depth: c.size_t) -> ^glsl.Include_Result {
    context = (^runtime.Context)(ctx)^
    unimplemented()
}

include_resolver_free_result :: proc "c" (ctx: rawptr, include_res: ^glsl.Include_Result) -> c.int {
    context = (^runtime.Context)(ctx)^
    unimplemented()
}
