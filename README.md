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

## MATLAB API

The `hdmf.zarr` namespace is the stable integration boundary for storage
backends such as MatNWB. It operates on neutral MATLAB structs and raw Zarr
metadata; consumers remain responsible for mapping records to their own domain
objects.

- `encodeReference` / `decodeReference` handle same-store and external object
  reference records, JSON array elements, and attribute wrappers.
- `encodeLinks` / `decodeLinks` handle `zarr_link` list values, including
  singleton and external link records.
- `isReferenceArray` identifies string arrays marked with
  `zarr_dtype: "object"`.
- `readSpecLocation` / `writeSpecLocation` preserve the exact `.specloc` key
  in root metadata.
- `refreshConsolidatedMetadata` refreshes existing consolidated metadata
  without changing an unconsolidated store.

Region references are rejected explicitly because HDMF-Zarr does not yet
define a complete interoperable storage representation for their selections.
The higher-level `hdmf.zarr.File` facade delegates encoding and decoding to
these functions while continuing to provide node resolution helpers.

The tested Zarr dependency is `catalystneuro/zarr-matlab` v0.3.1.

## Status

**Read and write layers implemented and CI-verified.**

- **Read**: `resolve()` follows `zarr_link` entries through paths, `deref()`
  handles attribute/JSON/struct reference forms, `derefAll()` dereferences
  reference datasets, plus link listing and `.specloc` access — verified
  against an NWB-Zarr fixture written by the pinned hdmf-zarr
  `zarr-v3-migration` branch (pynwb `ElectricalSeries` with links,
  attribute refs, dataset refs, and zstd-compressed data).
- **Write**: `addLink()` / `writeRefs()` / `setRefAttr()` produce
  spec-shaped conventions (object ids included, single links as JSON
  lists, consolidated metadata refreshed) — validated in CI by a
  zarr-python inspector, field by field against the storage spec.

Next: hdmf-zarr reading MATLAB-modified NWB files end-to-end, and the
MatNWB integration design. See
[matzarr/PLAN.md](https://github.com/catalystneuro/matzarr/blob/main/PLAN.md)
for the shared roadmap.

## License

MIT. A [CatalystNeuro](https://catalystneuro.com) project.
