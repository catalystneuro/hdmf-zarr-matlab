classdef Link
%Link - A named reference: how hdmf-zarr represents group links
%
%   Zarr groups have no native link concept, so hdmf-zarr lists a
%   group's links in its "zarr_link" attribute: a JSON list of records,
%   each an hdmf.zarr.Reference record plus a "name" field. A Link
%   pairs that Name with its Target reference. Soft links point into
%   this store; external links name another store (Target.isExternal).
%
%   This class only converts links between their in-memory and on-disk
%   forms. Following a link -- treating Name as a child of the group
%   that leads to Target -- is the job of hdmf.zarr.resolve; creating
%   one in a store is hdmf.zarr.File.addLink.
%
%   link = Link() creates the default link (empty name, this store's
%   root). Array growth and decode rely on this default.
%
%   link = Link(name, target) creates a link called name pointing at
%   target, an hdmf.zarr.Reference or a path string.
%
%   Link functions:
%       encode         - zarr_link attribute value: one record per link
%       decode         - (Static) Parse links from a zarr_link value
%       fromAttributes - (Static) Links declared in a node's attributes
%
%   Link properties:
%       Name   - Name of the link, as a child of the group
%       Target - Where the link points (an hdmf.zarr.Reference)
%
%   Example: Encode and decode a link record
%       link = hdmf.zarr.Link("device", "general/devices/probe0");
%       entries = link.encode()          % cell of zarr_link records
%       hdmf.zarr.Link.decode(entries)
%
%   See also hdmf.zarr.Reference, hdmf.zarr.resolve, hdmf.zarr.File

    properties
        %Name - Name of the link as it appears as a child of the group
        Name (1,1) string = ""

        %Target - Where the link points
        Target (1,1) hdmf.zarr.Reference = hdmf.zarr.Reference()
    end

    methods
        function obj = Link(name, target)
        %Link - Construct a named link to a Reference or path

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
        %encode - zarr_link attribute value: cell of records, one per link
        %   entries = encode(obj) returns the on-disk form of the
        %   links: each record is the target's reference record plus
        %   "name". A cell (not a struct array) so that jsonencode
        %   always emits a JSON list, even for a single link: a 1x1
        %   struct array would serialize as a bare object, which
        %   hdmf-zarr does not accept.

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
        %decode - Parse link(s) from a zarr_link attribute value
        %   links = decode(value) parses a struct array or cell of
        %   records, a single record, or empty ([] is what jsondecode
        %   gives for an empty JSON list, which hdmf-zarr writes before
        %   adding the first link), and returns a 1xN Link array.
        %   Raises hdmf:InvalidLink for records without a "name".

            arguments
                value {mustBeA(value, ["struct", "cell", "double", "dictionary"])}
            end
            if isa(value, 'dictionary')
                value = {value};        % a lone record, not a list
            elseif isempty(value)
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
                [hasName, name] = hdmf.zarr.internal.recordField(entry, 'name');
                if ~hasName
                    error("hdmf:InvalidLink", "Link record %d has no 'name' field.", i);
                end
                links(i) = hdmf.zarr.Link(string(char(name)), ...
                    hdmf.zarr.Reference.decode(entry));
            end
        end

        function links = fromAttributes(attributes)
        %fromAttributes - Links declared in a node's attributes
        %   links = fromAttributes(attributes) reads the "zarr_link"
        %   entry of a node's attributes (e.g. group.attrs, a
        %   dictionary) and returns an empty 1x0 array if the node
        %   declares no links. A scalar struct is accepted too, so a
        %   test can hand it a literal.

            [found, entries] = hdmf.zarr.internal.recordField(attributes, 'zarr_link');
            if found
                links = hdmf.zarr.Link.decode(entries);
            else
                links = hdmf.zarr.Link.empty(1, 0);
            end
        end
    end
end
