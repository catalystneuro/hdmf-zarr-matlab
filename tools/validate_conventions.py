"""Validate a MATLAB-written hdmf-zarr conventions store against the
documented storage spec, using zarr-python as the reader.

Usage: python tools/validate_conventions.py <store_dir>
"""
import json
import sys

import zarr


def main(root):
    g = zarr.open_group(zarr.storage.LocalStore(root), mode="r")

    # links: zarr_link must be a LIST of dicts with name/source/path
    acq = g["acquisition"]
    links = acq.attrs["zarr_link"]
    assert isinstance(links, list), f"zarr_link is {type(links)}, not list"
    link = links[0]
    assert link["name"] == "device"
    assert link["source"] == "."
    assert link["path"] == "/general/devices/probe0"
    target = g[link["path"].lstrip("/")]
    assert target.attrs["neurodata_type"] == "Device"

    # reference dataset: string dtype, zarr_dtype attr, JSON elements
    refs = g["acquisition"]["ts"]["refs"]
    assert refs.attrs["zarr_dtype"] == "object"
    r0 = json.loads(str(refs[0]))
    assert r0["source"] == "." and r0["path"] == "/general/devices/probe0"
    assert r0["object_id"] == "dev-oid-1"
    assert r0["source_object_id"] == "root-oid-1"

    # attribute-form reference
    table = g["acquisition"]["ts"]["data"].attrs["table"]
    assert table["zarr_dtype"] == "object"
    assert table["value"]["path"] == "/general/devices/probe0"

    # consolidated metadata still valid after MATLAB writes
    assert g.metadata.consolidated_metadata is not None
    print("conventions validated: links, dataset refs, attribute refs, consolidation")


if __name__ == "__main__":
    main(sys.argv[1])
