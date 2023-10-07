package callisto_editor

import "core:fmt"

command_registry: map[string]Command_Record

Command_Proc    :: #type proc(args: []string) -> (ok: bool)
Usage_Proc      :: #type proc(args: []string) -> string


Command_Record  :: struct {
    command_proc    : Command_Proc,
    usage_proc      : Usage_Proc,
}


// Commands can be registered before starting using an @(init) procedure that calls this
register_command :: proc(command_name: string, command_proc: Command_Proc, usage_proc: Usage_Proc) {
    command_registry[command_name] = {command_proc, usage_proc}
}

parse_command :: proc(args: []string) -> (ok: bool) {
    cmd_name := args[0]
    cmd_record, cmd_ok := command_registry[cmd_name] 
    if !cmd_ok {
        fmt.println("Command not found:", cmd_name)
        return false
    }
    
    return cmd_record.command_proc(args)
}

