classdef File < handle
    %FILE An hdmf-zarr hierarchy: Zarr v3 plus link/reference conventions.
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
            obj.store = store;
            obj.root = zarr.open(store);
            if ~isa(obj.root, 'zarr.Group')
                error("hdmf:InvalidFile", "Root node is not a group.");
            end
        end

        function node = resolve(obj, target)
            %RESOLVE Open the node at a path or Reference, following links.
            %   See hdmf.zarr.resolve.
            node = hdmf.zarr.resolve(obj.root, target);
        end

        function L = links(obj, groupOrPath)
            %LINKS zarr_link entries of a group, as an hdmf.zarr.Link array.
            g = obj.asNode(groupOrPath);
            L = hdmf.zarr.Link.fromAttributes(g.attrs);
        end

        function node = deref(obj, ref)
            %DEREF Resolve a reference to its node. ref may be a Reference
            %   or any on-disk form accepted by hdmf.zarr.Reference.decode
            %   (JSON string, attribute-form struct, bare record).
            if ~isa(ref, 'hdmf.zarr.Reference')
                ref = hdmf.zarr.Reference.decode(ref);
            end
            node = obj.resolve(ref);
        end

        function nodes = derefAll(obj, refArrayOrValues)
            %DEREFALL Dereference every element of a reference dataset (or of
            %   an already-read array of references). Returns a cell array
            %   shaped like the dataset.
            refs = refArrayOrValues;
            if isa(refs, 'zarr.Array')
                refs = refs.read();
            end
            if ~isa(refs, 'hdmf.zarr.Reference')
                refs = hdmf.zarr.Reference.decode(refs);
            end
            nodes = cell(size(refs));
            for i = 1:numel(refs)
                nodes{i} = obj.resolve(refs(i));
            end
        end

        % ------------------------------------------------------------------
        % Write side: create links and references per the conventions.

        function addLink(obj, groupPath, name, target)
            %ADDLINK Add a soft link: group's zarr_link gains an entry.
            %   addLink(f, "analysis", "device", "general/devices/probe0")
            g = obj.resolve(groupPath);
            if ~isa(g, 'zarr.Group')
                error("hdmf:WriteError", "'%s' is not a group.", groupPath);
            end
            newLink = hdmf.zarr.Link(name, obj.makeReference(target));
            links = [hdmf.zarr.Link.fromAttributes(g.attrs), newLink];
            g.setAttr('zarr_link', links.encode());
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
            end
            n = numel(targets);
            refs = repmat(hdmf.zarr.Reference(), n, 1);
            for i = 1:n
                if iscell(targets)
                    refs(i) = obj.makeReference(targets{i});
                else
                    refs(i) = obj.makeReference(targets(i));
                end
            end
            attrs = opts.Attributes;
            attrs.zarr_dtype = 'object';
            z = zarr.create(obj.store, n, "string", Path=path, ...
                Codecs={zarr.codecs.ZlibCodec(3)}, Attributes=attrs);
            z(:) = refs.encodeJson();
            obj.refresh();
        end

        function setRefAttr(obj, nodePath, attrName, target)
            %SETREFATTR Store an object reference in an attribute
            %   ({"zarr_dtype":"object","value":{...}} form).
            node = obj.resolve(nodePath);
            node.setAttr(attrName, obj.makeReference(target).encodeAttribute());
            obj.refresh();
        end

        function ref = makeReference(obj, target)
            %MAKEREFERENCE Reference to a node (or path), with the object ids
            %   of the target and of this store's root filled in when present.
            node = obj.asNode(target);
            ref = hdmf.zarr.Reference(node.path);
            a = node.attrs;
            if isfield(a, 'object_id')
                ref.ObjectId = string(char(a.object_id));
            end
            ra = obj.root.attrs;
            if isfield(ra, 'object_id')
                ref.SourceObjectId = string(char(ra.object_id));
            end
        end

        function refresh(obj)
            %REFRESH Re-read the root (and refresh consolidated metadata if
            %   this store carries it) after mutations.
            [bytes, found] = obj.store.get("zarr.json");
            if found
                txt = native2unicode(bytes, 'UTF-8');
                if contains(txt, '"consolidated_metadata"')
                    zarr.consolidate_metadata(obj.store);
                end
            end
            obj.root = zarr.open(obj.store);
        end

        function p = specLoc(obj)
            %SPECLOC Path of the cached specifications group ("" if absent).
            a = obj.root.attrs;
            if isfield(a, x_specloc_field())
                p = string(char(a.(x_specloc_field())));
            else
                p = "";
            end
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
    end
end

function f = x_specloc_field()
% '.specloc' is not a valid struct field; jsondecode normalizes it.
f = matlab.lang.makeValidName('.specloc');
end
