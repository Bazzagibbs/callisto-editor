package callisto_importer

import "core:os"
import "core:io"
import "core:bufio"
import "core:mem"

import "../callisto/asset"
import cc "../callisto/common"

GALILEO_VERSION :: 0

Galileo_Header :: struct #packed {
    magic:          [4]u8,
    spec_version:   u32,
    uuid:           cc.Uuid,
    type:           asset.Type,
    checksum:       u64,
}

default_galileo_header :: proc(uuid: cc.Uuid, asset_type: asset.Type, checksum: u64) -> Galileo_Header {
    return Galileo_Header {
        magic = "GALI",
        spec_version = GALILEO_VERSION,
        uuid = uuid,
        type = asset_type,
        checksum = checksum,
    }
}


