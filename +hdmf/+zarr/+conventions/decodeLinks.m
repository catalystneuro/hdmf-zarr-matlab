function links = decodeLinks(encodedLinks)
%DECODELINKS Decode HDMF link records into neutral structs.
%   links = hdmf.zarr.conventions.decodeLinks(value) accepts the zarr_link
%   attribute value or its JSON representation. The returned struct array
%   has string fields name, source, path, object_id, and source_object_id.

    arguments
        encodedLinks
    end

    rawLinks = decodeJsonIfNeeded(encodedLinks);
    if isempty(rawLinks)
        links = emptyLinks();
        return
    elseif isstruct(rawLinks)
        entries = num2cell(rawLinks);
    elseif iscell(rawLinks)
        entries = rawLinks;
    else
        invalidLink("Links must be a struct array, cell array, or JSON array.")
    end

    linkTemplate = struct( ...
        "name", "", ...
        "source", "", ...
        "path", "", ...
        "object_id", "", ...
        "source_object_id", "");
    links = repmat(linkTemplate, 1, numel(entries));
    for iLink = 1:numel(entries)
        rawLink = entries{iLink};
        if ~isstruct(rawLink) || ~isscalar(rawLink) || ~isfield(rawLink, "name")
            invalidLink("Each link record must be a scalar struct with a name field.")
        end
        name = requireLinkName(rawLink.name);
        try
            reference = hdmf.zarr.conventions.decodeReference(rawLink);
        catch exception
            if startsWith(string(exception.identifier), "hdmf:conventions:")
                error("hdmf:conventions:InvalidLink", ...
                    "Link `%s` has an invalid reference: %s", name, exception.message)
            end
            rethrow(exception)
        end
        links(iLink) = struct( ...
            "name", name, ...
            "source", reference.source, ...
            "path", reference.path, ...
            "object_id", reference.object_id, ...
            "source_object_id", reference.source_object_id);
    end
end

function value = decodeJsonIfNeeded(value)
    if ischar(value) || isstring(value)
        if isstring(value) && ~isscalar(value)
            invalidLink("JSON-encoded links must be scalar text.")
        end
        try
            value = jsondecode(char(value));
        catch exception
            error("hdmf:conventions:InvalidLink", ...
                "Link JSON could not be decoded: %s", exception.message)
        end
    end
end

function name = requireLinkName(rawName)
    if ~(ischar(rawName) || (isstring(rawName) && isscalar(rawName)))
        invalidLink("Link name must be scalar text.")
    end
    name = string(rawName);
    if ismissing(name) || strlength(name) == 0 || contains(name, "/")
        invalidLink("Link name must be a nonempty path segment.")
    end
end

function links = emptyLinks()
    links = struct( ...
        "name", {}, ...
        "source", {}, ...
        "path", {}, ...
        "object_id", {}, ...
        "source_object_id", {});
end

function invalidLink(message, varargin)
    error("hdmf:conventions:InvalidLink", message, varargin{:})
end
