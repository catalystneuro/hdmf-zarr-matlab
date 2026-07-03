# hdmf-zarr-matlab

MATLAB implementation of [hdmf-zarr](https://github.com/hdmf-dev/hdmf-zarr)'s
storage conventions — the layer that adds HDF5's missing-from-Zarr features
(**links** and **object references**) on top of Zarr v3, enabling MATLAB to
read and write **NWB files stored as Zarr**.

Built on [zarr-matlab](https://github.com/catalystneuro/zarr-matlab). The
conventions implemented (see the
[hdmf-zarr storage spec](https://hdmf-zarr.readthedocs.io/en/latest/storage.html)
and [hdmf-dev/hdmf-zarr#325](https://github.com/hdmf-dev/hdmf-zarr/pull/325)
for the Zarr v3 encoding):

- `zarr_link` group attributes — soft and external links
- `zarr_dtype: "object"` — object references in datasets (JSON-in-string-dtype)
  and attributes
- `.specloc` / cached specifications

These conventions serve two consumers: NWB-Zarr files (toward a MatNWB
backend) and [matzarr](https://github.com/catalystneuro/matzarr)'s translated
`.mat` cell-array references.

## Status

**Planning.** See the shared plan in
[matzarr/PLAN.md](https://github.com/catalystneuro/matzarr/blob/main/PLAN.md)
(milestones M3–M4). Interoperability with hdmf-zarr/pynwb will be verified
bidirectionally in CI, following the zarr-matlab testing model.

## License

MIT. A [CatalystNeuro](https://catalystneuro.com) project.
