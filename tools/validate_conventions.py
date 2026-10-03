"""Validate a MATLAB-written hdmf-zarr conventions store against the
documented storage spec: its on-disk shape through zarr-python, then its
meaning through hdmf-zarr's own reader.

Usage: python tools/validate_conventions.py <store_dir>
"""
import sys

import zarr
from hdmf.build import DatasetBuilder, GroupBuilder, ReferenceBuilder
from hdmf_zarr.backend import ZarrIO

DEVICE = "/general/devices/probe0"
DATA = "/acquisition/ts/data"


def check_layout(root):
    g = zarr.open_group(zarr.storage.LocalStore(root), mode="r")

    # links: _LINKS must be a LIST of {name, source, path}
    acq = g["acquisition"]
    assert "zarr_link" not in acq.attrs
    links = acq.attrs["_LINKS"]
    assert isinstance(links, list), f"_LINKS is {type(links)}, not list"
    assert links == [{"source": ".", "path": DEVICE, "name": "device"}], links
    target = g[links[0]["path"].lstrip("/")]
    assert target.attrs["neurodata_type"] == "Device"

    # reference dataset: string dtype, _DTYPE attr, plain path elements
    refs = g["acquisition"]["ts"]["refs"]
    assert refs.attrs["_DTYPE"] == "object_reference"
    assert "zarr_dtype" not in refs.attrs
    assert [str(r) for r in refs[:]] == [DEVICE, DATA]

    # attribute-form reference: {"_REFERENCE": {source, path}}
    table = g["acquisition"]["ts"]["data"].attrs["table"]
    assert table == {"_REFERENCE": {"source": ".", "path": DEVICE}}, table

    # compound dataset: a "struct" data_type with reference fields listed
    # in _REFERENCE_FIELDS and stored as fixed-length text holding paths
    compound = g["acquisition"]["ts"]["compound"]
    assert compound.attrs["_REFERENCE_FIELDS"] == ["reference"]
    assert "zarr_dtype" not in compound.attrs
    assert compound.dtype.names == ("id", "name", "reference"), compound.dtype
    # hdmf-zarr's minimum text capacity, so rows can be appended later
    assert compound.dtype["reference"].itemsize >= 512 * 4, compound.dtype["reference"]
    rows = compound[:]
    assert rows["id"].tolist() == [1, 2]
    assert list(rows["name"]) == ["probe0", "series"]
    assert list(rows["reference"]) == [DEVICE, DATA]

    # consolidated metadata still valid after MATLAB writes
    assert g.metadata.consolidated_metadata is not None


def target_path(builder):
    """Absolute path of the builder a reference or link points at."""
    if isinstance(builder, ReferenceBuilder):
        builder = builder.builder
    return builder.path if builder.path.startswith("/") else "/" + builder.path


def check_hdmf_zarr_reads(root):
    with ZarrIO(root, mode="r") as io:
        top = io.read_builder()
        ts = top["acquisition"]["ts"]

        link = top["acquisition"].links["device"]
        assert isinstance(link.builder, GroupBuilder)
        assert link.builder.attributes["neurodata_type"] == "Device"

        table = ts["data"].attributes["table"]
        assert isinstance(table, GroupBuilder)
        assert table.attributes["neurodata_type"] == "Device"

        refs = ts["refs"]
        assert isinstance(refs, DatasetBuilder)
        resolved = list(refs.data)
        assert isinstance(resolved[0], GroupBuilder)
        assert isinstance(resolved[1], DatasetBuilder)

        compound = ts["compound"]
        assert [field["name"] for field in compound.dtype] == ["id", "name", "reference"]
        assert compound.dtype[2]["dtype"] == DatasetBuilder.OBJECT_REF_TYPE
        rows = list(compound.data)
        assert isinstance(rows[0][2], GroupBuilder)
        assert isinstance(rows[1][2], DatasetBuilder)


def main(root):
    check_layout(root)
    check_hdmf_zarr_reads(root)
    print("conventions validated: links, dataset refs, attribute refs, "
          "compound datasets, consolidation; read back by hdmf-zarr")


if __name__ == "__main__":
    main(sys.argv[1])
