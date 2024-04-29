package callisto_editor

import "shader"


cmd_shader :: proc() {

}

@(init, private)
_register_shader :: proc() {
    register_command("shader", cmd_shader, usage_shader)
}
