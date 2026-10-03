# hdmf-zarr-matlab

MATLAB implementation of [hdmf-zarr](https://github.com/hdmf-dev/hdmf-zarr)'s
storage conventions — the layer that adds HDF5's missing-from-Zarr features
(**links** and **object references**) on top of Zarr v3, enabling MATLAB to
read and write **NWB files stored as Zarr**.

Built on [zarr-matlab](https://github.com/catalystneuro/zarr-matlab). The
conventions implemented are those of hdmf-zarr 0.14 (see the
[hdmf-zarr storage spec](https://hdmf-zarr.readthedocs.io/en/latest/storage.html)):

- `_LINKS` group attributes — soft and external links
- `_DTYPE: "object_reference"` — object references in datasets, stored as
  target paths
- `{"_REFERENCE": {source, path}}` — object references in attributes
- `_REFERENCE_FIELDS` — reference fields of compound datasets
- `.specloc` / cached specifications

Stores written by hdmf-zarr before 0.14 use `zarr_link` and `zarr_dtype`
instead. Like hdmf-zarr, this package still reads those names, but writes
only the current ones.

These conventions serve two consumers: NWB-Zarr files (toward a MatNWB
backend) and [matzarr](https://github.com/catalystneuro/matzarr)'s translated
`.mat` cell-array references.

## Status

**Read and write layers implemented and CI-verified.**

- **Read**: `resolve()` follows links through paths, `deref()` handles
  attribute, dataset-element and record reference forms, `derefAll()`
  dereferences reference datasets, `readCompound()` reads compound datasets
  with their reference fields decoded, plus link listing and `.specloc`
  access — verified against fixtures written by hdmf-zarr 0.14.0 (pynwb
  `ElectricalSeries` with links, attribute refs, dataset refs, scalar
  datasets and zstd-compressed data; compound datasets with reference
  fields).
- **Write**: `addLink()` / `writeRefs()` / `setRefAttr()` /
  `writeCompound()` produce spec-shaped conventions (single links as JSON
  lists, consolidated metadata refreshed) — validated in CI field by field
  against the storage spec, and read back by hdmf-zarr 0.14.0.

Next: hdmf-zarr reading MATLAB-modified NWB files end-to-end, and the
MatNWB integration design. See
[matzarr/PLAN.md](https://github.com/catalystneuro/matzarr/blob/main/PLAN.md)
for the shared roadmap.

## License

MIT. A [CatalystNeuro](https://catalystneuro.com) project.
