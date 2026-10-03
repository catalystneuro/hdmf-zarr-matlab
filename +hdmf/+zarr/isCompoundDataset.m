function tf = isCompoundDataset(node)
%isCompoundDataset - True if node is a compound dataset
%   tf = isCompoundDataset(node) answers whether node is a Zarr array
%   whose elements are structs of named fields -- a DynamicTable
%   column whose rows each carry an index, a label and a reference,
%   for instance -- rather than single values. "Compound" is hdmf's
%   and HDF5's name for it; Zarr calls it a structured data type and
%   names it "struct" (or "structured", what earlier versions of
%   zarr-python wrote). hdmf-zarr lists the fields that hold object
%   references in the array's _REFERENCE_FIELDS attribute.
%
%   Read such a dataset with hdmf.zarr.File.readCompound, which
%   decodes the fields that hold object references and also returns
%   the field layout as an hdmf.zarr.CompoundDtype.
%
%   Like other is* predicates it accepts any value and answers false
%   for anything that is not such a dataset -- including a plain
%   reference dataset, whose Zarr data type is string (see
%   hdmf.zarr.isReferenceArray).
%
%   See also hdmf.zarr.CompoundDtype, hdmf.zarr.File,
%   hdmf.zarr.isReferenceArray

tf = isa(node, 'zarr.Array') && ismember(node.dtype, ["struct", "structured"]);
end
