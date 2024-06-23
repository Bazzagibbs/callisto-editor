package callisto_editor_common

import "../callisto/common"
import "../callisto/asset"

import "core:os"
// import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:log"
import "core:io"
import "core:hash/xxhash"

FILE_EXT :: ".gali"

// TODO: Rework file_overwrite_or_new() once the asset database has been figured out.
// Probably need to keep track of source files <---> imported files relationship to determine whether to
// rename or perform collision avoidance.

// If the file already exists, returns the existing UUID. Otherwise, a newly generated UUID is returned.
//
// `file_name` should NOT include the ".gali" file extension; one will be appended by the procedure.
//
// Returns `ok = false` if the file could not be opened.
file_overwrite_or_new :: proc(base_dir: string, file_name: string) -> (file: os.Handle, uuid: common.Uuid, ok: bool) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s%s", file_name, FILE_EXT)

    file_path := filepath.join({base_dir, strings.to_string(sb)})
    defer delete(file_path)

    old_file, file_err := os.open(file_path)

    should_gen_uuid := true

    if file_err == os.ERROR_FILE_EXISTS {
        // file exists. If valid asset, use its existing uuid.
        file_reader := io.to_reader(os.stream_from_handle(old_file))

        gali_header, meta_ok := asset.read_header(file_reader)
        if meta_ok {
            uuid = gali_header.uuid
            should_gen_uuid = false
        }
        
        os.close(old_file)
        os.remove(file_path)
    } 


    if should_gen_uuid {
        uuid = common.generate_uuid()
    }


    new_file: os.Handle
    new_file, file_err = os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    if file_err != os.ERROR_NONE {
        log.error("Error", file_err, "when creating asset file:", file_path)
        return {}, {}, false
    }

    return new_file, uuid, true
}


file_package_galileo_asset :: proc(file: os.Handle, asset_type: asset.Type, uuid: common.Uuid, asset_body: []byte) -> (ok: bool) {
    header := asset.Galileo_Header {
        magic = { 'G', 'A', 'L', 'I' },
        spec_version_major = GALI_SPEC_VERSION_MAJOR,
        spec_version_minor = GALI_SPEC_VERSION_MINOR,
        spec_version_patch = GALI_SPEC_VERSION_PATCH,
        uuid = uuid,
        type = asset_type,
        body_checksum = xxhash.XXH3_64(asset_body),
    }

    write_err: os.Errno
    bytes_written: int

    bytes_written, write_err = os.write(file, (transmute([^]byte)(&header))[:size_of(header)])
    if write_err != os.ERROR_NONE || bytes_written != size_of(header) {
        log.error("Error writing Galileo header to file:", write_err, "\nWritten:", bytes_written, "Expected:", size_of(header))
        return false
    }

    bytes_written, write_err = os.write(file, asset_body)
    if write_err != os.ERROR_NONE || bytes_written != len(asset_body) {
        log.error("Error writing asset data to file:", write_err, "\nWritten:", bytes_written, "Expected:", len(asset_body))
        return false
    }
    
    return true
}
