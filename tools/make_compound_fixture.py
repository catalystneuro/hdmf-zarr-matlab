"""Generate an hdmf-zarr (Zarr v3) fixture of compound datasets: a plain
compound dataset and one whose rows carry object references, written the
way hdmf-zarr writes them (a "struct" data_type, references stored as target
paths in fixed-length text fields and listed in _REFERENCE_FIELDS).

Built from hdmf builders rather than pynwb, so the fixture stays small and
its field types are stated outright instead of following from a schema.

Usage: python tools/make_compound_fixture.py <out_dir>
"""
import shutil
import sys

import numpy as np
from hdmf.build import DatasetBuilder, GroupBuilder, ReferenceBuilder
from hdmf_zarr.backend import ZarrIO


def main(out):
    shutil.rmtree(out, ignore_errors=True)

    dataset_1 = DatasetBuilder("dataset_1", np.arange(100, 200, 10).reshape(2, 5))
    dataset_2 = DatasetBuilder("dataset_2", np.arange(0, 200, 10).reshape(4, 5))

    plain = DatasetBuilder(
        "plain_compound",
        [(1, "Allen"), (2, "Bob"), (3, "Mike")],
        dtype=[{"name": "id", "dtype": "int"}, {"name": "name", "dtype": str}],
    )
    with_refs = DatasetBuilder(
        "ref_compound",
        [
            (1, "dataset_1", ReferenceBuilder(dataset_1)),
            (2, "dataset_2", ReferenceBuilder(dataset_2)),
        ],
        dtype=[
            {"name": "id", "dtype": "int"},
            {"name": "name", "dtype": str},
            {"name": "reference", "dtype": "object"},
        ],
    )

    root = GroupBuilder(
        name="root",
        source=out,
        datasets={
            "dataset_1": dataset_1,
            "dataset_2": dataset_2,
            "plain_compound": plain,
            "ref_compound": with_refs,
        },
    )
    with ZarrIO(out, mode="w") as io:
        io.write_builder(root)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1])
