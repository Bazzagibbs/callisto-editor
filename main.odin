package callisto_editor

import "core:os"
import "core:io"
import "core:bufio"
import "core:fmt"
import "core:mem"
import "core:log"

import "core:strings"


main :: proc() {
    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)
    defer {
        for bad_free in track.bad_free_array {
            log.error("Bad free:", bad_free.location)
        }
        for _, leak in track.allocation_map {
            log.error("Leaked:", leak.size, leak.location)
        }
        mem.tracking_allocator_destroy(&track)
    }

    // If called with args, immediately parse args and return.
    if len(os.args) > 1 {
        parse_command(os.args[1:])
        mem.free_all(context.temp_allocator)
        return
    }
    
    // Otherwise, REPL.

    // Set up stdio reader. Can be swapped out for a GUI console reader later.
    stdin: bufio.Reader
    bufio.reader_init(&stdin, os.stream_from_handle(os.stdin), allocator = context.temp_allocator)
    defer bufio.reader_destroy(&stdin)

    // REPL loop
    print_prompt()
    for line in get_command(&stdin) {
        ok := parse_command(line)
        print_prompt(ok)
        mem.free_all(context.temp_allocator)
    }
}

get_command :: proc(reader: ^bufio.Reader) -> (argv: []string, ok: bool) {
    str, err := bufio.reader_read_string(reader, '\n', context.temp_allocator)
    if err != .None do return {}, false
    
    str_trimmed := strings.trim_space(str)
    argv, _ = strings.split(str_trimmed, " ", context.temp_allocator)
    return argv, true
}


print_prompt :: proc(prev_ok: bool = true) {
    if prev_ok {
        fmt.print("  callisto> ")
    } else {
        fmt.print("! callisto> ")
    }
}
