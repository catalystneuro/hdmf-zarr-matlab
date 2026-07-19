function reference = decodeReference(encodedReference)
%DECODEREFERENCE Decode an HDMF object-reference record.
%   reference = hdmf.zarr.conventions.decodeReference(value) accepts a raw
%   reference struct, a JSON-encoded reference, or the attribute form
%   struct("zarr_dtype", "object", "value", reference). The returned
%   neutral struct has string fields source, path, object_id, and
%   source_object_id. Optional object-id fields are empty strings when they
%   are absent from storage.

    arguments
        encodedReference
    end

    rawReference = decodeJsonIfNeeded(encodedReference);
    if ~isstruct(rawReference) || ~isscalar(rawReference)
        invalidReference("A reference must be a scalar struct or JSON object.")
    end

    if isfield(rawReference, "zarr_dtype")
        referenceType = requireText(rawReference.zarr_dtype, "zarr_dtype");
        if referenceType == "region"
            error("hdmf:conventions:UnsupportedRegionReference", ...
                "HDMF-Zarr region references do not have a complete interoperable storage contract.")
        elseif referenceType ~= "object"
            invalidReference("Reference attribute zarr_dtype must be `object`.")
        elseif ~isfield(rawReference, "value")
            invalidReference("Reference attribute is missing its value field.")
        end
        rawReference = rawReference.value;
    end

    if ~isstruct(rawReference) || ~isscalar(rawReference)
        invalidReference("The decoded reference value must be a scalar struct.")
    end
    if isfield(rawReference, "region")
        error("hdmf:conventions:UnsupportedRegionReference", ...
            "HDMF-Zarr region references do not have a complete interoperable storage contract.")
    end
    if ~isfield(rawReference, "source") || ~isfield(rawReference, "path")
        invalidReference("Reference records require source and path fields.")
    end

    source = requireText(rawReference.source, "source");
    path = requireText(rawReference.path, "path");
    if ~startsWith(path, "/")
        invalidReference("Reference path must be absolute and start with `/`.")
    end

    reference = struct( ...
        "source", source, ...
        "path", path, ...
        "object_id", optionalText(rawReference, "object_id"), ...
        "source_object_id", optionalText(rawReference, "source_object_id"));
end

function value = decodeJsonIfNeeded(value)
    if ischar(value) || isstring(value)
        if isstring(value) && ~isscalar(value)
            invalidReference("A JSON-encoded reference must be scalar text.")
        end
        try
            value = jsondecode(char(value));
        catch exception
            error("hdmf:conventions:InvalidReference", ...
                "Reference JSON could not be decoded: %s", exception.message)
        end
    end
end

function value = requireText(rawValue, fieldName)
    if ~(ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue)))
        invalidReference("Reference field `%s` must be scalar text.", fieldName)
    end
    value = string(rawValue);
    if ismissing(value) || strlength(value) == 0
        invalidReference("Reference field `%s` must not be empty.", fieldName)
    end
end

function value = optionalText(reference, fieldName)
    if ~isfield(reference, fieldName) || isempty(reference.(fieldName))
        value = "";
        return
    end
    rawValue = reference.(fieldName);
    if (ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue))) ...
            && strlength(string(rawValue)) == 0
        value = "";
        return
    end
    value = requireText(rawValue, fieldName);
end

function invalidReference(message, varargin)
    error("hdmf:conventions:InvalidReference", message, varargin{:})
end
