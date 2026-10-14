function names = referenceFields(node)
%referenceFields - Fields of a compound dataset that hold object references
%   names = referenceFields(node) returns, as a string row, the names of
%   the fields of the compound dataset node whose values are object
%   references rather than literal data. hdmf-zarr lists them in the
%   array's _REFERENCE_FIELDS attribute; a store written by hdmf-zarr
%   before 0.14 instead gives every field's type in zarr_dtype, where a
%   reference field has type "object". A compound dataset with neither
%   attribute, and a node that is not a compound dataset, has none.
%
%   The values of those fields are reference elements that
%   hdmf.zarr.Reference.decode decodes.
%
%   See also hdmf.zarr.isCompoundDataset, hdmf.zarr.CompoundDtype,
%   hdmf.zarr.File.readCompound

names = strings(1, 0);
if ~hdmf.zarr.isCompoundDataset(node)
    return
end
[found, value] = hdmf.zarr.internal.recordField(node.attrs, "_REFERENCE_FIELDS");
if found
    names = reshape(string(value), 1, []);
    return
end
[found, fieldTypes] = hdmf.zarr.internal.recordField(node.attrs, 'zarr_dtype');
if found
    dtype = hdmf.zarr.CompoundDtype.decode(fieldTypes);
    names = dtype.Names(dtype.isReferenceField());
end
end
