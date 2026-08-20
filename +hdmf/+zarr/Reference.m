classdef Reference
%Reference - An hdmf-zarr object reference, independent of any store
%   In-memory form of the {source, path, object_id, source_object_id}
%   record of the hdmf-zarr storage spec. On disk the record appears in
%   one of three forms, all accepted by decode:
%     - a JSON string: the elements of zarr_dtype:"object" datasets
%       (encodeJson)
%     - {"zarr_dtype":"object","value":<record>}: object references in
%       attributes (encodeAttribute)
%     - a record with a "name" field: entries of zarr_link lists
%       (see Link)
%
%   Only the record's shape lives here; looking up object ids and
%   following paths belong to File and resolve, so a consumer that
%   already knows its object ids need not re-traverse.
%
%   ref = Reference() creates the default reference: the root ("/") of
%   this store ("."). Array growth and decode rely on this default.
%
%   ref = Reference(path) creates a reference to the absolute node path
%   path within this store. path is normalized to a leading slash
%   ("a/b", "/a/b/" and "a//b" all become "/a/b").
%
%   ref = Reference(path,Source=source,ObjectId=id,SourceObjectId=rootId)
%   also records the source store and the object ids of the target node
%   and of the source store's root. Unknown ids ("") are omitted from
%   encoded records.
%
%   Reference functions:
%       isExternal      - True if the target lives in another store
%       encode          - Wire record(s) as struct(s)
%       encodeJson      - Wire record(s) as JSON string(s)
%       encodeAttribute - Attribute form of a scalar reference
%       decode          - (Static) Parse references from on-disk shapes
%
%   Reference properties:
%       Source         - Store the target lives in ("." is this store)
%       Path           - Absolute node path within Source
%       ObjectId       - object_id of the target node
%       SourceObjectId - object_id of the root of the source store
%
%   Example: Encode and decode a reference record
%       ref = hdmf.zarr.Reference("devices/probe0", ObjectId="abc");
%       ref.encode()      % struct with fields source, path, object_id
%       ref.encodeJson()  % the same as a JSON string
%       hdmf.zarr.Reference.decode('{"source":".","path":"/a/b"}')
%
%   See also hdmf.zarr.Link, hdmf.zarr.File, hdmf.zarr.resolve,
%   hdmf.zarr.isReferenceArray

    properties
        %Source - Store the target lives in
        %   "." is this store; anything else names another store
        %   (hdmf-zarr treats a record without "source" as external too,
        %   which decodes to "").
        Source (1,1) string = "."

        %Path - Absolute node path within Source
        %   Always normalized to a leading slash.
        Path (1,1) string = "/"

        %ObjectId - object_id of the target node ("" when not recorded)
        ObjectId (1,1) string = ""

        %SourceObjectId - object_id of the source store's root
        %   "" when not recorded.
        SourceObjectId (1,1) string = ""
    end

    methods
        function obj = Reference(path, opts)
        %Reference - Construct a reference to an absolute node path
            arguments
                path (1,1) string = "/"
                opts.Source (1,1) string = "."
                opts.ObjectId (1,1) string = ""
                opts.SourceObjectId (1,1) string = ""
            end
            obj.Path = path;
            obj.Source = opts.Source;
            obj.ObjectId = opts.ObjectId;
            obj.SourceObjectId = opts.SourceObjectId;
        end

        function obj = set.Path(obj, path)
            % Normalize so "a/b", "/a/b/" and "a//b" all become "/a/b".
            % zarr.internal.normalize_path also rejects "." / ".." segments.
            obj.Path = "/" + zarr.internal.normalize_path(path);
        end

        function tf = isExternal(obj)
        %isExternal - True if the target lives in another store
        %   tf = isExternal(obj) returns, element-wise, whether each
        %   reference targets another store. Only "." means this store;
        %   "" (a record written without a source) is external, as in
        %   hdmf-zarr's resolve_ref.
            tf = false(size(obj));
            for i = 1:numel(obj)
                tf(i) = obj(i).Source ~= ".";
            end
        end

        function s = encode(obj)
        %encode - Wire record(s) as struct(s), shaped like obj
        %   s = encode(obj) returns each element's wire record with
        %   fields source, path and, when known, object_id and
        %   source_object_id. Because ids are omitted when unknown,
        %   records can have different fields; as jsondecode does, the
        %   result is a struct array when all records share the same
        %   fields and a cell array of structs otherwise.
            records = cell(size(obj));
            for i = 1:numel(obj)
                records{i} = encodeOne(obj(i));
            end
            if isempty(records)
                s = reshape(struct('source', {}, 'path', {}), size(obj));
            elseif all(cellfun(@(r) isequal(fieldnames(r), fieldnames(records{1})), records))
                s = reshape([records{:}], size(obj));
            else
                s = records;
            end
        end

        function txt = encodeJson(obj)
        %encodeJson - Wire record(s) as JSON string(s), shaped like obj
        %   txt = encodeJson(obj) returns each element's record as a
        %   JSON string, the element format of zarr_dtype:"object"
        %   datasets.
            txt = strings(size(obj));
            for i = 1:numel(obj)
                txt(i) = string(jsonencode(encodeOne(obj(i))));
            end
        end

        function s = encodeAttribute(obj)
        %encodeAttribute - Attribute form of a scalar reference
        %   s = encodeAttribute(obj) returns the struct
        %   {zarr_dtype:"object", value:<record>} stored in node
        %   attributes. Scalar only: an attribute holds one reference.
            arguments
                obj (1,1) hdmf.zarr.Reference
            end
            s = struct('zarr_dtype', 'object', 'value', encodeOne(obj));
        end
    end

    methods (Static)
        function refs = decode(value)
        %decode - Parse reference(s) from any on-disk shape
        %   refs = decode(value) parses JSON string(s) (string array or
        %   char), attribute-form structs {zarr_dtype, value}, bare
        %   record structs, or a cell of either (what jsondecode returns
        %   for a list of records with differing fields), and returns a
        %   Reference array shaped like the input. Raises
        %   hdmf:InvalidReference for anything that is not a reference
        %   record, naming the offending element.
            arguments
                value {mustBeA(value, ["string", "char", "struct", "cell"])}
            end
            if ischar(value)
                value = string(value);
            end
            refs = repmat(hdmf.zarr.Reference(), size(value));
            for i = 1:numel(value)
                if iscell(value)
                    refs(i) = hdmf.zarr.Reference.decode(value{i});
                elseif isstring(value)
                    refs(i) = decodeOne(parseJsonRecord(value(i), i));
                else
                    refs(i) = decodeOne(value(i));
                end
            end
        end
    end
end

function record = parseJsonRecord(txt, index)
%parseJsonRecord - jsondecode one element, failing as hdmf:InvalidReference
%   Empty strings are what unwritten chunks of a string dataset read as, so
%   they are the common way to hit this; the element index locates them.
if ismissing(txt) || strlength(txt) == 0
    error("hdmf:InvalidReference", ...
        "Reference element %d is empty; the dataset may be partially written.", index);
end
try
    record = jsondecode(char(txt));
catch cause
    exception = MException("hdmf:InvalidReference", ...
        "Reference element %d is not valid JSON: %s", index, txt);
    throw(exception.addCause(cause));
end
end

function s = encodeOne(ref)
%encodeOne - Wire record for one reference
%   Ids (and an empty source) are omitted, not written as null or "",
%   matching what hdmf-zarr writes and reads.
s = struct();
if strlength(ref.Source) > 0
    s.source = char(ref.Source);
end
s.path = char(ref.Path);
if strlength(ref.ObjectId) > 0
    s.object_id = char(ref.ObjectId);
end
if strlength(ref.SourceObjectId) > 0
    s.source_object_id = char(ref.SourceObjectId);
end
end

function ref = decodeOne(s)
%decodeOne - Reference from one decoded record (bare or attribute form)
if ~isstruct(s) || ~isscalar(s)
    error("hdmf:InvalidReference", ...
        "Expected a reference record (JSON object), got %s.", class(s));
end
if isfield(s, 'zarr_dtype') && isfield(s, 'value')
    s = s.value;   % attribute form
    if ~isstruct(s)
        error("hdmf:InvalidReference", ...
            "Attribute value of zarr_dtype 'object' is not a record but %s.", class(s));
    end
end
if ~isfield(s, 'path')
    error("hdmf:InvalidReference", ...
        "Reference record has no 'path' field (fields: %s).", strjoin(fieldnames(s), ", "));
end
% Absent source means "path names another file" in hdmf-zarr: keep it
% distinguishable from "." by storing "".
ref = hdmf.zarr.Reference(textField(s, 'path'), Source=textField(s, 'source'), ...
    ObjectId=textField(s, 'object_id'), SourceObjectId=textField(s, 'source_object_id'));
end

function value = textField(s, name)
%textField - Field of s as a string; "" when absent or JSON null ([])
if isfield(s, name) && ~isempty(s.(name))
    value = string(char(s.(name)));
else
    value = "";
end
end
