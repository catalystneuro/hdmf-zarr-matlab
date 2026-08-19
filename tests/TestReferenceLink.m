classdef TestReferenceLink < matlab.unittest.TestCase
    %Store-free encode/decode of the hdmf-zarr reference and link records.
    %   These pin the on-disk shapes (field names, optional ids, list-vs-
    %   object) that hdmf.zarr.File and external consumers such as MatNWB
    %   both rely on.

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

        function encodeOmitsUnknownIds(tc)
            s = hdmf.zarr.Reference("a/b").encode();
            tc.verifyEqual(s, struct('source', '.', 'path', '/a/b'));
            s = hdmf.zarr.Reference("a/b", ObjectId="oid", SourceObjectId="root").encode();
            tc.verifyEqual(s, struct('source', '.', 'path', '/a/b', ...
                'object_id', 'oid', 'source_object_id', 'root'));
        end

        function encodeArrayIsStructIfHomogeneousElseCell(tc)
            same = [hdmf.zarr.Reference("a"), hdmf.zarr.Reference("b")];
            s = same.encode();
            tc.verifyClass(s, 'struct');
            tc.verifySize(s, [1 2]);
            tc.verifyEqual({s.path}, {'/a', '/b'});
            mixed = [hdmf.zarr.Reference("a"); hdmf.zarr.Reference("b", ObjectId="x")];
            c = mixed.encode();
            tc.verifyClass(c, 'cell');    % records differ in fields, as jsondecode would return
            tc.verifySize(c, [2 1]);
            tc.verifyEqual(c{2}.object_id, 'x');
            tc.verifySize(hdmf.zarr.Reference.empty(0, 1).encode(), [0 1]);
        end

        function encodeJsonIsElementwise(tc)
            refs = [hdmf.zarr.Reference("a"); hdmf.zarr.Reference("b", ObjectId="x")];
            txt = refs.encodeJson();
            tc.verifySize(txt, [2 1]);
            tc.verifyEqual(txt(1), "{""source"":""."",""path"":""/a""}");
            tc.verifyEqual(jsondecode(txt(2)).object_id, 'x');
        end

        function encodeAttributeWraps(tc)
            s = hdmf.zarr.Reference("a/b").encodeAttribute();
            tc.verifyEqual(s.zarr_dtype, 'object');
            tc.verifyEqual(s.value, struct('source', '.', 'path', '/a/b'));
        end

        function decodeAcceptsAllForms(tc)
            record = struct('source', '.', 'path', '/a/b', 'object_id', 'oid');
            forms = {record, ...                                    % bare
                struct('zarr_dtype', 'object', 'value', record), ... % attribute
                jsonencode(record), ...                              % char JSON
                string(jsonencode(record))};                         % string JSON
            for i = 1:numel(forms)
                r = hdmf.zarr.Reference.decode(forms{i});
                tc.verifyClass(r, 'hdmf.zarr.Reference');
                tc.verifyEqual(r.Path, "/a/b", "form " + i);
                tc.verifyEqual(r.ObjectId, "oid", "form " + i);
                tc.verifyTrue(ismissing(r.SourceObjectId), "form " + i);
            end
        end

        function decodeIsShapePreserving(tc)
            txt = ["{""source"":""."",""path"":""/a""}"; "{""source"":""."",""path"":""/b""}"];
            refs = hdmf.zarr.Reference.decode(txt);
            tc.verifySize(refs, [2 1]);
            tc.verifyEqual([refs.Path], ["/a", "/b"]);
            tc.verifySize(hdmf.zarr.Reference.decode(strings(0, 1)), [0 1]);
        end

        function roundTripPreservesFields(tc)
            ref = hdmf.zarr.Reference("x/y", Source="other.zarr", ...
                ObjectId="o", SourceObjectId="s");
            back = hdmf.zarr.Reference.decode(ref.encodeJson());
            tc.verifyEqual(back, ref);
            tc.verifyTrue(back.isExternal());
            tc.verifyFalse(hdmf.zarr.Reference("x").isExternal());
        end

        function decodeRejectsMissingPath(tc)
            tc.verifyError(@() hdmf.zarr.Reference.decode(struct('source', '.')), ...
                "hdmf:InvalidReference");
            tc.verifyError(@() hdmf.zarr.Reference.decode(42), "hdmf:InvalidReference");
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
            attrs = struct('zarr_link', {{struct('name', 'n', 'source', '.', 'path', '/p')}});
            links = hdmf.zarr.Link.fromAttributes(attrs);
            tc.verifyEqual(links.Name, "n");
        end

        function linkRoundTrip(tc)
            links = [hdmf.zarr.Link("a", hdmf.zarr.Reference("/x", ObjectId="1")), ...
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
