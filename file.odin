package callisto_editor

import "callisto/common"
import "callisto/asset"
import "importer"

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "core:log"

FILE_EXT :: ".gali"

// If the file already exists, returns the existing UUID. Otherwise, a newly generated UUID is returned.
//
// `file_name` should NOT include a file extension; one will be appended by the procedure.
//
// Returns `ok = false` if the file could not be opened.
file_overwrite_or_new :: proc(base_dir: string, file_name: string) -> (file: os.Handle, uuid: common.Uuid, ok: bool) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    fmt.sbprintf(&sb, "%s%s", file_name, FILE_EXT)

    file_path := filepath.join({base_dir, strings.to_string(sb)})
    defer delete(file_path)

    existing_meta, file_exists := asset.read_metadata(file_path)
    if file_exists {
        uuid = existing_meta.uuid
        log.infof("Overwriting existing file: %s with UUID: %32x", file_path, uuid)
    } else {
        uuid = common.generate_uuid()
        log.infof("Creating new file: %s with UUID: %32x", file_path, uuid)
    }

    new_file, err := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
    if err != os.ERROR_NONE {
        log.error("Error creating asset file:", err)
        return {}, {}, false
    }

    return new_file, uuid, true

}
