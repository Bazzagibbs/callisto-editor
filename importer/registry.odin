package callisto_importer

import "../common"
import "core:strings"
import "core:slice"
import "core:fmt"

file_handler_registry: map[string]Importer_Record

Command_Result :: common.Command_Result

Importer_Record :: struct {
    import_file : Importer_Proc,
    usage       : Importer_Usage_Proc,
    short_desc  : Importer_Short_Desc_Proc,
}

Option_Pair :: struct {
    key : string,
    val : string,
}

Importer_Proc             :: #type proc(options: []Option_Pair, input_file: string, output_path: string) -> Command_Result 
Importer_Usage_Proc       :: #type proc(args: []string) -> string
Importer_Short_Desc_Proc  :: #type proc() -> string


register_file_handler :: proc(file_type: string, importer_proc: Importer_Proc, usage: Importer_Usage_Proc, short_desc: Importer_Short_Desc_Proc) {
    file_handler_registry[file_type] = {
        importer_proc,
        usage,
        short_desc,
    }
}


sb_printf_short_descs :: proc(sb: ^strings.Builder, format: string) {
    file_handler_entries, _ := slice.map_entries(file_handler_registry)
    defer delete(file_handler_entries)

    slice.sort_by_cmp(file_handler_entries, _cmp_keys)

    for entry in file_handler_entries {
        fmt.sbprintf(sb, format, entry.key, entry.value.short_desc())
    }
}


@(private)
_cmp_keys :: proc(a, b: slice.Map_Entry(string, Importer_Record)) -> slice.Ordering {
    return slice.Ordering(strings.compare(a.key, b.key))
}
