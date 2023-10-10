package callisto_editor

import "core:fmt"
import "core:strings"

cmd_help :: proc(args: []string) -> (ok: bool) {

    usage_proc: Usage_Proc = usage_help

    if len(args) > 1 {
        cmd_name := args[1]
        cmd_record, cmd_ok := command_registry[cmd_name]
        if !cmd_ok {
            println("Command not found:", cmd_name)
            return false
        }
        
        usage_proc = cmd_record.usage_proc
    }

    println(usage_proc(args))
    return true
}

usage_help :: proc(args: []string) -> string {
    return "help [command] [..args]"
}

@(init, private)
_register_help :: proc() {
    register_command("help", cmd_help, usage_help)
}
