function wasRefreshed = refreshConsolidatedMetadata(store)
%REFRESHCONSOLIDATEDMETADATA Refresh existing consolidated Zarr metadata.
%   wasRefreshed = refreshConsolidatedMetadata(store) refreshes inline
%   consolidated metadata only when the root already contains it. The
%   function preserves the exact HDMF .specloc storage key.

    arguments
        store (1,1) zarr.stores.Store
    end

    [rootBytes, found] = store.get("zarr.json");
    if ~found
        error("hdmf:conventions:MissingRootMetadata", ...
            "The Zarr store does not contain root zarr.json metadata.")
    end
    rootText = string(native2unicode(rootBytes, "UTF-8"));
    [rootKeys, rootValues] = zarr.internal.json_object_entries(rootText);
    consolidatedIndex = find(rootKeys == "consolidated_metadata", 1);
    wasRefreshed = ~isempty(consolidatedIndex) ...
        && strtrim(rootValues(consolidatedIndex)) ~= "null";
    if ~wasRefreshed
        return
    end

    specLocation = hdmf.zarr.readSpecLocation(store);
    zarr.consolidate_metadata(store);
    if strlength(specLocation) > 0
        hdmf.zarr.writeSpecLocation(store, specLocation);
    end
end
