function node = resolve(root, target)
%RESOLVE Open the node a path or reference points to, following zarr_link entries.
%   node = hdmf.zarr.resolve(root, "general/devices/probe0")
%   node = hdmf.zarr.resolve(root, hdmf.zarr.Reference(...))
%
%   root is the zarr.Group at the top of the store. Each path segment may
%   be a real child of the current group or the name of one of its links;
%   a link restarts resolution at its target path from root. Only
%   in-store targets are supported: external links and references
%   (Source ~= ".") raise hdmf:UnsupportedFeature.
%
%   This is the store-dependent counterpart of hdmf.zarr.Reference /
%   hdmf.zarr.Link; hdmf.zarr.File.resolve is a thin wrapper around it.

arguments
    root (1,1) zarr.Group
    target
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
% Find the link called name in group and resolve its target from root.
links = hdmf.zarr.Link.fromAttributes(group.attrs);
index = find([links.Name] == name, 1);
if isempty(index)
    error("hdmf:ResolveError", ...
        "No child or link named '%s' under '/%s'.", name, group.path);
end
link = links(index);
if link.Target.isExternal()
    error("hdmf:UnsupportedFeature", ...
        "External links are not supported yet (source '%s').", link.Target.Source);
end
node = hdmf.zarr.resolve(root, link.Target);
end
