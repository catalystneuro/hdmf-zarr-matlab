function tf = isReferenceArray(node)
%ISREFERENCEARRAY - True if node is a dataset of object references.
%   Per the hdmf-zarr conventions such a dataset has string dtype, each
%   element a JSON reference record, and is tagged with the attribute
%   zarr_dtype = "object". Decode its elements with
%   hdmf.zarr.Reference.decode(node.read()). Like other is* predicates it
%   accepts any value and answers false for anything that is not such a
%   dataset.

tf = isa(node, 'zarr.Array') && isfield(node.attrs, 'zarr_dtype') && ...
    string(char(node.attrs.zarr_dtype)) == "object" && node.dtype == "string";
end
