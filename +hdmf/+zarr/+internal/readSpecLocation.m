function location = readSpecLocation(store)
%READSPECLOCATION Read the root .specloc attribute from a Zarr store.
%   Internal helper for hdmf.zarr.File. Returns an
%   empty string when the attribute is absent. The metadata is read as raw
%   JSON so the leading dot in the storage key is preserved.

    arguments
        store (1,1) zarr.stores.Store
    end

    rootText = readRootMetadata(store);
    [rootKeys, rootValues] = zarr.internal.json_object_entries(rootText);
    attributesIndex = find(rootKeys == "attributes", 1);
    if isempty(attributesIndex)
        location = "";
        return
    end

    [attributeKeys, attributeValues] = ...
        zarr.internal.json_object_entries(rootValues(attributesIndex));
    locationIndex = find(attributeKeys == ".specloc", 1);
    if isempty(locationIndex)
        % Existing MATLAB readers normalize invalid JSON field names this
        % way. Reading it preserves compatibility while all new writes use
        % the exact HDMF storage key above.
        locationIndex = find(attributeKeys == "x_specloc", 1);
    end
    if isempty(locationIndex)
        location = "";
        return
    end

    decodedLocation = jsondecode(char(attributeValues(locationIndex)));
    if ~(ischar(decodedLocation) || (isstring(decodedLocation) && isscalar(decodedLocation)))
        error("hdmf:conventions:InvalidSpecLocation", ...
            "The root .specloc attribute must contain scalar text.")
    end
    location = string(decodedLocation);
end

function rootText = readRootMetadata(store)
    [rootBytes, found] = store.get("zarr.json");
    if ~found
        error("hdmf:conventions:MissingRootMetadata", ...
            "The Zarr store does not contain root zarr.json metadata.")
    end
    rootText = string(native2unicode(rootBytes, "UTF-8"));
end
