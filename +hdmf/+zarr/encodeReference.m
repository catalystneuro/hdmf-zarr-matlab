function encodedReference = encodeReference(reference, options)
%ENCODEREFERENCE Encode an HDMF object-reference record.
%   encoded = hdmf.zarr.encodeReference(reference) returns a
%   storage-shaped struct with source and path fields and optional object-id
%   fields.
%
%   encoded = encodeReference(reference, Format="json") returns the JSON
%   string representation used for reference-array elements.
%
%   encoded = encodeReference(reference, Format="attribute") returns the
%   {"zarr_dtype":"object","value":reference} attribute representation.

    arguments
        reference
        options.Format (1,1) string {mustBeMember(options.Format, ...
            ["record", "json", "attribute"])} = "record"
    end

    reference = hdmf.zarr.decodeReference(reference);
    storageRecord = struct( ...
        "source", char(reference.source), ...
        "path", char(reference.path));
    if strlength(reference.object_id) > 0
        storageRecord.object_id = char(reference.object_id);
    end
    if strlength(reference.source_object_id) > 0
        storageRecord.source_object_id = char(reference.source_object_id);
    end

    switch options.Format
        case "record"
            encodedReference = storageRecord;
        case "json"
            encodedReference = string(jsonencode(storageRecord));
        case "attribute"
            encodedReference = struct("zarr_dtype", "object", "value", storageRecord);
        otherwise
            error("hdmf:conventions:InvalidReferenceFormat", ...
                "Unsupported reference encoding format `%s`.", options.Format)
    end
end
