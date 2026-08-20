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
%       links         - zarr_link entries of a group, as a Link array
%       addLink       - Add a soft link to a group
%       writeRefs     - Create a reference dataset
%       setRefAttr    - Store an object reference in an attribute
%       makeReference - Reference to a node, with object ids filled in
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
        %links - zarr_link entries of a group, as a Link array
        %   linkList = links(obj, groupOrPath) returns the links
        %   declared by a group (a zarr.Group or a path to one) as an
        %   hdmf.zarr.Link array; 1x0 if the group declares none.

            group = obj.asNode(groupOrPath);
            linkList = hdmf.zarr.Link.fromAttributes(group.attrs);
        end

        function node = deref(obj, ref)
        %deref - Resolve a reference to its node
        %   node = deref(obj, ref) opens the node ref points to. ref
        %   may be an hdmf.zarr.Reference or any on-disk form accepted
        %   by hdmf.zarr.Reference.decode (JSON string, attribute-form
        %   struct, bare record).

            arguments
                obj
                ref {mustBeA(ref, ["hdmf.zarr.Reference", "string", "char", "struct"])}
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
                    ["zarr.Array", "hdmf.zarr.Reference", "string", "char", "struct", "cell"])}
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

        % ------------------------------------------------------------------
        % Write side: create links and references per the conventions.

        function addLink(obj, groupPath, name, target)
        %addLink - Add a soft link: group's zarr_link gains an entry
        %   addLink(obj, groupPath, name, target) makes target (a path
        %   or node in this store) appear as the child name of the
        %   group at groupPath, e.g.
        %   addLink(f, "analysis", "device", "general/devices/probe0")

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
            attributes = group.attrs;
            existing = {};
            if isfield(attributes, 'zarr_link') && ~isempty(attributes.zarr_link)
                existing = attributes.zarr_link;
                if isstruct(existing)
                    existing = num2cell(existing);
                end
                existing = reshape(existing, 1, []);
            end
            newLink = hdmf.zarr.Link(name, obj.makeReference(target));
            group.setAttr('zarr_link', [existing, newLink.encode()]);
            obj.refresh();
        end

        function refDataset = writeRefs(obj, path, targets, opts)
        %writeRefs - Create a reference dataset (zarr_dtype:"object")
        %   refDataset = writeRefs(obj, path, targets) writes a
        %   string-dtype array at path with one JSON reference record
        %   per element of targets (paths or nodes), e.g.
        %   writeRefs(f, "table/col", ["a/b", "a/c"])
        %
        %   refDataset = writeRefs(obj, path, targets, Attributes=attrs)
        %   also sets additional attributes on the new dataset.

            arguments
                obj
                path (1,1) string
                targets
                opts.Attributes struct = struct()
            end
            if ~iscell(targets)
                targets = num2cell(targets);
            end
            numTargets = numel(targets);
            refs = repmat(hdmf.zarr.Reference(), numTargets, 1);
            for i = 1:numTargets
                refs(i) = obj.makeReference(targets{i});
            end
            attributes = opts.Attributes;
            attributes.zarr_dtype = 'object';
            refDataset = zarr.create(obj.store, numTargets, "string", Path=path, ...
                Codecs={zarr.codecs.ZlibCodec(3)}, Attributes=attributes);
            refDataset(:) = refs.encodeJson();
            obj.refresh();
        end

        function setRefAttr(obj, nodePath, attrName, target)
        %setRefAttr - Store an object reference in an attribute
        %   setRefAttr(obj, nodePath, attrName, target) sets the
        %   attribute attrName of the node at nodePath to a reference
        %   to target (a path or node), in the
        %   {"zarr_dtype":"object","value":<record>} form.

            arguments
                obj
                nodePath (1,1) string
                attrName (1,1) string
                target
            end
            node = obj.resolve(nodePath);
            node.setAttr(char(attrName), obj.makeReference(target).encodeAttribute());
            obj.refresh();
        end

        function ref = makeReference(obj, target)
        %makeReference - Reference to a node, with object ids filled in
        %   ref = makeReference(obj, target) builds an
        %   hdmf.zarr.Reference to target (a path or node); the object
        %   ids of the target and of this store's root are filled in
        %   when those nodes record one.

            node = obj.asNode(target);
            ref = hdmf.zarr.Reference(node.path);
            attributes = node.attrs;
            if isfield(attributes, 'object_id')
                ref.ObjectId = string(char(attributes.object_id));
            end
            rootAttributes = obj.root.attrs;
            if isfield(rootAttributes, 'object_id')
                ref.SourceObjectId = string(char(rootAttributes.object_id));
            end
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

            attributes = obj.root.attrs;
            if isfield(attributes, specLocField())
                specPath = string(char(attributes.(specLocField())));
            else
                specPath = "";
            end
        end
    end

    methods (Access = private)
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

function fieldName = specLocField()
%specLocField - Struct field under which jsondecode stores ".specloc"
%   '.specloc' is not a valid struct field name; jsondecode normalizes it.

fieldName = matlab.lang.makeValidName('.specloc');
end
