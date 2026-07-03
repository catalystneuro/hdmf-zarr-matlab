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
            L = struct('name', {}, 'source', {}, 'path', {});
            a = g.attrs;
            if ~isfield(a, 'zarr_link')
                return
            end
            raw = a.zarr_link;
            if isstruct(raw)
                entries = num2cell(raw);
            else
                entries = raw;
            end
            for i = 1:numel(entries)
                e = entries{i};
                L(i).name = string(char(e.name));
                L(i).source = string(char(e.source));
                L(i).path = string(char(e.path));
            end
        end

        function node = deref(obj, ref)
            %DEREF Resolve a reference (struct with source/path, a JSON
            %   string of one, or an attribute value of the
            %   {"zarr_dtype":"object","value":{...}} form) to its node.
            if isstring(ref) || ischar(ref)
                ref = jsondecode(char(ref));
            end
            if isfield(ref, 'zarr_dtype') && isfield(ref, 'value')
                ref = ref.value;   % attribute form
            end
            src = string(char(ref.source));
            if src ~= "." && strlength(src) > 0
                error("hdmf:UnsupportedFeature", ...
                    "External reference sources are not supported yet ('%s').", src);
            end
            node = obj.resolve(string(char(ref.path)));
        end

        function tf = isRefArray(~, node)
            %ISREFARRAY True if node is a zarr_dtype:"object" reference dataset.
            tf = isa(node, 'zarr.Array') && isfield(node.attrs, 'zarr_dtype') && ...
                string(char(node.attrs.zarr_dtype)) == "object" && ...
                node.dtype == "string";
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

function f = x_specloc_field()
% '.specloc' is not a valid struct field; jsondecode normalizes it.
f = matlab.lang.makeValidName('.specloc');
end
