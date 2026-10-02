function tf = isCompoundDataset(node)
%isCompoundDataset - True if node is a compound dataset
%   tf = isCompoundDataset(node) answers whether node is a Zarr array
%   whose elements are structs of named fields -- a DynamicTable
%   column whose rows each carry an index, a label and a reference,
%   for instance -- rather than single values. "Compound" is hdmf's
%   and HDF5's name for it; Zarr calls it a structured data type and
%   names it "struct" (or "structured", what earlier versions of
%   zarr-python wrote). hdmf-zarr names the hdmf type of each field in
%   the array's zarr_dtype attribute.
%
%   Read such a dataset with hdmf.zarr.File.readCompound, which
%   decodes the fields that hold object references; take the field
%   layout on its own with
%   hdmf.zarr.CompoundDtype.decode(node.attrs{"zarr_dtype"}).
%
%   Like other is* predicates it accepts any value and answers false
%   for anything that is not such a dataset -- including a plain
%   reference dataset, whose zarr_dtype is the text "object" rather
%   than a list of field records (see hdmf.zarr.isReferenceArray).
%
%   See also hdmf.zarr.CompoundDtype, hdmf.zarr.File,
%   hdmf.zarr.isReferenceArray

tf = isa(node, 'zarr.Array') && ismember(node.dtype, ["struct", "structured"]);
end
