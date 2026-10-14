function specPath = specLoc(rootGroup)
%specLoc - Path of the cached specifications group ("" if absent)
%   specPath = specLoc(rootGroup) returns, as a string, the value of the
%   ".specloc" attribute of rootGroup, the zarr.Group at the top of an
%   hdmf-zarr hierarchy. It names the group holding the cached format
%   specifications; a store that records none gives "".
%
%   See also hdmf.zarr.File.specLoc

[found, value] = hdmf.zarr.internal.recordField(rootGroup.attrs, ".specloc");
if found
    specPath = string(char(value));
else
    specPath = "";
end
end
