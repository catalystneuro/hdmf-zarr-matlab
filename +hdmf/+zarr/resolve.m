function node = resolve(root, target)
%resolve - Open the node a path or reference points to, following links
%   node = resolve(root, target) walks target from root (the
%   zarr.Group at the top of the store) and returns the node it ends
%   at. target is a path ("general/devices/probe0") or a scalar
%   hdmf.zarr.Reference.
%
%   Each path segment may be a real child of the current group or the
%   name of one of that group's links (see hdmf.zarr.Link) -- links are
%   followed transparently, so a linked node can be addressed as if it
%   were an ordinary child. A link restarts resolution at its target
%   path from root. Only in-store targets are supported: external
%   links and references raise hdmf:UnsupportedFeature.
%
%   This is the store-bound counterpart of hdmf.zarr.Reference and
%   hdmf.zarr.Link; hdmf.zarr.File.resolve is a thin wrapper around
%   it, and hdmf.zarr.File.derefAll handles Reference arrays.
%
%   See also hdmf.zarr.File, hdmf.zarr.Reference, hdmf.zarr.Link

arguments
    root (1,1) zarr.Group
    target {mustBeResolveTarget}
end

if isa(target, 'hdmf.zarr.Reference')
    if target.isExternal()
        error("hdmf:UnsupportedFeature", ...
            "External reference sources are not supported yet ('%s').", target.Source);
    end
    path = target.Path;
else
    path = string(target);
end

segments = split(zarr.internal.normalize_path(path), "/");
segments = segments(strlength(segments) > 0);
node = root;
for i = 1:numel(segments)
    name = segments(i);
    if ~isa(node, 'zarr.Group')
        error("hdmf:ResolveError", ...
            "'%s' is not a group; cannot descend into '%s'.", node.path, name);
    end
    if node.isKey(name)
        node = node.item(name);
    else
        node = followLink(root, node, name);
    end
end
end

function node = followLink(root, group, name)
%followLink - Resolve the link called name in group, from root

links = hdmf.zarr.Link.fromAttributes(group.attrs);
link = hdmf.zarr.Link.empty(1, 0);
for i = 1:numel(links)
    if links(i).Name == name
        link = links(i);
        break
    end
end
if isempty(link)
    error("hdmf:ResolveError", ...
        "No child or link named '%s' under '/%s'.", name, group.path);
end
if link.Target.isExternal()
    error("hdmf:UnsupportedFeature", ...
        "External links are not supported yet (source '%s').", link.Target.Source);
end
node = hdmf.zarr.resolve(root, link.Target);
end

function mustBeResolveTarget(target)
%mustBeResolveTarget - One path (text scalar) or one Reference
%   A Reference array is rejected rather than silently resolving its
%   first element; use hdmf.zarr.File.derefAll for arrays.

if isa(target, 'hdmf.zarr.Reference')
    if ~isscalar(target)
        error("hdmf:ResolveError", ...
            "resolve takes one Reference; got %d. Use derefAll for arrays.", numel(target));
    end
else
    mustBeTextScalar(target);
end
end
