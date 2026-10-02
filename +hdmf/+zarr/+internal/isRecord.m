function tf = isRecord(value)
%isRecord - True for a single on-disk record in either of its forms
%   A record is one JSON object: a dictionary when it was read from a
%   store, a scalar struct when it was built in MATLAB. Both are 1x1, so
%   a caller can iterate a list of records the same way for either.
%
%   See also hdmf.zarr.internal.recordField

tf = isa(value, 'dictionary') || (isstruct(value) && isscalar(value));
end
