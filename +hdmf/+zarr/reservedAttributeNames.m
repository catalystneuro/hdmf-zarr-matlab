function names = reservedAttributeNames()
%reservedAttributeNames - Attribute names that carry hdmf-zarr conventions
%   names = reservedAttributeNames() returns, as a string row, the
%   attribute names hdmf-zarr uses for its own bookkeeping rather than
%   for data: _LINKS (a group's links), _DTYPE (the hdmf data type of a
%   dataset, which marks a dataset of references), _REFERENCE_FIELDS
%   (the reference fields of a compound dataset), .specloc (the cached
%   specifications group) and _ARRAY_DIMENSIONS (the dimension names of
%   a dataset, in the xarray convention), plus zarr_link and zarr_dtype,
%   which stores written by hdmf-zarr before 0.14 use instead. A reader
%   that presents a node's attributes as data leaves these out.
%
%   Example: Data attributes of a node
%       names = keys(node.attrs);
%       names = names(~ismember(names, hdmf.zarr.reservedAttributeNames()));
%
%   See also hdmf.zarr.Link, hdmf.zarr.isReferenceArray,
%   hdmf.zarr.referenceFields, hdmf.zarr.specLoc

names = [hdmf.zarr.Link.AttributeName, "_DTYPE", "_REFERENCE_FIELDS", ...
    ".specloc", "_ARRAY_DIMENSIONS", hdmf.zarr.Link.LegacyAttributeName, "zarr_dtype"];
end
