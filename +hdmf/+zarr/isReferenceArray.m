function tf = isReferenceArray(node)
%isReferenceArray - True if node is a dataset of object references
%   tf = isReferenceArray(node) answers whether node is a Zarr array
%   whose elements are object references rather than literal text:
%   per the hdmf-zarr conventions such a dataset has string dtype and
%   carries the attribute _DTYPE = "object_reference", or, in a store
%   written by hdmf-zarr before 0.14, zarr_dtype = "object". Decode its
%   elements with hdmf.zarr.Reference.decode(node.read()), or open the
%   targets directly with hdmf.zarr.File.derefAll.
%
%   Like other is* predicates it accepts any value and answers false
%   for anything that is not such a dataset -- including arrays whose
%   zarr_dtype is not text at all (for a compound dtype hdmf-zarr
%   wrote a list of per-field descriptors there).
%
%   See also hdmf.zarr.Reference, hdmf.zarr.File

if ~isa(node, 'zarr.Array') || node.dtype ~= "string"
    tf = false;
    return
end
% hdmf-zarr reads _DTYPE in preference to zarr_dtype
[found, dtype] = hdmf.zarr.internal.recordField(node.attrs, "_DTYPE");
if found
    tf = isTextScalar(dtype) && string(dtype) == hdmf.zarr.Reference.DatasetDtype;
    return
end
[found, dtype] = hdmf.zarr.internal.recordField(node.attrs, 'zarr_dtype');
tf = found && isTextScalar(dtype) && string(dtype) == "object";
end

function tf = isTextScalar(value)
%isTextScalar - True for a char row vector or string scalar

tf = (ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value));
end
