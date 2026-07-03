"""Generate an NWB-Zarr (v3) fixture exercising the hdmf-zarr conventions:
links (zarr_link), object references in attributes and datasets
(zarr_dtype: object), and cached specifications (.specloc).

Usage: python tools/make_nwb_fixture.py <out_dir>
"""
import shutil
import sys
from datetime import datetime, timezone

import numpy as np
from hdmf_zarr.nwb import NWBZarrIO
from pynwb import NWBFile
from pynwb.ecephys import ElectricalSeries
from pynwb.file import Subject


def main(out):
    shutil.rmtree(out, ignore_errors=True)
    nwbfile = NWBFile(
        session_description="hdmf-zarr-matlab conventions fixture",
        identifier="fixture-001",
        session_start_time=datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc),
        subject=Subject(subject_id="M-042", species="Mus musculus"),
    )
    dev = nwbfile.create_device(name="probe0")
    grp = nwbfile.create_electrode_group(
        name="shank0", description="d", location="CA1", device=dev)  # link -> device
    for i in range(4):
        nwbfile.add_electrode(location="CA1", group=grp)  # refs -> group per row

    # DynamicTableRegion: object reference stored in an ATTRIBUTE
    region = nwbfile.create_electrode_table_region([0, 1, 2, 3], "all electrodes")
    es = ElectricalSeries(
        name="eseries",
        data=np.arange(400, dtype="float32").reshape(100, 4) * 0.5,
        electrodes=region,
        rate=30000.0,
        starting_time=0.0,
    )
    nwbfile.add_acquisition(es)

    with NWBZarrIO(out, mode="w") as io:
        io.write(nwbfile)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1])
