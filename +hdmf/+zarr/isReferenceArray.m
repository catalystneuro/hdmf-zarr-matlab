function tf = isReferenceArray(dataType, attributes)
%ISREFERENCEARRAY Identify an HDMF object-reference array.
%   tf = hdmf.zarr.isReferenceArray(dataType, attributes) is
%   true when the physical Zarr type is string and the reserved zarr_dtype
%   attribute is "object".

    arguments
        dataType {mustBeTextScalar}
        attributes (1,1) struct
    end

    tf = false;
    if string(dataType) ~= "string" || ~isfield(attributes, "zarr_dtype")
        return
    end

    referenceType = attributes.zarr_dtype;
    if ischar(referenceType) || (isstring(referenceType) && isscalar(referenceType))
        tf = string(referenceType) == "object";
    end
end
