package callisto_editor_common

import "../callisto/common"
import "../callisto/asset"

import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:log"
import "core:io"
import "core:hash/xxhash"

FILE_EXT :: ".gali"

// If the file already exists, returns the existing UUID. Otherwise, a newly generated UUID is returned.
//
// `file_name` should NOT include the ".gali" file extension; one will be appended by the procedure.
//
// Returns `ok = false` if the file could not be opened.
file_overwrite_or_new :: proc(base_dir: string, file_name: string) -> (file: ^os2.File, uuid: common.Uuid, ok: bool) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s%s", file_name, FILE_EXT)

    file_path := filepath.join({base_dir, strings.to_string(sb)})
    defer delete(file_path)

    uuid = common.generate_uuid()

    old_file, file_err := os2.open(file_path)
    if file_err == os2.General_Error.Exist {
        // file exists. If valid asset, use its existing uuid.
        file_reader := io.to_reader(os2.to_stream(old_file))

        gali_header, meta_ok := asset.read_header(file_reader)
        if meta_ok {
            uuid = gali_header.uuid
        }
        
        os2.close(old_file)
    }

    new_file, err := os2.open(file_path, {.Read, .Write, .Trunc})
    if err != {} {
        log.error("Error creating asset file:", err)
        return {}, {}, false
    }

    return new_file, uuid, true
}


file_package_galileo_asset :: proc(file: ^os2.File, asset_type: asset.Type, uuid: common.Uuid, asset_body: []byte) -> (ok: bool) {
    header := asset.Galileo_Header {
        magic = { 'G', 'A', 'L', 'I' },
        spec_version_major = GALI_SPEC_VERSION_MAJOR,
        spec_version_minor = GALI_SPEC_VERSION_MINOR,
        spec_version_patch = GALI_SPEC_VERSION_PATCH,
        uuid = uuid,
        type = asset_type,
        body_checksum = xxhash.XXH3_64(asset_body),
    }

    write_err: os2.Error
    bytes_written: int

    bytes_written, write_err = os2.write(file, (transmute([^]byte)(&header))[:size_of(header)])
    if write_err != nil || bytes_written != size_of(header) {
        log.error("Error writing Galileo header to file:", write_err, "\nWritten:", bytes_written, "Expected:", size_of(header))
        return false
    }

    bytes_written, write_err = os2.write(file, asset_body)
    if write_err != nil || bytes_written != size_of(header) {
        log.error("Error writing asset data to file:", write_err, "\nWritten:", bytes_written, "Expected:", len(asset_body))
        return false
    }
    
    return true
}
