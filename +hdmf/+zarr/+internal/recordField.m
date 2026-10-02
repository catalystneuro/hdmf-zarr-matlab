function [found, value] = recordField(record, name)
%recordField - One field of an on-disk record, whichever form it is in
%   A record read from a node's attributes is a dictionary: zarr-matlab
%   exposes attributes that way so that a JSON key survives exactly, and
%   an object nested inside an attribute value decodes the same way. A
%   record built in MATLAB -- by Reference.encode, or by a test fixture
%   written as a literal -- is a scalar struct. Both reach the decoders
%   here, so both are read through this function and no caller has to
%   know which one it holds.
%
%   [found, value] = recordField(record, name) returns whether the
%   record carries the field, and its value when it does ([] otherwise).
%   Anything that is not a record at all reports found = false rather
%   than raising, so a caller can give its own error naming the record.
%
%   Dictionaries here always come from zarr-matlab, whose attributes are
%   cell-valued, so the value is read with braces.
%
%   Example: Same call for either form
%       hdmf.zarr.internal.recordField(struct('path', '/a'), 'path')
%       d = dictionary(string.empty, {}); d("path") = {"/a"};
%       hdmf.zarr.internal.recordField(d, 'path')
%
%   See also hdmf.zarr.Reference, hdmf.zarr.Link

value = [];
if isa(record, 'dictionary')
    found = isKey(record, string(name));
    if found
        value = record{string(name)};
    end
elseif isstruct(record) && isscalar(record)
    found = isfield(record, char(name));
    if found
        value = record.(char(name));
    end
else
    found = false;
end
end
