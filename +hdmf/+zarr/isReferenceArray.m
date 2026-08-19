function tf = isReferenceArray(node)
%ISREFERENCEARRAY - True if node is a dataset of object references.
%   Per the hdmf-zarr conventions such a dataset has string dtype, each
%   element a JSON reference record, and is tagged with the attribute
%   zarr_dtype = "object". Decode its elements with
%   hdmf.zarr.Reference.decode(node.read()). Like other is* predicates it
%   accepts any value and answers false for anything that is not such a
%   dataset -- including arrays whose zarr_dtype is not text at all (for a
%   compound dtype hdmf-zarr writes a list of per-field descriptors there).

tf = isa(node, 'zarr.Array') && node.dtype == "string" && ...
    isfield(node.attrs, 'zarr_dtype') && isTextScalar(node.attrs.zarr_dtype) && ...
    string(node.attrs.zarr_dtype) == "object";
end

function tf = isTextScalar(value)
tf = (ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value));
end
