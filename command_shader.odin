package callisto_editor

import "core:log"
import "shader"


cmd_shader :: proc(args: []string) -> (ok: bool) {
    log.error("Not implemented")
    return false
}

usage_shader :: proc(args: []string) -> string {
    return "I don't know yet :)"
}

@(init, private)
_register_shader :: proc() {
    register_command("shader", cmd_shader, usage_shader)
}
