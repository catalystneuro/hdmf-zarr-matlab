classdef Reference
%Reference - An hdmf-zarr store-independent object reference
%
%   A Reference is a pointer to a node in a Zarr store: which store
%   (Source) and the node's absolute path (Path). It is the in-memory
%   form of the {source, path} record with which hdmf-zarr emulates
%   HDF5's references and links.
%
%   hdmf-zarr writes a reference in one of three containers, each with
%   its own on-disk form:
%     - Reference datasets (e.g. a DynamicTable column of group
%       references): each element is the target path as plain text
%       (encodeElement), and the array carries the attribute
%       _DTYPE = "object_reference" (isReferenceArray).
%     - Reference attributes: the record wrapped as
%       {"_REFERENCE": {source, path}} (encodeAttribute).
%     - Group links: the record plus a "name" field, listed in the
%       group's _LINKS attribute -- a named reference that acts as a
%       child of the group (see hdmf.zarr.Link and hdmf.zarr.resolve).
%
%   Stores written by hdmf-zarr before 0.14 use older forms, which
%   hdmf-zarr still reads and so does decode: dataset elements that are
%   JSON records, the attribute wrapper {"zarr_dtype": "object",
%   "value": <record>}, and records that also carry object_id and
%   source_object_id. Those ids are kept in ObjectId and SourceObjectId
%   when present, but are never written.
%
%   This class only converts records between their in-memory and
%   on-disk forms; it never touches a store. To open the node a
%   reference points to, use File.deref (or resolve); to build a
%   reference to a node of a store, use File.makeReference.
%
%   ref = Reference() creates the default reference: the root ("/") of
%   this store ("."). Array growth and decode rely on this default.
%
%   ref = Reference(path) creates a reference to the absolute node path
%   path within this store. path is normalized to a leading slash
%   ("a/b", "/a/b/" and "a//b" all become "/a/b").
%
%   ref = Reference(path,Source=source) creates a reference to a node
%   of another store. ObjectId and SourceObjectId may also be given, as
%   decode does for records that carry them.
%
%   Reference functions:
%       isExternal      - True if the target lives in another store
%       encode          - On-disk {source, path} record(s) as struct(s)
%       encodeElement   - Reference dataset element(s): target paths
%       encodeAttribute - Attribute form of a scalar reference
%       decode          - (Static) Parse references from on-disk shapes
%
%   Reference properties:
%       Source         - Store the target lives in ("." is this store)
%       Path           - Absolute node path within Source
%       ObjectId       - object_id of the target, from a legacy record
%       SourceObjectId - object_id of the source root, from a legacy record
%
%   Example: Encode and decode a reference
%       ref = hdmf.zarr.Reference("devices/probe0");
%       ref.encode()          % struct with fields source, path
%       ref.encodeElement()   % "/devices/probe0"
%       hdmf.zarr.Reference.decode("/devices/probe0")
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
        %   Records written by hdmf-zarr before 0.14 carry the target's
        %   object_id; decode keeps it here. It is never written, and
        %   resolution works from the path alone.
        ObjectId (1,1) string = ""

        %SourceObjectId - object_id of the source store's root
        %   "" when not recorded. Read from legacy records, like ObjectId.
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
        %   "" (a record written without a source) is external,
        %   matching hdmf-zarr's behaviour.

            tf = false(size(obj));
            for i = 1:numel(obj)
                tf(i) = obj(i).Source ~= ".";
            end
        end

        function s = encode(obj)
        %encode - On-disk record(s) as struct(s), shaped like obj
        %   s = encode(obj) returns each element's on-disk record with
        %   fields source and path. A reference decoded from a record
        %   without a source has none to write, so the result is a
        %   struct array when all records share the same fields and,
        %   as jsondecode returns mixed records, a cell array of structs
        %   otherwise.

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

        function txt = encodeElement(obj)
        %encodeElement - Reference dataset element(s), shaped like obj
        %   txt = encodeElement(obj) returns each reference's target
        %   path as a string, the element form of a dataset marked
        %   _DTYPE = "object_reference". A bare path names a node of
        %   the same store, so this form cannot hold a reference into
        %   another store: such a reference raises
        %   hdmf:InvalidReference.

            external = obj.isExternal();
            if any(external)
                index = find(external, 1);
                error("hdmf:InvalidReference", ...
                    "Reference %d points into store '%s'. A reference dataset can only " + ...
                    "hold references to nodes of its own store.", index, obj(index).Source);
            end
            txt = strings(size(obj));
            for i = 1:numel(obj)
                txt(i) = obj(i).Path;
            end
        end

        function d = encodeAttribute(obj)
        %encodeAttribute - Attribute form of a scalar reference
        %   d = encodeAttribute(obj) returns {"_REFERENCE": <record>},
        %   the value hdmf-zarr stores in a node attribute, as a
        %   dictionary: "_REFERENCE" is not a valid struct field name.
        %   Scalar only: an attribute holds one reference.

            arguments
                obj (1,1) hdmf.zarr.Reference
            end
            d = dictionary(string.empty, {});
            d(hdmf.zarr.Reference.AttributeKey) = {encodeOne(obj)};
        end
    end

    properties (Constant, Hidden)
        %AttributeKey - Key that wraps a reference stored in an attribute
        AttributeKey = "_REFERENCE"

        %DatasetDtype - _DTYPE value that marks a dataset of references
        DatasetDtype = "object_reference"
    end

    methods (Static)
        function refs = decode(value)
        %decode - Parse reference(s) from any on-disk shape
        %   refs = decode(value) parses reference dataset elements
        %   (string array or char), attribute-form records, bare
        %   records, or a cell of these, and returns a Reference array
        %   shaped like the input -- e.g. decode(node.read()) for a
        %   reference dataset, or decode(group.attrs{"table"}) for a
        %   reference attribute.
        %
        %   A text element is a target path in this store, or, in a
        %   store written by hdmf-zarr before 0.14, a JSON record; text
        %   starting with "{" is read as the latter. An attribute-form
        %   record is {"_REFERENCE": <record>}, or the legacy
        %   {"zarr_dtype": "object", "value": <record>}. A record is a
        %   dictionary when it came from a store and a scalar struct
        %   when it was built in MATLAB; both are accepted. Raises
        %   hdmf:InvalidReference for anything that is not a
        %   reference, naming the offending element.

            arguments
                value {mustBeA(value, ["string", "char", "struct", "cell", "dictionary"])}
            end
            if ischar(value)
                value = string(value);
            end
            if isa(value, 'dictionary')
                % A dictionary is one record. It is also 1x1, so the loop
                % below would reach it -- but value(1) on a dictionary looks
                % up the key 1 rather than indexing an element, so it has to
                % be taken before the loop.
                refs = decodeOne(value);
                return
            end
            refs = repmat(hdmf.zarr.Reference(), size(value));
            for i = 1:numel(value)
                if iscell(value)
                    refs(i) = hdmf.zarr.Reference.decode(value{i});
                elseif isstring(value)
                    refs(i) = decodeElement(value(i), i);
                else
                    refs(i) = decodeOne(value(i));
                end
            end
        end
    end
end

function ref = decodeElement(txt, index)
%decodeElement - Reference from one text element of a reference dataset
%   hdmf-zarr writes the target path as plain text; before 0.14 it wrote a
%   JSON record. A node path never starts with "{", and a JSON record
%   always does, so that character tells the two apart. Empty strings are
%   what unwritten chunks of a string dataset read as, so they are the
%   common way to hit an error here; the element index locates them.

if ismissing(txt) || strlength(strtrim(txt)) == 0
    error("hdmf:InvalidReference", ...
        "Reference element %d is empty; the dataset may be partially written.", index);
end
if ~startsWith(strtrim(txt), "{")
    ref = hdmf.zarr.Reference(txt);
    return
end
try
    record = jsondecode(char(txt));
catch cause
    exception = MException("hdmf:InvalidReference", ...
        "Reference element %d is not valid JSON: %s", index, txt);
    throw(exception.addCause(cause));
end
ref = decodeOne(record);
end

function s = encodeOne(ref)
%encodeOne - On-disk record for one reference
%   An empty source is omitted rather than written as "": a record
%   without a source is what hdmf-zarr reads as pointing into another
%   file, and "" would not round-trip to that.

s = struct();
if strlength(ref.Source) > 0
    s.source = char(ref.Source);
end
s.path = char(ref.Path);
end

function ref = decodeOne(s)
%decodeOne - Reference from one decoded record (bare or attribute form)

if ~hdmf.zarr.internal.isRecord(s)
    error("hdmf:InvalidReference", ...
        "Expected a reference record (JSON object), got %s.", class(s));
end
[isWrapped, inner] = hdmf.zarr.internal.recordField(s, hdmf.zarr.Reference.AttributeKey);
if ~isWrapped
    % Attribute form written by hdmf-zarr before 0.14
    hasLegacyDtype = hdmf.zarr.internal.recordField(s, 'zarr_dtype');
    [hasValue, inner] = hdmf.zarr.internal.recordField(s, 'value');
    isWrapped = hasLegacyDtype && hasValue;
end
if isWrapped
    s = inner;
    if ~hdmf.zarr.internal.isRecord(s)
        error("hdmf:InvalidReference", ...
            "Attribute-form reference wraps %s, not a record.", class(s));
    end
end
hasPath = hdmf.zarr.internal.recordField(s, 'path');
if ~hasPath
    error("hdmf:InvalidReference", ...
        "Reference record has no 'path' field (fields: %s).", ...
        strjoin(recordFieldNames(s), ", "));
end
% Absent source means "path names another file" in hdmf-zarr: keep it
% distinguishable from "." by storing "".
ref = hdmf.zarr.Reference(textField(s, 'path'), Source=textField(s, 'source'), ...
    ObjectId=textField(s, 'object_id'), SourceObjectId=textField(s, 'source_object_id'));
end

function value = textField(s, name)
%textField - Field of s as a string; "" when absent or JSON null ([])

[found, raw] = hdmf.zarr.internal.recordField(s, name);
if found && ~isempty(raw)
    value = string(char(raw));
else
    value = "";
end
end

function names = recordFieldNames(s)
%recordFieldNames - Field names of a record, for an error message

if isa(s, 'dictionary')
    names = keys(s);
else
    names = string(fieldnames(s));
end
names = reshape(names, 1, []);
end
