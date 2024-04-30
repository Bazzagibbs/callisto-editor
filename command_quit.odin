package callisto_editor

@(init, private)
_register_quit :: proc() {
    register_command("quit", cmd_quit, usage_quit)

    register_alias("q", "quit")
    register_alias("exit", "quit")
}


cmd_quit :: proc(args: []string) -> Command_Result {
    return .Quit
}


usage_quit :: proc(args: []string) -> string {
    return `Quit the editor.`
}


