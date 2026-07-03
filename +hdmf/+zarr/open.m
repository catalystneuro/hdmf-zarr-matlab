function f = open(store)
%OPEN Open an hdmf-zarr formatted hierarchy (e.g. an NWB-Zarr file).
%   f = hdmf.zarr.open("session.nwb.zarr")
%   f = hdmf.zarr.open(zarr.stores.HttpStore("https://.../session.nwb.zarr"))
%
%   Returns an hdmf.zarr.File supporting link-following path resolution
%   (resolve), reference dereferencing (deref/readRefs), and link listing.

f = hdmf.zarr.File(zarr.internal.resolve_store(store));
end
