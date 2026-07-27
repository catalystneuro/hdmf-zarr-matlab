classdef File < handle
    %FILE An hdmf-zarr hierarchy: Zarr v3 plus link/reference conventions.
    %   Implements the storage conventions of
    %   https://hdmf-zarr.readthedocs.io/en/latest/storage.html :
    %     - zarr_link group attributes (soft + external links)
    %     - zarr_dtype:"object" references in datasets and attributes

    properties (SetAccess = private)
        store
        root      % zarr.Group
    end

    methods
        function obj = File(store)
            obj.store = store;
            obj.root = zarr.open(store);
            if ~isa(obj.root, 'zarr.Group')
                error("hdmf:InvalidFile", "Root node is not a group.");
            end
        end

        function node = resolve(obj, path)
            %RESOLVE Open the node at path, following zarr_link entries.
            %   Each path segment may be a real child or a link name; links
            %   restart resolution at their target (source "." = this store).
            parts = split(zarr.internal.normalize_path(path), "/");
            parts = parts(strlength(parts) > 0);
            node = obj.root;
            i = 1;
            while i <= numel(parts)
                seg = parts(i);
                if ~isa(node, 'zarr.Group')
                    error("hdmf:ResolveError", ...
                        "'%s' is not a group; cannot descend into '%s'.", node.path, seg);
                end
                if node.isKey(seg)
                    node = node.item(seg);
                else
                    link = obj.findLink(node, seg);
                    if isempty(link)
                        error("hdmf:ResolveError", ...
                            "No child or link named '%s' under '/%s'.", seg, node.path);
                    end
                    node = obj.followLink(link);
                end
                i = i + 1;
            end
        end

        function L = links(obj, groupOrPath)
            %LINKS zarr_link entries of a group, as a struct array
            %   (fields: name, source, path, and optionally object ids).
            g = obj.asNode(groupOrPath);
            a = g.attrs;
            if ~isfield(a, 'zarr_link')
                L = hdmf.zarr.decodeLinks([]);
                return
            end
            L = hdmf.zarr.decodeLinks(a.zarr_link);
        end

        function node = deref(obj, ref)
            %DEREF Resolve a reference (struct with source/path, a JSON
            %   string of one, or an attribute value of the
            %   {"zarr_dtype":"object","value":{...}} form) to its node.
            ref = hdmf.zarr.decodeReference(ref);
            src = ref.source;
            if src ~= "." && strlength(src) > 0
                error("hdmf:UnsupportedFeature", ...
                    "External reference sources are not supported yet ('%s').", src);
            end
            node = obj.resolve(ref.path);
        end

        function tf = isRefArray(~, node)
            %ISREFARRAY True if node is a zarr_dtype:"object" reference dataset.
            tf = isa(node, 'zarr.Array') && ...
                hdmf.zarr.isReferenceArray(node.dtype, node.attrs);
        end

        function nodes = derefAll(obj, refArrayOrNode)
            %DEREFALL Dereference every element of a reference dataset.
            %   Returns a cell array shaped like the dataset.
            if isa(refArrayOrNode, 'zarr.Array')
                refs = refArrayOrNode.read();
            else
                refs = refArrayOrNode;
            end
            nodes = cell(size(refs));
            for i = 1:numel(refs)
                nodes{i} = obj.deref(refs(i));
            end
        end

        % ------------------------------------------------------------------
        % Write side (M4): create links and references per the conventions.

        function addLink(obj, groupPath, name, target)
            %ADDLINK Add a soft link: group's zarr_link gains an entry.
            %   addLink(f, "analysis", "device", "general/devices/probe0")
            g = obj.resolve(groupPath);
            if ~isa(g, 'zarr.Group')
                error("hdmf:WriteError", "'%s' is not a group.", groupPath);
            end
            reference = hdmf.zarr.decodeReference(obj.makeRef(target));
            entry = struct( ...
                'name', string(name), ...
                'source', reference.source, ...
                'path', reference.path, ...
                'object_id', reference.object_id, ...
                'source_object_id', reference.source_object_id);
            a = g.attrs;
            if isfield(a, 'zarr_link')
                existing = hdmf.zarr.decodeLinks(a.zarr_link);
            else
                existing = hdmf.zarr.decodeLinks([]);
            end
            encodedLinks = hdmf.zarr.encodeLinks([existing, entry]);
            g.setAttr('zarr_link', encodedLinks);
            obj.refresh();
        end

        function z = writeRefs(obj, path, targets, opts)
            %WRITEREFS Create a reference dataset (zarr_dtype:"object").
            %   writeRefs(f, "table/col", ["a/b", "a/c"]) writes a string-dtype
            %   array of JSON references, one per target path (or node).
            arguments
                obj
                path (1,1) string
                targets
                opts.Attributes struct = struct()
                opts.ChunkShape (1,:) double = []
                opts.Codecs cell = {}
            end
            n = numel(targets);
            jsonRefs = strings(n, 1);
            for i = 1:n
                if iscell(targets)
                    t = targets{i};
                else
                    t = targets(i);
                end
                jsonRefs(i) = hdmf.zarr.encodeReference( ...
                    obj.makeRef(t), Format="json");
            end
            attrs = opts.Attributes;
            attrs.zarr_dtype = 'object';
            z = zarr.create(obj.store, n, "string", Path=path, ...
                ChunkShape=opts.ChunkShape, Codecs=opts.Codecs, Attributes=attrs);
            z(:) = jsonRefs;
            obj.refresh();
        end

        function setRefAttr(obj, nodePath, attrName, target)
            %SETREFATTR Store an object reference in an attribute
            %   ({"zarr_dtype":"object","value":{...}} form).
            node = obj.resolve(nodePath);
            encodedReference = hdmf.zarr.encodeReference( ...
                obj.makeRef(target), Format="attribute");
            node.setAttr(attrName, encodedReference);
            obj.refresh();
        end

        function ref = makeRef(obj, target)
            %MAKEREF Build a {source, path, object ids} reference struct.
            if isa(target, 'zarr.Group') || isa(target, 'zarr.Array')
                node = target;
            else
                node = obj.resolve(target);
            end
            ref = struct('source', '.', 'path', char("/" + node.path));
            a = node.attrs;
            if isfield(a, 'object_id')
                ref.object_id = char(a.object_id);
            end
            ra = obj.root.attrs;
            if isfield(ra, 'object_id')
                ref.source_object_id = char(ra.object_id);
            end
            ref = hdmf.zarr.encodeReference(ref);
        end

        function refresh(obj)
            %REFRESH Re-read the root (and refresh consolidated metadata if
            %   this store carries it) after mutations.
            hdmf.zarr.refreshConsolidatedMetadata(obj.store);
            obj.root = zarr.open(obj.store);
        end

        function p = specLoc(obj)
            %SPECLOC Path of the cached specifications group ("" if absent).
            p = hdmf.zarr.readSpecLocation(obj.store);
        end

        function setSpecLoc(obj, location)
            %SETSPECLOC Set the path of the cached specifications group.
            arguments
                obj
                location (1,1) string
            end
            hdmf.zarr.writeSpecLocation(obj.store, location);
            obj.root = zarr.open(obj.store);
        end
    end

    methods (Access = private)
        function g = asNode(obj, groupOrPath)
            if isa(groupOrPath, 'zarr.Group') || isa(groupOrPath, 'zarr.Array')
                g = groupOrPath;
            else
                g = obj.resolve(groupOrPath);
            end
        end

        function link = findLink(obj, group, name)
            link = [];
            L = obj.links(group);
            for i = 1:numel(L)
                if L(i).name == name
                    link = L(i);
                    return
                end
            end
        end

        function node = followLink(obj, link)
            if link.source ~= "." && strlength(link.source) > 0
                error("hdmf:UnsupportedFeature", ...
                    "External links are not supported yet (source '%s').", link.source);
            end
            node = obj.resolve(link.path);
        end
    end
end
