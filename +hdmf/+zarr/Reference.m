classdef Reference
    %REFERENCE An hdmf-zarr object reference, independent of any store.
    %   The canonical in-memory form of the {source, path, object_id,
    %   source_object_id} record defined by the hdmf-zarr storage spec
    %   (https://hdmf-zarr.readthedocs.io/en/latest/storage.html).
    %
    %   A reference appears on disk in three shapes; decode accepts all of
    %   them and the encode* methods produce each:
    %     - bare record:       {"source": ".", "path": "/a/b", ...}
    %                          (one element of a zarr_dtype:"object" dataset,
    %                          stored as a JSON string; see encodeJson)
    %     - attribute form:    {"zarr_dtype": "object", "value": <record>}
    %                          (see encodeAttribute)
    %     - zarr_link entry:   <record> plus "name" (see hdmf.zarr.Link)
    %
    %   Only the shape of the record lives here. Looking up object ids or
    %   following the path to a node is the job of hdmf.zarr.File /
    %   hdmf.zarr.resolve, so consumers that already know their object ids
    %   (e.g. MatNWB) can build references without a second traversal.
    %
    %   Example:
    %     ref = hdmf.zarr.Reference("general/devices/probe0", ObjectId="abc");
    %     ref.encode()          % struct('source','.','path','/general/...',...)
    %     ref.encodeJson()      % the same as a JSON string
    %     hdmf.zarr.Reference.decode('{"source":".","path":"/a/b"}')

    properties
        % Store the target lives in: "." means this store.
        Source (1,1) string = "."
        % Absolute node path within Source, always with a leading slash.
        Path (1,1) string = "/"
        % object_id of the target node (missing when not recorded).
        ObjectId (1,1) string = missing
        % object_id of the root of the source store (missing when not recorded).
        SourceObjectId (1,1) string = missing
    end

    methods
        function obj = Reference(path, opts)
            %REFERENCE Construct a reference to an absolute node path.
            %   hdmf.zarr.Reference(path)
            %   hdmf.zarr.Reference(path, Source=, ObjectId=, SourceObjectId=)
            %   hdmf.zarr.Reference() yields the default (root of this store),
            %   which is what array growth and decode rely on.
            arguments
                path (1,1) string = "/"
                opts.Source (1,1) string = "."
                opts.ObjectId (1,1) string = missing
                opts.SourceObjectId (1,1) string = missing
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
            %ISEXTERNAL True if the target lives in another store. Element-wise.
            tf = false(size(obj));
            for i = 1:numel(obj)
                tf(i) = obj(i).Source ~= "." && strlength(obj(i).Source) > 0;
            end
        end

        function s = encode(obj)
            %ENCODE Wire record: struct with fields source, path and, when
            %   known, object_id / source_object_id. Scalar only, because
            %   records with and without ids cannot form one struct array;
            %   use encodeJson for arrays.
            arguments
                obj (1,1) hdmf.zarr.Reference
            end
            s = encodeOne(obj);
        end

        function txt = encodeJson(obj)
            %ENCODEJSON Wire record(s) as JSON string(s), shaped like obj.
            %   This is the element format of zarr_dtype:"object" datasets.
            txt = strings(size(obj));
            for i = 1:numel(obj)
                txt(i) = string(jsonencode(encodeOne(obj(i))));
            end
        end

        function s = encodeAttribute(obj)
            %ENCODEATTRIBUTE Attribute form {zarr_dtype:"object", value:<record>}.
            %   Scalar only: an attribute holds one reference.
            arguments
                obj (1,1) hdmf.zarr.Reference
            end
            s = struct('zarr_dtype', 'object', 'value', encodeOne(obj));
        end
    end

    methods (Static)
        function refs = decode(value)
            %DECODE Parse reference(s) from any on-disk shape.
            %   value may be a JSON string (or string array / char), the
            %   attribute form {zarr_dtype, value}, a bare record struct, or
            %   a struct array / cell of either. Returns a Reference array
            %   shaped like the input. Link entries (with a "name" field)
            %   decode too; the name is simply ignored — use hdmf.zarr.Link
            %   to keep it.
            if ischar(value)
                value = string(value);
            end
            if ~(isstring(value) || iscell(value) || isstruct(value))
                error("hdmf:InvalidReference", ...
                    "Cannot decode a reference from a %s. Expected a JSON string or a struct.", ...
                    class(value));
            end
            refs = repmat(hdmf.zarr.Reference(), size(value));
            for i = 1:numel(value)
                if isstring(value)
                    refs(i) = decodeOne(jsondecode(char(value(i))));
                elseif iscell(value)
                    refs(i) = hdmf.zarr.Reference.decode(value{i});
                else
                    refs(i) = decodeOne(value(i));
                end
            end
        end
    end
end

function s = encodeOne(ref)
% Ids are omitted (not written as null) when unknown, matching hdmf-zarr.
s = struct('source', char(ref.Source), 'path', char(ref.Path));
if ~ismissing(ref.ObjectId)
    s.object_id = char(ref.ObjectId);
end
if ~ismissing(ref.SourceObjectId)
    s.source_object_id = char(ref.SourceObjectId);
end
end

function ref = decodeOne(s)
if isfield(s, 'zarr_dtype') && isfield(s, 'value')
    s = s.value;   % attribute form
end
if ~isfield(s, 'path')
    error("hdmf:InvalidReference", ...
        "Reference record has no 'path' field (fields: %s).", strjoin(fieldnames(s), ", "));
end
ref = hdmf.zarr.Reference(string(char(s.path)));
if isfield(s, 'source')
    ref.Source = string(char(s.source));
end
if isfield(s, 'object_id') && ~isempty(s.object_id)
    ref.ObjectId = string(char(s.object_id));
end
if isfield(s, 'source_object_id') && ~isempty(s.source_object_id)
    ref.SourceObjectId = string(char(s.source_object_id));
end
end
