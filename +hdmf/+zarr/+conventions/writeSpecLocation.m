function writeSpecLocation(store, location)
%WRITESPECLOCATION Write the root .specloc attribute to a Zarr store.
%   hdmf.zarr.conventions.writeSpecLocation(store, location) updates root
%   zarr.json directly so the HDMF key remains exactly ".specloc" rather
%   than MATLAB's normalized struct field name.

    arguments
        store (1,1) zarr.stores.Store
        location (1,1) string
    end

    if strlength(location) == 0 || ~startsWith(location, "/")
        error("hdmf:conventions:InvalidSpecLocation", ...
            "Specification location must be a nonempty absolute path.")
    end

    [rootBytes, found] = store.get("zarr.json");
    if ~found
        error("hdmf:conventions:MissingRootMetadata", ...
            "The Zarr store does not contain root zarr.json metadata.")
    end
    rootText = string(native2unicode(rootBytes, "UTF-8"));
    [rootKeys, rootValues] = zarr.internal.json_object_entries(rootText);
    attributesIndex = find(rootKeys == "attributes", 1);
    if isempty(attributesIndex)
        attributesText = "{}";
    else
        attributesText = rootValues(attributesIndex);
    end

    attributesText = removeJsonEntry(attributesText, "x_specloc");
    attributesText = setJsonEntry(attributesText, ".specloc", ...
        string(jsonencode(char(location))));
    rootText = setJsonEntry(rootText, "attributes", attributesText);
    store.set("zarr.json", unicode2native(char(rootText), "UTF-8"));
end

function objectText = setJsonEntry(objectText, key, valueText)
    [keys, values] = zarr.internal.json_object_entries(objectText);
    index = find(keys == key, 1);
    if isempty(index)
        keys = [keys; key];
        values = [values; valueText];
    else
        values(index) = valueText;
    end
    objectText = buildJsonObject(keys, values);
end

function objectText = removeJsonEntry(objectText, key)
    [keys, values] = zarr.internal.json_object_entries(objectText);
    keep = keys ~= key;
    objectText = buildJsonObject(keys(keep), values(keep));
end

function objectText = buildJsonObject(keys, values)
    entries = strings(numel(keys), 1);
    for iEntry = 1:numel(keys)
        entries(iEntry) = string(jsonencode(char(keys(iEntry)))) + ":" + values(iEntry);
    end
    objectText = "{" + strjoin(entries, ",") + "}";
end
