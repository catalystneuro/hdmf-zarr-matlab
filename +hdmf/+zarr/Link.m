classdef Link
    %LINK - A named reference stored in a group's zarr_link attribute.
    %   Soft links point into this store (Target.Source == "."); external
    %   links name another store.
    %
    %   On disk a group's "zarr_link" attribute is a JSON list of records
    %   {"name": ..., "source": ..., "path": ..., "object_id": ...,
    %   "source_object_id": ...}; fromAttributes / decode read that list and
    %   encode produces it. Following a link is the job of hdmf.zarr.resolve.
    %
    %   Example:
    %     links = hdmf.zarr.Link.fromAttributes(group.attrs);
    %     group.setAttr('zarr_link', encode([links, newLink]));

    properties
        % Name of the link as it appears as a child of the group.
        Name (1,1) string = ""
        % Where the link points.
        Target (1,1) hdmf.zarr.Reference = hdmf.zarr.Reference()
    end

    methods
        function obj = Link(name, target)
            %LINK - Construct a link. target is a Reference or a path string.
            %   hdmf.zarr.Link("device", "general/devices/probe0")
            %   hdmf.zarr.Link("device", hdmf.zarr.Reference(..., ObjectId=...))
            arguments
                name (1,1) string = ""
                target {mustBeA(target, ["hdmf.zarr.Reference", "string", "char"])} = ...
                    hdmf.zarr.Reference()
            end
            obj.Name = name;
            if isa(target, 'hdmf.zarr.Reference')
                obj.Target = target;
            else
                obj.Target = hdmf.zarr.Reference(target);
            end
        end

        function entries = encode(obj)
            %ENCODE - zarr_link attribute value: cell of records, one per link.
            %   A cell (not a struct array) so that jsonencode always emits a
            %   JSON list, even for a single link: a 1x1 struct array would
            %   serialize as a bare object, which hdmf-zarr does not accept.
            entries = cell(1, numel(obj));
            for i = 1:numel(obj)
                % the link record is the reference record plus "name"
                target = obj(i).Target.encode();
                entries{i} = cell2struct( ...
                    [struct2cell(target); {char(obj(i).Name)}], ...
                    [fieldnames(target); {'name'}]);
            end
        end
    end

    methods (Static)
        function links = decode(value)
            %DECODE - Parse link(s) from a zarr_link attribute value.
            %   value is a struct array or cell of records, a single record,
            %   or empty ([] is what jsondecode gives for an empty JSON list,
            %   which hdmf-zarr writes before adding the first link). Returns
            %   a 1xN Link array.
            arguments
                value {mustBeA(value, ["struct", "cell", "double"])}
            end
            if isempty(value)
                value = {};
            elseif isstruct(value)
                value = num2cell(value);
            elseif ~iscell(value)
                error("hdmf:InvalidLink", ...
                    "Cannot decode links from a %s. Expected a list of link records.", ...
                    class(value));
            end
            links = repmat(hdmf.zarr.Link(), 1, numel(value));
            for i = 1:numel(value)
                entry = value{i};
                if ~isstruct(entry) || ~isfield(entry, 'name')
                    error("hdmf:InvalidLink", "Link record %d has no 'name' field.", i);
                end
                links(i) = hdmf.zarr.Link(string(char(entry.name)), ...
                    hdmf.zarr.Reference.decode(entry));
            end
        end

        function links = fromAttributes(attributes)
            %FROMATTRIBUTES - Links declared in a node's attributes struct.
            %   Reads the "zarr_link" field; returns an empty 1x0 array if
            %   the node declares no links.
            arguments
                attributes struct
            end
            if isfield(attributes, 'zarr_link')
                links = hdmf.zarr.Link.decode(attributes.zarr_link);
            else
                links = hdmf.zarr.Link.empty(1, 0);
            end
        end
    end
end
