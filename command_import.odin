package callisto_editor

import "importer"
import "core:fmt"

cmd_import :: proc(args: []string) -> (ok: bool) {
    return true
}

usage_import :: proc(args: []string) -> string {
    return "import <file_type> <input_file_path> <output_directory>"
}

@(init, private)
_register_import :: proc() {
    register_command("import", cmd_import, usage_import)
}
