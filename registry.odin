package callisto_editor

import "core:log"
import "common"


command_registry: map[string]Command_Record
command_aliases : map[string]string


MAX_ALIAS_DEPTH :: 8
Command_Result  :: common.Command_Result
Command_Proc    :: #type proc(args: []string) -> Command_Result
Usage_Proc      :: #type proc(args: []string) -> string


Command_Record  :: struct {
    command_proc    : Command_Proc,
    usage_proc      : Usage_Proc,
}


// Commands can be registered before starting using an @(init) procedure that calls this
register_command :: proc(command_name: string, command_proc: Command_Proc, usage_proc: Usage_Proc) {
    command_registry[command_name] = {command_proc, usage_proc}
}


// This could maybe be exposed as its own command?
register_alias :: proc(alias: string, command_name: string) {
    command_aliases[alias] = command_name
}


get_command_record :: proc(cmd_name: string) -> (record: Command_Record, exists: bool) {
    cmd_name := cmd_name

    record, exists = command_registry[cmd_name]
    if exists do return

    for i in 0..<MAX_ALIAS_DEPTH {
        cmd_name, exists = command_aliases[cmd_name]
        if !exists do return {}, false

        record, exists = command_registry[cmd_name]
        if exists do return
    }

    log.error("Reached max alias depth for command:", cmd_name)
    return {}, false
}


parse_command :: proc(args: []string) -> Command_Result {
    record, exists := get_command_record(args[0])
    if !exists do return .Input_Error

    return record.command_proc(args)
}

