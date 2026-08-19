classdef File < handle
    %FILE - An hdmf-zarr hierarchy: Zarr v3 plus link/reference conventions.
    %   Convenience wrapper that binds a store to the store-independent
    %   conventions layer:
    %     - hdmf.zarr.Reference / hdmf.zarr.Link  encode and decode the
    %       zarr_dtype:"object" and zarr_link records
    %     - hdmf.zarr.resolve                      follows links through paths
    %   File adds what needs the store: opening the root, looking up
    %   object ids when building references, writing attributes and
    %   datasets, and refreshing consolidated metadata after mutations.
    %   Consumers with their own file model (e.g. MatNWB) can use the
    %   conventions layer directly and skip File.

    properties (SetAccess = private)
        store
        root      % zarr.Group
    end

    methods
        function obj = File(store)
            %FILE - Open the hierarchy rooted at store.
            obj.store = store;
            obj.root = zarr.open(store);
            if ~isa(obj.root, 'zarr.Group')
                error("hdmf:InvalidFile", "Root node is not a group.");
            end
        end

        function node = resolve(obj, target)
            %RESOLVE - Open the node at a path or Reference, following links.
            %   See hdmf.zarr.resolve.
            node = hdmf.zarr.resolve(obj.root, target);
        end

        function linkList = links(obj, groupOrPath)
            %LINKS - zarr_link entries of a group, as an hdmf.zarr.Link array.
            group = obj.asNode(groupOrPath);
            linkList = hdmf.zarr.Link.fromAttributes(group.attrs);
        end

        function node = deref(obj, ref)
            %DEREF - Resolve a reference to its node.
            %   ref may be a Reference or any on-disk form accepted by
            %   hdmf.zarr.Reference.decode (JSON string, attribute-form
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
            %DEREFALL - Dereference every element of a reference dataset.
            %   Accepts the zarr.Array itself, its read() values, or a
            %   Reference array. Returns a cell array shaped like the input.
            %   Each distinct path is resolved once: reference columns
            %   typically repeat a few targets many times.
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
            %ADDLINK - Add a soft link: group's zarr_link gains an entry.
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
            %WRITEREFS - Create a reference dataset (zarr_dtype:"object").
            %   writeRefs(f, "table/col", ["a/b", "a/c"]) writes a string-dtype
            %   array of JSON references, one per target path (or node).
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
            %SETREFATTR - Store an object reference in an attribute
            %   ({"zarr_dtype":"object","value":{...}} form).
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
            %MAKEREFERENCE - Reference to a node (or path) with object ids.
            %   The object_id of the target and of this store's root are
            %   filled in when those nodes record one.
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
            %REFRESH - Re-read the root after mutations.
            %   Also refreshes consolidated metadata if this store carries it.
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
            %SPECLOC - Path of the cached specifications group ("" if absent).
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
            %ASNODE - A zarr node as given, or resolved from a path.
            if isa(nodeOrPath, 'zarr.Group') || isa(nodeOrPath, 'zarr.Array')
                node = nodeOrPath;
            else
                node = obj.resolve(nodeOrPath);
            end
        end
    end
end

function fieldName = specLocField()
%SPECLOCFIELD - Struct field under which jsondecode stores ".specloc".
%   '.specloc' is not a valid struct field name; jsondecode normalizes it.
fieldName = matlab.lang.makeValidName('.specloc');
end
