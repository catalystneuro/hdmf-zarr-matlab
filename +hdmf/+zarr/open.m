function f = open(store)
%open - Open an hdmf-zarr formatted hierarchy (e.g. an NWB-Zarr file)
%   f = open(store) returns an hdmf.zarr.File for store, which may be
%   a folder path, a URL, or a zarr store object:
%       f = hdmf.zarr.open("session.nwb.zarr")
%       f = hdmf.zarr.open(zarr.stores.HttpStore(url))
%
%   The File supports link-following path resolution (resolve),
%   reference dereferencing (deref, derefAll), link listing (links),
%   and the write-side conventions (addLink, writeRefs, setRefAttr).
%
%   See also hdmf.zarr.File, hdmf.zarr.resolve

f = hdmf.zarr.File(zarr.internal.resolve_store(store));
end
