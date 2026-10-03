classdef TestWriteConventions < matlab.unittest.TestCase
    %Writing links and references per the hdmf-zarr conventions, and
    %   reading the forms hdmf-zarr wrote before 0.14.

    properties
        work
    end

    methods (TestMethodSetup)
        function makeWork(tc)
            tc.work = fullfile(tempdir, "hdmf_w_" + string(feature('getpid')) + ...
                "_" + string(randi(1e9)));
            mkdir(tc.work);
        end
    end

    methods (TestMethodTeardown)
        function rmWork(tc)
            if isfolder(tc.work), rmdir(tc.work, 's'); end
        end
    end

    methods (Static)
        function [f, store] = freshFile(root)
            store = zarr.stores.LocalStore(root);
            zarr.create_group(store, Attributes=struct('object_id', 'root-oid-1'));
            zarr.create_group(store, Path="general/devices/probe0", ...
                Attributes=struct('object_id', 'dev-oid-1', 'neurodata_type', 'Device'));
            z = zarr.create(store, [4 3], "float64", Path="acquisition/ts/data", ...
                ChunkShape=[2 3]);
            z.write(reshape(1:12, [4 3]));
            f = hdmf.zarr.open(store);
        end
    end

    methods (Test)
        function linkRoundTrip(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "a.zarr"));
            f.addLink("acquisition", "device", "general/devices/probe0");
            dev = f.resolve("acquisition/device");
            tc.verifyEqual(dev.attrs{"neurodata_type"}, "Device");
            L = f.links("acquisition");
            tc.verifyEqual(L(1).Name, "device");
            tc.verifyEqual(L(1).Target.Source, ".");
            tc.verifyEqual(L(1).Target.Path, "/general/devices/probe0");
        end

        function singleLinkSerializesAsList(tc)
            [f, store] = TestWriteConventions.freshFile(fullfile(tc.work, "b.zarr"));
            f.addLink("acquisition", "device", "general/devices/probe0");
            [bytes, ~] = store.get("acquisition/zarr.json");
            txt = native2unicode(bytes, 'UTF-8');
            tc.verifySubstring(txt, '"_LINKS":[{');   % list, not object
            tc.verifyFalse(contains(txt, "zarr_link"));
            tc.verifyFalse(contains(txt, "object_id"), 'links carry no object ids');
        end

        function compoundDtypeHintIsNotAReferenceArray(tc)
            % hdmf-zarr tags a compound dataset with a zarr_dtype LIST of
            % per-field descriptors; the predicate must answer false, not
            % choke on the non-text attribute.
            [~, store] = TestWriteConventions.freshFile(fullfile(tc.work, "e.zarr"));
            fieldHints = {struct('name', 'x', 'dtype', 'int32'), ...
                struct('name', 'ts', 'dtype', 'object')};
            arr = zarr.create(store, 2, "string", Path="acquisition/compound_ish", ...
                Attributes=struct('zarr_dtype', {fieldHints}));
            tc.verifyFalse(hdmf.zarr.isReferenceArray(arr));
            tc.verifyFalse(hdmf.zarr.isReferenceArray(struct('attrs', 1)));
        end

        function textDatasetIsNotAReferenceArray(tc)
            % hdmf-zarr records the dtype of every dataset in _DTYPE; only
            % "object_reference" marks references.
            [~, store] = TestWriteConventions.freshFile(fullfile(tc.work, "j.zarr"));
            arr = zarr.create(store, 2, "string", Path="acquisition/labels", ...
                Attributes=dtypeAttributes("utf8"));
            tc.verifyFalse(hdmf.zarr.isReferenceArray(arr));
        end

        function refDatasetRoundTrip(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "c.zarr"));
            f.writeRefs("acquisition/ts/electrodes_ish", ...
                ["general/devices/probe0", "acquisition/ts/data"]);
            col = f.resolve("acquisition/ts/electrodes_ish");
            tc.verifyTrue(hdmf.zarr.isReferenceArray(col));
            nodes = f.derefAll(col);
            tc.verifyEqual(nodes{1}.attrs{"object_id"}, "dev-oid-1");
            tc.verifyClass(nodes{2}, 'zarr.Array');
            % elements are plain target paths, marked by _DTYPE
            tc.verifyEqual(col.attrs{"_DTYPE"}, "object_reference");
            tc.verifyFalse(isKey(col.attrs, "zarr_dtype"));
            tc.verifyEqual(col.read(), ["/general/devices/probe0"; "/acquisition/ts/data"]);
        end

        function refDatasetKeepsGivenAttributes(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "k.zarr"));
            f.writeRefs("acquisition/ts/col", "general/devices/probe0", ...
                Attributes=struct('neurodata_type', 'VectorData'));
            col = f.resolve("acquisition/ts/col");
            tc.verifyEqual(col.attrs{"neurodata_type"}, "VectorData");
            tc.verifyTrue(hdmf.zarr.isReferenceArray(col));
        end

        function attrRefRoundTrip(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "d.zarr"));
            f.setRefAttr("acquisition/ts/data", "table", "general/devices/probe0");
            node = f.resolve("acquisition/ts/data");
            target = f.deref(node.attrs{"table"});
            tc.verifyEqual(target.attrs{"object_id"}, "dev-oid-1");
            % {"_REFERENCE": {source, path}}
            record = node.attrs{"table"}{"_REFERENCE"};
            tc.verifyEqual(sort(keys(record)), ["path"; "source"]);
            tc.verifyEqual(record{"path"}, "/general/devices/probe0");
        end

        function missingChildRaisesResolveError(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "f.zarr"));
            % a group with no _LINKS at all, and one with an empty list
            zarr.create_group(f.store, Path="emptylinks", ...
                Attributes=linksAttributes({}));
            f.refresh();
            tc.verifyError(@() f.resolve("general/nope"), "hdmf:ResolveError");
            tc.verifyError(@() f.resolve("emptylinks/nope"), "hdmf:ResolveError");
            tc.verifySize(f.links("emptylinks"), [1 0]);
            % and the empty list does not block adding the first link
            f.addLink("emptylinks", "device", "general/devices/probe0");
            tc.verifyEqual(f.links("emptylinks").Name, "device");
        end

        function addLinkPreservesForeignRecords(tc)
            [f, store] = TestWriteConventions.freshFile(fullfile(tc.work, "g.zarr"));
            foreign = struct('name', 'other', 'source', '.', 'path', '/acquisition/ts/data', ...
                'object_id', [], 'extra', 'keep me');
            zarr.create_group(store, Path="withforeign", ...
                Attributes=linksAttributes({foreign}));
            f.refresh();
            f.addLink("withforeign", "device", "general/devices/probe0");
            group = f.resolve("withforeign");
            % A JSON list of objects reads back as a cell of dictionaries.
            raw = group.attrs{"_LINKS"};
            tc.verifyEqual(numel(raw), 2);
            tc.verifyEqual(raw{1}{"extra"}, "keep me");   % untouched, not re-encoded
            tc.verifyTrue(isKey(raw{1}, "object_id"), 'a null field survives');
            tc.verifyEqual(raw{2}{"name"}, "device");
            % and both links still resolve
            tc.verifyClass(f.resolve("withforeign/other"), 'zarr.Array');
            tc.verifyClass(f.resolve("withforeign/device"), 'zarr.Group');
        end

        function addLinkCarriesLegacyLinksForward(tc)
            % Readers take _LINKS alone when it is present, so the links a
            % group lists under zarr_link move into it with the new one.
            [f, store] = TestWriteConventions.freshFile(fullfile(tc.work, "l.zarr"));
            legacy = struct('name', 'other', 'source', '.', 'path', '/acquisition/ts/data', ...
                'object_id', 'data-oid');
            zarr.create_group(store, Path="legacylinks", ...
                Attributes=struct('zarr_link', {{legacy}}));
            f.refresh();
            f.addLink("legacylinks", "device", "general/devices/probe0");
            raw = f.resolve("legacylinks").attrs{"_LINKS"};
            tc.verifyEqual(numel(raw), 2);
            tc.verifyEqual(raw{1}{"object_id"}, "data-oid");   % copied as stored
            tc.verifyEqual([f.links("legacylinks").Name], ["other", "device"]);
        end

        % ------------------------------------------------------------------
        % Reading what hdmf-zarr wrote before 0.14

        function legacyLinksResolve(tc)
            [f, store] = TestWriteConventions.freshFile(fullfile(tc.work, "m.zarr"));
            legacy = struct('name', 'device', 'source', '.', 'path', '/general/devices/probe0', ...
                'object_id', 'dev-oid-1', 'source_object_id', 'root-oid-1');
            zarr.create_group(store, Path="legacy", Attributes=struct('zarr_link', {{legacy}}));
            f.refresh();
            dev = f.resolve("legacy/device");
            tc.verifyEqual(dev.attrs{"neurodata_type"}, "Device");
            tc.verifyEqual(f.links("legacy").Target.ObjectId, "dev-oid-1");
        end

        function legacyRefDatasetDereferences(tc)
            % string elements holding JSON records, marked zarr_dtype "object"
            [f, store] = TestWriteConventions.freshFile(fullfile(tc.work, "n.zarr"));
            records = ["{""source"":""."",""path"":""/general/devices/probe0"",""object_id"":""dev-oid-1""}"; ...
                "{""source"":""."",""path"":""/acquisition/ts/data""}"];
            legacyColumn = zarr.create(store, 2, "string", Path="acquisition/legacy_refs", ...
                Attributes=struct('zarr_dtype', 'object'));
            legacyColumn.write(records);
            f.refresh();
            col = f.resolve("acquisition/legacy_refs");
            tc.verifyTrue(hdmf.zarr.isReferenceArray(col));
            nodes = f.derefAll(col);
            tc.verifyEqual(nodes{1}.attrs{"neurodata_type"}, "Device");
            tc.verifyClass(nodes{2}, 'zarr.Array');
            refs = hdmf.zarr.Reference.decode(col.read());
            tc.verifyEqual([refs.ObjectId], ["dev-oid-1"; ""]');
        end

        function legacyAttrRefDereferences(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "o.zarr"));
            node = f.resolve("acquisition/ts/data");
            node.setAttr("table", struct('zarr_dtype', 'object', ...
                'value', struct('source', '.', 'path', '/general/devices/probe0')));
            f.refresh();
            node = f.resolve("acquisition/ts/data");
            target = f.deref(node.attrs{"table"});
            tc.verifyEqual(target.attrs{"neurodata_type"}, "Device");
        end

        function resolveRejectsReferenceArrays(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "h.zarr"));
            refs = [hdmf.zarr.Reference("general"), hdmf.zarr.Reference("/")];
            tc.verifyError(@() f.resolve(refs), "hdmf:ResolveError");
            tc.verifyError(@() f.deref(refs), "hdmf:ResolveError");
            tc.verifySize(f.derefAll(refs), [1 2]);   % the array entry point
        end

        function derefAllResolvesRepeatedTargets(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "i.zarr"));
            targets = repmat(["general/devices/probe0", "acquisition/ts/data"], 1, 3);
            f.writeRefs("acquisition/ts/many", targets);
            nodes = f.derefAll(f.resolve("acquisition/ts/many"));
            tc.verifySize(nodes, [6 1]);
            tc.verifyEqual(cellfun(@(n) string(n.path), nodes), ...
                repmat(["general/devices/probe0"; "acquisition/ts/data"], 3, 1));
        end

        function writesSurviveConsolidation(tc)
            root = fullfile(tc.work, "e.zarr");
            [f, store] = TestWriteConventions.freshFile(root);
            zarr.consolidate_metadata(store);
            f.refresh();
            f.addLink("acquisition", "device", "general/devices/probe0");
            % a brand-new File (fresh consolidated view) must see the link
            f2 = hdmf.zarr.open(root);
            dev = f2.resolve("acquisition/device");
            tc.verifyEqual(dev.attrs{"neurodata_type"}, "Device");
        end
    end
end

function attributes = linksAttributes(entries)
%linksAttributes - Group attributes listing link records under _LINKS
%   A dictionary, since a struct cannot carry the key "_LINKS".

attributes = dictionary(string.empty, {});
attributes("_LINKS") = {entries};
end

function attributes = dtypeAttributes(dtype)
%dtypeAttributes - Dataset attributes recording an hdmf dtype under _DTYPE

attributes = dictionary(string.empty, {});
attributes("_DTYPE") = {dtype};
end
