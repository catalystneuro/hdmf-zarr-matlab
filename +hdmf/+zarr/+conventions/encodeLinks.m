function encodedLinks = encodeLinks(links, options)
%ENCODELINKS Encode HDMF link records for the zarr_link attribute.
%   encoded = hdmf.zarr.conventions.encodeLinks(links) returns a cell array
%   so jsonencode emits a JSON list even when links contains one record.
%
%   encoded = encodeLinks(links, Format="json") returns that JSON list as
%   text.

    arguments
        links
        options.Format (1,1) string {mustBeMember(options.Format, ...
            ["attribute", "json"])} = "attribute"
    end

    links = hdmf.zarr.conventions.decodeLinks(links);
    storageLinks = cell(1, numel(links));
    for iLink = 1:numel(links)
        reference = hdmf.zarr.conventions.encodeReference(links(iLink));
        storageLink = struct( ...
            "name", char(links(iLink).name), ...
            "source", reference.source, ...
            "path", reference.path);
        if isfield(reference, "object_id")
            storageLink.object_id = reference.object_id;
        end
        if isfield(reference, "source_object_id")
            storageLink.source_object_id = reference.source_object_id;
        end
        storageLinks{iLink} = storageLink;
    end

    switch options.Format
        case "attribute"
            encodedLinks = storageLinks;
        case "json"
            encodedLinks = string(jsonencode(storageLinks));
        otherwise
            error("hdmf:conventions:InvalidLinkFormat", ...
                "Unsupported link encoding format `%s`.", options.Format)
    end
end
