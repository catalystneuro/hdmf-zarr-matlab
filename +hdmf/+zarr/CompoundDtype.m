classdef CompoundDtype
%CompoundDtype - The field layout of an hdmf-zarr compound dataset
%
%   A compound dataset stores one struct per element rather than one
%   number: a DynamicTable column whose rows each carry an index, a
%   label and a reference, for instance. "Compound" is hdmf's and
%   HDF5's name for it; Zarr calls the same thing a structured data
%   type and writes it as data_type "struct". On top of that,
%   hdmf-zarr adds a zarr_dtype attribute naming the hdmf type of each
%   field. A CompoundDtype is the in-memory form of that pair -- the
%   field names, their hdmf types, and how much room text fields get.
%
%   Two things make the pair more than a restatement of each other.
%   Object references have no Zarr type: hdmf-zarr writes each one as
%   a JSON record (see hdmf.zarr.Reference) into an ordinary
%   fixed-length text field, and only the zarr_dtype entry "object"
%   says that a field holds references rather than literal text. And
%   because those fields are fixed-length, they are sized to the data
%   with room to spare, so that rows can be appended later without
%   rewriting the dataset.
%
%   This class only converts a layout between its in-memory and
%   on-disk forms; it never touches a store. To read or write a
%   compound dataset, use hdmf.zarr.File.readCompound and
%   hdmf.zarr.File.writeCompound, which use this class internally.
%
%   dtype = CompoundDtype(names, types) describes fields named names
%   (a string array) with hdmf types types (a string array of the same
%   length): "int8" to "int64", "uint8" to "uint64", "float32",
%   "float64", "bool_", "str_" for text, or "object" for a field of
%   object references.
%
%   dtype = CompoundDtype(names, types, StringChars=n) also sets the
%   capacity, in characters, of each text and reference field. n is
%   either one value for all such fields or one per field (values for
%   other fields are ignored). The default, 512, is hdmf-zarr's
%   minimum; CompoundDtype.fromData widens it to fit the data.
%
%   CompoundDtype functions:
%       isReferenceField - True for each field that holds references
%       encodeAttribute  - On-disk zarr_dtype attribute value
%       encodeDataType   - On-disk Zarr data_type of the array
%       decode           - (Static) Layout from a zarr_dtype value
%       fromData         - (Static) Layout inferred from a struct array
%
%   CompoundDtype properties:
%       Names       - Field names, in storage order
%       Types       - hdmf type of each field
%       StringChars - Capacity of each text/reference field
%
%   Example: Describe a table of references and read one back
%       dtype = hdmf.zarr.CompoundDtype(["idx", "electrode"], ...
%           ["int32", "object"]);
%       dtype.isReferenceField()   % [false true]
%
%   See also hdmf.zarr.Reference, hdmf.zarr.File,
%   hdmf.zarr.isCompoundDataset

    properties
        %Names - Field names, in storage order
        Names (1,:) string

        %Types - hdmf type of each field
        %   One of the integer or float type names, "bool_", "str_" for
        %   text, or "object" for a field of object references.
        Types (1,:) string

        %StringChars - Capacity of each text/reference field, in characters
        %   Meaningless for other fields, which are fixed-size already.
        %   Text is stored as UTF-32, so a field occupies four bytes per
        %   character of capacity whether or not the rows use it.
        StringChars (1,:) double
    end

    properties (Constant)
        %MinStringChars - Smallest capacity hdmf-zarr gives a text field
        %   hdmf-zarr's COMPOUND_DTYPE_MIN_STRING_LENGTH. Text fields are
        %   never narrower than this, however short the data, so that
        %   appended rows have room for longer values.
        MinStringChars = 512
    end

    methods
        function obj = CompoundDtype(names, types, opts)
        %CompoundDtype - Describe the fields of a compound dataset

            arguments
                names (1,:) string
                types (1,:) string
                opts.StringChars (1,:) double {mustBePositive, mustBeInteger} = ...
                    hdmf.zarr.CompoundDtype.MinStringChars
            end
            if numel(names) ~= numel(types)
                error("hdmf:InvalidCompoundDtype", ...
                    "Got %d field names but %d types; a compound dtype needs one type per field.", ...
                    numel(names), numel(types));
            end
            if isempty(names)
                error("hdmf:InvalidCompoundDtype", "A compound dtype needs at least one field.");
            end
            obj.Names = names;
            obj.Types = types;
            if isscalar(opts.StringChars)
                obj.StringChars = repmat(opts.StringChars, 1, numel(names));
            elseif numel(opts.StringChars) == numel(names)
                obj.StringChars = opts.StringChars;
            else
                error("hdmf:InvalidCompoundDtype", ...
                    "StringChars must be one value or one per field (%d), got %d.", ...
                    numel(names), numel(opts.StringChars));
            end
        end

        function tf = isReferenceField(obj)
        %isReferenceField - True for each field that holds references
        %   tf = isReferenceField(obj) returns a logical row, one entry
        %   per field, marking the fields whose elements are JSON
        %   reference records rather than literal text. Decode those
        %   with hdmf.zarr.Reference.decode.

            tf = obj.Types == "object";
        end

        function value = encodeAttribute(obj)
        %encodeAttribute - On-disk zarr_dtype attribute value
        %   value = encodeAttribute(obj) returns the list of
        %   {name, dtype} records hdmf-zarr stores in zarr_dtype, as a
        %   cell array of structs so that it encodes as a JSON list
        %   even when the dataset has a single field.

            value = cell(1, numel(obj.Names));
            for i = 1:numel(obj.Names)
                value{i} = struct('name', char(obj.Names(i)), 'dtype', char(obj.Types(i)));
            end
        end

        function dataType = encodeDataType(obj)
        %encodeDataType - On-disk Zarr data_type of the array
        %   dataType = encodeDataType(obj) returns the structured
        %   ("struct") data_type, as the {name, configuration} struct
        %   that zarr.create accepts. Text and reference fields become
        %   fixed_length_utf32 of StringChars characters; every other
        %   field becomes its plain Zarr data type.

            fields = struct('name', cell(numel(obj.Names), 1), 'data_type', cell(numel(obj.Names), 1));
            for i = 1:numel(obj.Names)
                fields(i).name = char(obj.Names(i));
                fields(i).data_type = fieldDataType(obj.Types(i), obj.StringChars(i));
            end
            dataType = struct('name', "struct", 'configuration', struct('fields', fields));
        end
    end

    methods (Static)
        function obj = decode(value)
        %decode - Layout from a zarr_dtype attribute value
        %   obj = decode(value) parses the list of {name, dtype}
        %   records hdmf-zarr writes to zarr_dtype -- as jsondecode
        %   returns it, so a struct array or a cell array of structs --
        %   e.g. decode(node.attrs.zarr_dtype). Raises
        %   hdmf:InvalidCompoundDtype for a zarr_dtype that is not such
        %   a list, including the plain "object" of a (non-compound)
        %   reference dataset.
        %
        %   Capacities are not recorded in zarr_dtype: a decoded layout
        %   reports the field capacities of the array it came from only
        %   after encodeDataType has been given them, so decode leaves
        %   StringChars at its default. It is the array's own data_type
        %   that governs what a read or write actually uses.

            if isstruct(value)
                value = num2cell(value);
            end
            if ~iscell(value) || isempty(value)
                error("hdmf:InvalidCompoundDtype", ...
                    "zarr_dtype is %s, not a list of field records; the dataset is not compound.", ...
                    class(value));
            end
            names = strings(1, numel(value));
            types = strings(1, numel(value));
            for i = 1:numel(value)
                entry = value{i};
                if ~isstruct(entry) || ~isscalar(entry) || ~isfield(entry, 'name') || ~isfield(entry, 'dtype')
                    error("hdmf:InvalidCompoundDtype", ...
                        "Field %d of zarr_dtype is not a {name, dtype} record.", i);
                end
                names(i) = string(char(entry.name));
                types(i) = string(char(entry.dtype));
            end
            obj = hdmf.zarr.CompoundDtype(names, types);
        end

        function obj = fromData(records, opts)
        %fromData - Layout inferred from a struct array of rows
        %   obj = fromData(records) reads the field names and types off
        %   a struct array: numeric and logical fields keep their MATLAB
        %   class, string and char fields become "str_", and fields of
        %   hdmf.zarr.Reference become "object". Text and reference
        %   fields are sized to the longest value they hold, but never
        %   below MinStringChars.
        %
        %   obj = fromData(records, Types=types) instead declares the
        %   hdmf type of every field, leaving only the sizing to the
        %   data. Use it when the data does not pin the type down --
        %   MATLAB doubles standing in for float32, say.

            arguments
                records struct
                opts.Types (1,:) string = string.empty
            end
            names = string(fieldnames(records))';
            if isempty(names)
                error("hdmf:InvalidCompoundDtype", ...
                    "A compound dtype needs at least one field, but the data has none.");
            end
            if isempty(opts.Types)
                types = arrayfun(@(n) hdmfTypeOf(records, n), names);
            else
                types = opts.Types;
            end
            obj = hdmf.zarr.CompoundDtype(names, types);
            obj.StringChars = arrayfun(@(i) capacityFor(records, names(i), types(i)), ...
                1:numel(names));
        end
    end
end

function dataType = fieldDataType(type, stringChars)
%FIELDDATATYPE Zarr data_type of one field of a compound dataset.
%   Object references have no Zarr type of their own: they travel as
%   JSON text, so they take the same fixed-length text type as "str_".

switch type
    case {"str_", "str", "text", "utf", "utf8", "utf-8", "isodatetime", "object"}
        dataType = struct('name', "fixed_length_utf32", ...
            'configuration', struct('length_bytes', 4 * stringChars));
    case {"bool_", "bool", "logical"}
        dataType = 'bool';
    case {"int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64"}
        dataType = char(type);
    case {"float32", "single"}
        dataType = 'float32';
    case {"float64", "double"}
        dataType = 'float64';
    otherwise
        error("hdmf:InvalidCompoundDtype", ...
            "Unsupported compound field type '%s'.", type);
end
end

function type = hdmfTypeOf(records, name)
%HDMFTYPEOF hdmf type name for one field of a struct array of rows.

value = records(1).(name);
if isa(value, 'hdmf.zarr.Reference')
    type = "object";
elseif isstring(value) || ischar(value)
    type = "str_";
elseif islogical(value)
    type = "bool_";
elseif isa(value, 'double')
    type = "float64";
elseif isa(value, 'single')
    type = "float32";
elseif isinteger(value)
    type = string(class(value));
else
    error("hdmf:InvalidCompoundDtype", ...
        "Field '%s' has class %s, which has no hdmf compound type.", name, class(value));
end
end

function chars = capacityFor(records, name, type)
%CAPACITYFOR Characters to reserve for one field, from the rows it holds.
%   Reference fields are measured as the JSON records they become, not as
%   the paths they point at.

chars = hdmf.zarr.CompoundDtype.MinStringChars;
if ~ismember(type, ["str_", "str", "text", "utf", "utf8", "utf-8", "isodatetime", "object"])
    return
end
for i = 1:numel(records)
    value = records(i).(name);
    if isa(value, 'hdmf.zarr.Reference')
        value = value.encodeJson();
    end
    chars = max(chars, max(strlength(string(value)), 0));
end
end
