package callisto_editor

import "core:log"
import "core:strings"
import "core:slice"


@(init, private)
_register_help :: proc() {
    register_command("help", cmd_help, usage_help)
    register_alias("h", "help")
}


cmd_help :: proc(args: []string) -> Command_Result {
    if len(args) > 1 {
        name := args[1]
        record, exists := get_command_record(args[1])
        if !exists {
            log.error("Command", args[1], "is not a valid command.")
            return .Input_Error
    }
        log.info(record.usage_proc(args[1:]))
        return .Ok
    }

    // print out all registered commands, sorted alphabetically
    command_names, _ := slice.map_keys(command_registry)
    defer delete(command_names)

    slice.sort(command_names)

    log.info("Available commands:")
    for name in command_names {
        log.info(" ", name)
    }
    

    return .Ok
}

usage_help :: proc(args: []string) -> string {
    return "help [command] [..args]"
}

