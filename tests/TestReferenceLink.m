classdef TestReferenceLink < matlab.unittest.TestCase
    %Store-free encode/decode of the hdmf-zarr reference and link records.
    %   These pin the on-disk shapes (field names, optional source, list-
    %   vs-object) that hdmf.zarr.File and external consumers such as
    %   MatNWB both rely on, and the legacy shapes that are still read.

    methods (Test)
        % ---------------------------------------------------------- Reference
        function pathIsNormalizedToAbsolute(tc)
            for p = ["a/b", "/a/b", "/a/b/", "a//b"]
                tc.verifyEqual(hdmf.zarr.Reference(p).Path, "/a/b", ...
                    "input '" + p + "'");
            end
            tc.verifyEqual(hdmf.zarr.Reference().Path, "/");
            tc.verifyEqual(hdmf.zarr.Reference("").Path, "/");
        end

        function encodeWritesSourceAndPathOnly(tc)
            s = hdmf.zarr.Reference("a/b").encode();
            tc.verifyEqual(s, struct('source', '.', 'path', '/a/b'));
            % ids decoded from a legacy record are not written back
            s = hdmf.zarr.Reference("a/b", ObjectId="oid", SourceObjectId="root").encode();
            tc.verifyEqual(s, struct('source', '.', 'path', '/a/b'));
        end

        function encodeArrayIsStructIfHomogeneousElseCell(tc)
            same = [hdmf.zarr.Reference("a"), hdmf.zarr.Reference("b")];
            s = same.encode();
            tc.verifyClass(s, 'struct');
            tc.verifySize(s, [1 2]);
            tc.verifyEqual({s.path}, {'/a', '/b'});
            % a reference without a source has no source field to write
            mixed = [hdmf.zarr.Reference("a"); hdmf.zarr.Reference("b", Source="")];
            c = mixed.encode();
            tc.verifyClass(c, 'cell');    % records differ in fields, as jsondecode would return
            tc.verifySize(c, [2 1]);
            tc.verifyFalse(isfield(c{2}, 'source'));
            tc.verifySize(hdmf.zarr.Reference.empty(0, 1).encode(), [0 1]);
        end

        function encodeElementIsPathElementwise(tc)
            refs = [hdmf.zarr.Reference("a"); hdmf.zarr.Reference("b/c")];
            txt = refs.encodeElement();
            tc.verifySize(txt, [2 1]);
            tc.verifyEqual(txt, ["/a"; "/b/c"]);
        end

        function encodeElementRejectsExternalReferences(tc)
            % A bare path names a node of the same store.
            refs = [hdmf.zarr.Reference("a"), hdmf.zarr.Reference("b", Source="other.zarr")];
            tc.verifyError(@() refs.encodeElement(), "hdmf:InvalidReference");
        end

        function encodeAttributeWraps(tc)
            d = hdmf.zarr.Reference("a/b").encodeAttribute();
            tc.verifyClass(d, 'dictionary');
            tc.verifyEqual(keys(d), "_REFERENCE");
            tc.verifyEqual(d{"_REFERENCE"}, struct('source', '.', 'path', '/a/b'));
        end

        function decodeAcceptsAllForms(tc)
            record = struct('source', '.', 'path', '/a/b');
            wrapped = dictionary(string.empty, {});
            wrapped("_REFERENCE") = {record};
            forms = {record, ...                                    % bare
                wrapped, ...                                         % attribute
                "/a/b", ...                                          % dataset element
                'a/b', ...                                           % char element
                string(jsonencode(record)), ...                      % legacy element
                struct('zarr_dtype', 'object', 'value', record)};    % legacy attribute
            for i = 1:numel(forms)
                r = hdmf.zarr.Reference.decode(forms{i});
                tc.verifyClass(r, 'hdmf.zarr.Reference');
                tc.verifyEqual(r.Path, "/a/b", "form " + i);
                tc.verifyEqual(r.Source, ".", "form " + i);
            end
        end

        function decodeKeepsLegacyObjectIds(tc)
            % hdmf-zarr before 0.14 wrote object ids into every record.
            record = struct('source', '.', 'path', '/a/b', 'object_id', 'oid', ...
                'source_object_id', 'root');
            r = hdmf.zarr.Reference.decode(string(jsonencode(record)));
            tc.verifyEqual(r.ObjectId, "oid");
            tc.verifyEqual(r.SourceObjectId, "root");
        end

        function decodeIsShapePreserving(tc)
            txt = ["/a"; "{""source"":""."",""path"":""/b""}"];   % a path and a legacy record
            refs = hdmf.zarr.Reference.decode(txt);
            tc.verifySize(refs, [2 1]);
            tc.verifyEqual([refs.Path], ["/a", "/b"]);
            tc.verifySize(hdmf.zarr.Reference.decode(strings(0, 1)), [0 1]);
        end

        function roundTripPreservesFields(tc)
            ref = hdmf.zarr.Reference("x/y", Source="other.zarr");
            back = hdmf.zarr.Reference.decode(jsondecode(jsonencode(ref.encode())));
            tc.verifyEqual(back, ref);
            tc.verifyTrue(back.isExternal());
            tc.verifyFalse(hdmf.zarr.Reference("x").isExternal());
            local = hdmf.zarr.Reference("x/y");
            tc.verifyEqual(hdmf.zarr.Reference.decode(local.encodeElement()), local);
        end

        function decodeRejectsNonReferences(tc)
            tc.verifyError(@() hdmf.zarr.Reference.decode(struct('source', '.')), ...
                "hdmf:InvalidReference");                       % no path field
            tc.verifyError(@() hdmf.zarr.Reference.decode("{not json"), "hdmf:InvalidReference");
            wrappedText = dictionary(string.empty, {});
            wrappedText("_REFERENCE") = {"/a"};
            tc.verifyError(@() hdmf.zarr.Reference.decode(wrappedText), "hdmf:InvalidReference");
            % "" is what unwritten chunks of a string dataset read as
            tc.verifyError(@() hdmf.zarr.Reference.decode(["/a"; ""]), ...
                "hdmf:InvalidReference");
            tc.verifyError(@() hdmf.zarr.Reference.decode(42), "MATLAB:validators:mustBeA");
        end

        function decodeAcceptsWhatEncodeReturns(tc)
            % mixed sources -> encode returns a cell; decode must take it back
            mixed = [hdmf.zarr.Reference("a"); hdmf.zarr.Reference("b", Source="")];
            tc.verifyEqual(hdmf.zarr.Reference.decode(mixed.encode()), mixed);
            same = [hdmf.zarr.Reference("a"), hdmf.zarr.Reference("b")];
            tc.verifyEqual(hdmf.zarr.Reference.decode(same.encode()), same);
        end

        function recordWithoutSourceIsExternal(tc)
            % hdmf-zarr's resolve_ref treats a missing source as "path names
            % another file"; it must not be read as an in-store reference.
            ref = hdmf.zarr.Reference.decode(struct('path', 'other.nwb.zarr'));
            tc.verifyEqual(ref.Source, "");
            tc.verifyTrue(ref.isExternal());
            % and it round-trips without inventing a source
            tc.verifyFalse(isfield(ref.encode(), 'source'));
            tc.verifyEqual(hdmf.zarr.Reference.decode(jsondecode(jsonencode(ref.encode()))), ref);
        end

        function identicalReferencesAreEqual(tc)
            % unknown ids are "" rather than missing so isequal/unique work
            tc.verifyTrue(isequal(hdmf.zarr.Reference("x"), hdmf.zarr.Reference("x")));
            tc.verifyTrue(isequal(hdmf.zarr.Link("a", "/x"), hdmf.zarr.Link("a", "/x")));
            tc.verifyFalse(isequal(hdmf.zarr.Reference("x"), ...
                hdmf.zarr.Reference("x", ObjectId="1")));
        end

        function emptyArraysKeepTheirTypes(tc)
            empty = hdmf.zarr.Reference.empty(0, 1);
            tc.verifyClass(empty.encodeElement(), 'string');
            tc.verifySize(empty.encodeElement(), [0 1]);
            tc.verifyClass(empty.isExternal(), 'logical');
            tc.verifySize(empty.isExternal(), [0 1]);
        end

        % --------------------------------------------------------------- Link
        function linkEncodesAsListEvenWhenSingle(tc)
            link = hdmf.zarr.Link("device", "general/devices/probe0");
            entries = link.encode();
            tc.verifyClass(entries, 'cell');
            tc.verifySize(entries, [1 1]);
            tc.verifyEqual(entries{1}, struct('source', '.', ...
                'path', '/general/devices/probe0', 'name', 'device'));
            % the reason for the cell: jsonencode must emit a JSON list
            tc.verifyTrue(startsWith(jsonencode(entries), "["));
        end

        function linkDecodesStructArrayAndCell(tc)
            records = struct('name', {'a', 'b'}, 'source', {'.', '.'}, ...
                'path', {'/x', '/y'});
            fromStruct = hdmf.zarr.Link.decode(records);
            fromCell = hdmf.zarr.Link.decode(num2cell(records));
            tc.verifyEqual(fromStruct, fromCell);
            tc.verifySize(fromStruct, [1 2]);
            tc.verifyEqual([fromStruct.Name], ["a", "b"]);
            tc.verifyEqual(fromStruct(2).Target.Path, "/y");
        end

        function linkFromAttributesHandlesAbsence(tc)
            tc.verifySize(hdmf.zarr.Link.fromAttributes(struct()), [1 0]);
            % hdmf-zarr writes "_LINKS": [] before the first link is added;
            % a JSON null or an empty list reads back empty
            tc.verifySize(hdmf.zarr.Link.fromAttributes(linkAttributes("_LINKS", [])), [1 0]);
            tc.verifySize(hdmf.zarr.Link.fromAttributes(linkAttributes("_LINKS", {})), [1 0]);
            tc.verifySize(hdmf.zarr.Link.decode({}), [1 0]);
            record = struct('name', 'n', 'source', '.', 'path', '/p');
            links = hdmf.zarr.Link.fromAttributes(linkAttributes("_LINKS", {record}));
            tc.verifyEqual(links.Name, "n");
        end

        function linkFromAttributesReadsLegacyName(tc)
            % hdmf-zarr before 0.14 listed links under zarr_link
            record = struct('name', 'n', 'source', '.', 'path', '/p');
            links = hdmf.zarr.Link.fromAttributes(struct('zarr_link', {{record}}));
            tc.verifyEqual(links.Name, "n");
        end

        function linkFromAttributesPrefersCurrentName(tc)
            % as hdmf-zarr does: _LINKS, when present, is the whole list
            attributes = linkAttributes("_LINKS", ...
                {struct('name', 'current', 'source', '.', 'path', '/p')});
            attributes("zarr_link") = {{struct('name', 'legacy', 'source', '.', 'path', '/q')}};
            links = hdmf.zarr.Link.fromAttributes(attributes);
            tc.verifyEqual([links.Name], "current");
        end

        function linkRoundTrip(tc)
            links = [hdmf.zarr.Link("a", hdmf.zarr.Reference("/x")), ...
                hdmf.zarr.Link("b", "/y")];
            % through JSON, as the attribute actually travels
            back = hdmf.zarr.Link.decode(jsondecode(jsonencode(links.encode())));
            tc.verifyEqual(back, links);
        end

        function linkDecodeRejectsNameless(tc)
            tc.verifyError(@() hdmf.zarr.Link.decode(struct('source', '.', 'path', '/p')), ...
                "hdmf:InvalidLink");
        end
    end
end

function attributes = linkAttributes(name, value)
%linkAttributes - Node attributes holding one entry, as a store returns them
%   A dictionary, since a struct cannot carry a key such as "_LINKS".

attributes = dictionary(string.empty, {});
attributes(name) = {value};
end
