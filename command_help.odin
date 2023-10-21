package callisto_editor

import "core:fmt"
import "core:strings"
import "core:slice"

cmd_help :: proc(args: []string) -> (ok: bool) {


    if len(args) > 1 {
        cmd_name := args[1]
        cmd_record, cmd_ok := command_registry[cmd_name]
        if !cmd_ok {
            println("Command not found:", cmd_name)
            return false
        }
        
        println(cmd_record.usage_proc(args[1:]))
        return true
    }

    // print out all registered commands, sorted alphabetically
    command_names, _ := slice.map_keys(command_registry)
    defer delete(command_names)

    slice.sort(command_names)

    println("Available commands:")
    for name in command_names {
        println(" ", name)
    }
    

    return true
}

usage_help :: proc(args: []string) -> string {
    return "help [command] [..args]"
}

@(init, private)
_register_help :: proc() {
    register_command("help", cmd_help, usage_help)
}
