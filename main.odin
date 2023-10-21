package callisto_editor

import "core:os"
import "core:io"
import "core:bufio"
import "core:fmt"
import "core:mem"
import "core:log"

import "core:strings"

cmdline_in : bufio.Reader
cmdline_out: io.Writer

main :: proc() {
    // DEBUG SETUP
    // ///////////
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
    // ///////////

    // Set up stdio reader. Can be swapped out for a GUI console reader later.
    bufio.reader_init(&cmdline_in, io.to_reader(os.stream_from_handle(os.stdin)))
    defer bufio.reader_destroy(&cmdline_in)

    // Set up stdio writer. Can be swapped out for a GUI console writer later.
    // bufio.writer_init(&cal_in, os.stream_from_handle(os.stdout), allocator = context.temp_allocator)
    cmdline_out = io.to_writer(os.stream_from_handle(os.stdout))

    // If called with args, immediately parse args and return.
    if len(os.args) > 1 {
        parse_command(os.args[1:])
        return
    }
    
    // Otherwise, REPL.
    prev_ok := true
    line: []string
    for get_command(&cmdline_in, &line, prev_ok) == true {
        prev_ok = parse_command(line)
        mem.free_all(context.temp_allocator)
    }

    mem.free_all(context.temp_allocator)
}


// Allocates using temp allocator
get_command :: proc(reader: ^bufio.Reader, out_args: ^[]string, prev_ok: bool) -> (next: bool) {
    if prev_ok {
        print("\u001b[32mCAL>\u001b[0m ")
    } else {
        print("\u001b[31mCAL>\u001b[0m ")
    }

    str, err := bufio.reader_read_string(reader, '\n', context.temp_allocator)
    if err != .None {
        if err != .Unknown { // sigint errors with "unknown", which should close the program without error.
            log.error("Error getting command:", err)
        }
        return false
    }
    
    str_trimmed := strings.trim_space(str)
    out_args^, _ = strings.split(str_trimmed, " ", context.temp_allocator)
    return true
}

print   :: fmt.print
println :: fmt.println
