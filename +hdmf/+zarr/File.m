classdef File < handle
%File - An hdmf-zarr hierarchy: a Zarr store plus links and references
%
%   File binds a Zarr store to the store-independent conventions layer
%   (hdmf.zarr.Reference, hdmf.zarr.Link, hdmf.zarr.resolve) and adds
%   everything that needs the store: opening the root, following paths
%   and links to nodes, dereferencing references, looking up object ids
%   when building references, writing links, reference datasets and
%   reference attributes, and refreshing consolidated metadata after
%   mutations. Consumers with their own file model (e.g. MatNWB) can
%   use the conventions layer directly and skip File.
%
%   f = File(store) opens the hierarchy rooted at store, a zarr store
%   object (e.g. zarr.stores.LocalStore). For a folder path or URL,
%   use hdmf.zarr.open, which resolves it to a store first.
%
%   File functions:
%       resolve       - Open the node at a path or Reference
%       deref         - Resolve a reference to its node
%       derefAll      - Dereference a whole reference dataset
%       readCompound  - Read a compound dataset, references decoded
%       links         - Links a group declares, as a Link array
%       addLink       - Add a soft link to a group
%       writeRefs     - Create a reference dataset
%       writeCompound - Create a compound dataset
%       setRefAttr    - Store an object reference in an attribute
%       makeReference - Reference to a node of this store
%       refresh       - Re-read the root after mutations
%       specLoc       - Path of the cached specifications group
%
%   File properties:
%       store - The underlying zarr store object
%       root  - zarr.Group at the top of the hierarchy
%
%   Example: Create a store, add a link, follow it
%       s = tempname + ".zarr";
%       g = zarr.create_group(s);
%       g.createGroup("devices").createGroup("probe0");
%       f = hdmf.zarr.open(s);
%       f.addLink("/", "probe", "devices/probe0");
%       f.resolve("probe").path   % "devices/probe0"
%
%   See also hdmf.zarr.open, hdmf.zarr.Reference, hdmf.zarr.Link,
%   hdmf.zarr.resolve

    properties (SetAccess = private)
        %store - The underlying zarr store object
        store

        %root - zarr.Group at the top of the hierarchy
        root
    end

    methods
        function obj = File(store)
        %File - Open the hierarchy rooted at store

            obj.store = store;
            obj.root = zarr.open(store);
            if ~isa(obj.root, 'zarr.Group')
                error("hdmf:InvalidFile", "Root node is not a group.");
            end
        end

        function node = resolve(obj, target)
        %resolve - Open the node at a path or Reference, following links
        %   node = resolve(obj, target) opens the node target points
        %   to; target is a path ("general/devices/probe0") or a
        %   scalar hdmf.zarr.Reference. Links along the path are
        %   followed transparently. See hdmf.zarr.resolve.

            node = hdmf.zarr.resolve(obj.root, target);
        end

        function linkList = links(obj, groupOrPath)
        %links - Links a group declares, as a Link array
        %   linkList = links(obj, groupOrPath) returns the links
        %   declared by a group (a zarr.Group or a path to one) in its
        %   _LINKS attribute, or the legacy zarr_link, as an
        %   hdmf.zarr.Link array; 1x0 if the group declares none.

            group = obj.asNode(groupOrPath);
            linkList = hdmf.zarr.Link.fromAttributes(group.attrs);
        end

        function node = deref(obj, ref)
        %deref - Resolve a reference to its node
        %   node = deref(obj, ref) opens the node ref points to. ref
        %   may be an hdmf.zarr.Reference or any on-disk form accepted
        %   by hdmf.zarr.Reference.decode (dataset element, attribute-form
        %   record, bare record).

            arguments
                obj
                ref {mustBeA(ref, ["hdmf.zarr.Reference", "string", "char", "struct", "dictionary"])}
            end
            if ~isa(ref, 'hdmf.zarr.Reference')
                ref = hdmf.zarr.Reference.decode(ref);
            end
            node = obj.resolve(ref);
        end

        function nodes = derefAll(obj, refArrayOrValues)
        %derefAll - Dereference every element of a reference dataset
        %   nodes = derefAll(obj, refArrayOrValues) opens the target of
        %   each reference and returns them as a cell array shaped like
        %   the input, which may be the zarr.Array itself, its read()
        %   values, or a Reference array. Each distinct path is
        %   resolved once: reference columns typically repeat a few
        %   targets many times.

            arguments
                obj
                refArrayOrValues {mustBeA(refArrayOrValues, ...
                    ["zarr.Array", "hdmf.zarr.Reference", "string", "char", "struct", "cell", ...
                     "dictionary"])}
            end
            refs = refArrayOrValues;
            if isa(refs, 'zarr.Array')
                refs = refs.read();
            end
            if ~isa(refs, 'hdmf.zarr.Reference')
                refs = hdmf.zarr.Reference.decode(refs);
            end
            % External references have no in-store path to share; resolve
            % them individually so the error names the offending element.
            if any(refs.isExternal())
                nodes = arrayfun(@(r) obj.resolve(r), refs, UniformOutput=false);
                return
            end
            [uniquePaths, ~, pathIndex] = unique([refs.Path]);
            uniqueNodes = cell(size(uniquePaths));
            for i = 1:numel(uniquePaths)
                uniqueNodes{i} = obj.resolve(uniquePaths(i));
            end
            nodes = reshape(uniqueNodes(pathIndex), size(refs));
        end

        function [records, dtype] = readCompound(obj, target)
        %readCompound - Read a compound dataset, references decoded
        %   records = readCompound(obj, target) reads the compound
        %   dataset at target (a path or a zarr.Array) and returns its
        %   rows as a struct array with one field per record field.
        %   Fields that hold object references come back as
        %   hdmf.zarr.Reference arrays rather than as the text they are
        %   stored as; every other field keeps the class its Zarr type
        %   gives it. Convert the result with struct2table
        %   if a table suits the caller better.
        %
        %   [records, dtype] = readCompound(obj, target) also returns
        %   the field layout as an hdmf.zarr.CompoundDtype, which says
        %   which fields hold references.
        %
        %   To open what a reference field points at, pass the column
        %   to derefAll: derefAll(f, [records.electrode]).

            node = obj.asNode(target);
            if ~hdmf.zarr.isCompoundDataset(node)
                error("hdmf:NotCompoundDataset", ...
                    "Dataset '%s' has data type '%s', not a compound (structured) type.", ...
                    node.path, node.dtype);
            end
            records = node.read();
            dtype = compoundDtypeOf(node, records);
            referenceFields = dtype.Names(dtype.isReferenceField());
            for name = referenceFields
                values = hdmf.zarr.Reference.decode([records.(name)]);
                for i = 1:numel(records)
                    records(i).(name) = values(i);
                end
            end
        end

        % ------------------------------------------------------------------
        % Write side: create links and references per the conventions.

        function addLink(obj, groupPath, name, target)
        %addLink - Add a soft link: group's _LINKS gains an entry
        %   addLink(obj, groupPath, name, target) makes target (a path
        %   or node in this store) appear as the child name of the
        %   group at groupPath, e.g.
        %   addLink(f, "analysis", "device", "general/devices/probe0")
        %
        %   A group that lists its links under the legacy zarr_link
        %   name has them copied into _LINKS along with the new one:
        %   readers take _LINKS alone when it is present.

            arguments
                obj
                groupPath (1,1) string
                name (1,1) string
                target
            end
            group = obj.resolve(groupPath);
            if ~isa(group, 'zarr.Group')
                error("hdmf:WriteError", "'%s' is not a group.", groupPath);
            end
            % Append to the raw list rather than decoding and re-encoding the
            % existing entries, so records written by other tools keep any
            % fields this library does not model.
            existing = hdmf.zarr.Link.rawEntries(group.attrs);
            newLink = hdmf.zarr.Link(name, obj.makeReference(target));
            group.setAttr(hdmf.zarr.Link.AttributeName, [existing, newLink.encode()]);
            obj.refresh();
        end

        function refDataset = writeRefs(obj, path, targets, opts)
        %writeRefs - Create a reference dataset (_DTYPE "object_reference")
        %   refDataset = writeRefs(obj, path, targets) writes a
        %   string-dtype array at path holding the path of each element
        %   of targets (paths or nodes in this store), e.g.
        %   writeRefs(f, "table/col", ["a/b", "a/c"])
        %
        %   refDataset = writeRefs(obj, path, targets, Attributes=attrs)
        %   also sets additional attributes on the new dataset.

            arguments
                obj
                path (1,1) string
                targets
                opts.Attributes {mustBeA(opts.Attributes, ["struct", "dictionary"])} = struct()
            end
            if ~iscell(targets)
                targets = num2cell(targets);
            end
            numTargets = numel(targets);
            refs = repmat(hdmf.zarr.Reference(), numTargets, 1);
            for i = 1:numTargets
                refs(i) = obj.makeReference(targets{i});
            end
            attributes = withAttribute(opts.Attributes, "_DTYPE", ...
                hdmf.zarr.Reference.DatasetDtype);
            refDataset = zarr.create(obj.store, numTargets, "string", Path=path, ...
                Codecs={zarr.codecs.ZlibCodec(3)}, Attributes=attributes);
            refDataset(:) = refs.encodeElement();
            obj.refresh();
        end

        function compoundDataset = writeCompound(obj, path, records, opts)
        %writeCompound - Create a compound dataset
        %   compoundDataset = writeCompound(obj, path, records) writes
        %   the struct array records as a compound dataset at path, one
        %   record per element. Field types are read off the data:
        %   numeric and logical fields keep their class, text becomes a
        %   string field, and fields of hdmf.zarr.Reference (or of
        %   paths or nodes, which are turned into references to this
        %   store) become reference fields. Text and reference fields
        %   are sized to the longest value they hold, with hdmf-zarr's
        %   minimum of 512 characters as a floor so that rows can be
        %   appended later.
        %
        %   writeCompound(obj, path, records, Dtype=dtype) instead
        %   takes the field layout from an hdmf.zarr.CompoundDtype. Use
        %   it when the data alone does not pin the types down -- to
        %   store MATLAB doubles as float32, say, or to declare a
        %   reference field whose rows are given as paths. The text
        %   capacities it declares are minimums: a field is widened
        %   when one of its values needs more room.
        %
        %   writeCompound(obj, path, records, Attributes=attrs) also
        %   sets additional attributes on the new dataset.

            arguments
                obj
                path (1,1) string
                records struct
                opts.Dtype hdmf.zarr.CompoundDtype {mustBeScalarOrEmpty} = ...
                    hdmf.zarr.CompoundDtype.empty
                opts.Attributes {mustBeA(opts.Attributes, ["struct", "dictionary"])} = struct()
            end
            if isempty(records)
                error("hdmf:InvalidCompoundData", ...
                    "Cannot write an empty compound dataset at '%s'.", path);
            end
            records = obj.resolveReferenceFields(reshape(records, [], 1));
            if isempty(opts.Dtype)
                dtype = hdmf.zarr.CompoundDtype.fromData(records);
            else
                dtype = opts.Dtype;
            end
            stored = obj.encodeCompoundRows(records, dtype);
            % Size from the encoded rows rather than from records: a
            % reference field given as relative paths or nodes occupies
            % the absolute paths they became.
            dtype = dtype.widenToFit(stored);

            attributes = opts.Attributes;
            if any(dtype.isReferenceField())
                % hdmf-zarr writes this attribute only for a compound that
                % has reference fields.
                attributes = withAttribute(attributes, "_REFERENCE_FIELDS", ...
                    dtype.encodeReferenceFields());
            end
            compoundDataset = zarr.create(obj.store, numel(stored), dtype.encodeDataType(), ...
                Path=path, Codecs={zarr.codecs.ZlibCodec(3)}, Attributes=attributes);
            compoundDataset.write(stored);
            obj.refresh();
        end

        function setRefAttr(obj, nodePath, attrName, target)
        %setRefAttr - Store an object reference in an attribute
        %   setRefAttr(obj, nodePath, attrName, target) sets the
        %   attribute attrName of the node at nodePath to a reference
        %   to target (a path or node), in the
        %   {"_REFERENCE": {source, path}} form.

            arguments
                obj
                nodePath (1,1) string
                attrName (1,1) string
                target
            end
            node = obj.resolve(nodePath);
            node.setAttr(attrName, obj.makeReference(target).encodeAttribute());
            obj.refresh();
        end

        function ref = makeReference(obj, target)
        %makeReference - Reference to a node of this store
        %   ref = makeReference(obj, target) builds an
        %   hdmf.zarr.Reference to target (a path or node). A path is
        %   resolved to its node first, which checks that it exists.

            node = obj.asNode(target);
            ref = hdmf.zarr.Reference(node.path);
        end

        function refresh(obj)
        %refresh - Re-read the root after mutations
        %   refresh(obj) re-opens the root group, refreshing
        %   consolidated metadata first if this store carries it. The
        %   write methods call this themselves.

            [bytes, found] = obj.store.get("zarr.json");
            if found
                txt = native2unicode(bytes, 'UTF-8');
                if contains(txt, '"consolidated_metadata"')
                    zarr.consolidate_metadata(obj.store);
                end
            end
            obj.root = zarr.open(obj.store);
        end

        function specPath = specLoc(obj)
        %specLoc - Path of the cached specifications group ("" if absent)
        %   specPath = specLoc(obj) returns the value of the root
        %   ".specloc" attribute, which names the group holding cached
        %   format specifications ("" when the store records none).

            [found, value] = hdmf.zarr.internal.recordField(obj.root.attrs, ".specloc");
            if found
                specPath = string(char(value));
            else
                specPath = "";
            end
        end
    end

    methods (Access = private)
        function records = resolveReferenceFields(obj, records)
        %resolveReferenceFields - Turn path/node reference fields into References
        %   Only fields already holding hdmf.zarr.Reference are left
        %   alone; a field of paths or nodes cannot be told apart from a
        %   field of text without a declared layout, so this is used only
        %   to infer one, never to reinterpret a declared "str_" field.

            for name = string(fieldnames(records))'
                if isa(records(1).(name), 'hdmf.zarr.Reference')
                    continue
                end
                if isa(records(1).(name), 'zarr.Group') || isa(records(1).(name), 'zarr.Array')
                    for i = 1:numel(records)
                        records(i).(name) = obj.makeReference(records(i).(name));
                    end
                end
            end
        end

        function stored = encodeCompoundRows(obj, records, dtype)
        %encodeCompoundRows - Rows in the form the Zarr record type takes
        %   Reference fields become their target paths and text fields
        %   string scalars, so that every field is a value the array's
        %   own data type can encode.

            missingFields = setdiff(dtype.Names, string(fieldnames(records))');
            if ~isempty(missingFields)
                error("hdmf:InvalidCompoundData", ...
                    "The data has no field '%s', which the compound dtype declares.", ...
                    missingFields(1));
            end
            isReference = dtype.isReferenceField();
            stored = struct();
            for k = 1:numel(dtype.Names)
                name = dtype.Names(k);
                for i = 1:numel(records)
                    value = records(i).(name);
                    if isReference(k)
                        if ~isa(value, 'hdmf.zarr.Reference')
                            value = obj.makeReference(value);
                        end
                        stored(i, 1).(name) = value.encodeElement();
                    elseif isstring(value) || ischar(value)
                        stored(i, 1).(name) = string(value);
                    else
                        stored(i, 1).(name) = value;
                    end
                end
            end
        end

        function node = asNode(obj, nodeOrPath)
        %asNode - A zarr node as given, or resolved from a path

            if isa(nodeOrPath, 'zarr.Group') || isa(nodeOrPath, 'zarr.Array')
                node = nodeOrPath;
            else
                node = obj.resolve(nodeOrPath);
            end
        end
    end
end

function dtype = compoundDtypeOf(node, records)
%compoundDtypeOf - Field layout of a compound dataset that has been read
%   The Zarr record type gives every field's type, but a reference field
%   is stored as text, so only an attribute can say which fields hold
%   references: _REFERENCE_FIELDS, or, in a store written by hdmf-zarr
%   before 0.14, the per-field types of zarr_dtype. A dataset with
%   neither is read as plain fields: nothing claims any of them is a
%   reference.

fieldNames = string(fieldnames(records))';
[found, referenceFields] = hdmf.zarr.internal.recordField(node.attrs, "_REFERENCE_FIELDS");
if found
    dtype = hdmf.zarr.CompoundDtype.fromData(records);
    referenceFields = reshape(string(referenceFields), 1, []);
    unknownFields = setdiff(referenceFields, fieldNames);
    if ~isempty(unknownFields)
        error("hdmf:InvalidCompoundDtype", ...
            "_REFERENCE_FIELDS of '%s' names field '%s', but the record type has %s.", ...
            node.path, unknownFields(1), strjoin(fieldNames, ", "));
    end
    dtype.Types(ismember(dtype.Names, referenceFields)) = "object";
    return
end
[found, fieldTypes] = hdmf.zarr.internal.recordField(node.attrs, 'zarr_dtype');
if found
    dtype = hdmf.zarr.CompoundDtype.decode(fieldTypes);
    if ~isequal(sort(dtype.Names), sort(fieldNames))
        error("hdmf:InvalidCompoundDtype", ...
            "zarr_dtype of '%s' names fields %s, but the record type has %s.", ...
            node.path, strjoin(dtype.Names, ", "), strjoin(fieldNames, ", "));
    end
    return
end
dtype = hdmf.zarr.CompoundDtype.fromData(records);
end

function attributes = withAttribute(attributes, name, value)
%withAttribute - Attributes with one entry added, as a dictionary
%   The reserved hdmf-zarr attribute names start with an underscore, which
%   a struct field cannot, so a struct of attributes is carried over into
%   a dictionary first.

if isstruct(attributes)
    names = string(fieldnames(attributes));
    contents = struct2cell(attributes);
    attributes = dictionary(string.empty, {});
    for i = 1:numel(names)
        attributes(names(i)) = contents(i);
    end
end
attributes(name) = {value};
end
