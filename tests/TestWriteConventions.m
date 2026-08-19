classdef TestWriteConventions < matlab.unittest.TestCase
    %M4: writing links and references per the hdmf-zarr conventions.

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
            tc.verifyEqual(string(char(dev.attrs.neurodata_type)), "Device");
            L = f.links("acquisition");
            tc.verifyEqual(L(1).Name, "device");
            tc.verifyEqual(L(1).Target.Source, ".");
            tc.verifyEqual(L(1).Target.Path, "/general/devices/probe0");
            tc.verifyEqual(L(1).Target.ObjectId, "dev-oid-1");
        end

        function singleLinkSerializesAsList(tc)
            [f, store] = TestWriteConventions.freshFile(fullfile(tc.work, "b.zarr"));
            f.addLink("acquisition", "device", "general/devices/probe0");
            [bytes, ~] = store.get("acquisition/zarr.json");
            txt = native2unicode(bytes, 'UTF-8');
            tc.verifySubstring(txt, '"zarr_link":[{');   % list, not object
        end

        function refDatasetRoundTrip(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "c.zarr"));
            f.writeRefs("acquisition/ts/electrodes_ish", ...
                ["general/devices/probe0", "acquisition/ts/data"]);
            col = f.resolve("acquisition/ts/electrodes_ish");
            tc.verifyTrue(hdmf.zarr.isReferenceArray(col));
            nodes = f.derefAll(col);
            tc.verifyEqual(string(char(nodes{1}.attrs.object_id)), "dev-oid-1");
            tc.verifyClass(nodes{2}, 'zarr.Array');
            % object ids recorded per convention
            r = jsondecode(char(subsref(col.read(), substruct('()', {1}))));
            tc.verifyEqual(string(r.object_id), "dev-oid-1");
            tc.verifyEqual(string(r.source_object_id), "root-oid-1");
        end

        function attrRefRoundTrip(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "d.zarr"));
            f.setRefAttr("acquisition/ts/data", "table", "general/devices/probe0");
            node = f.resolve("acquisition/ts/data");
            target = f.deref(node.attrs.table);
            tc.verifyEqual(string(char(target.attrs.object_id)), "dev-oid-1");
        end

        function missingChildRaisesResolveError(tc)
            [f, ~] = TestWriteConventions.freshFile(fullfile(tc.work, "f.zarr"));
            % a group with no zarr_link at all, and one with an empty list
            zarr.create_group(f.store, Path="emptylinks", ...
                Attributes=struct('zarr_link', []));
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
                Attributes=struct('zarr_link', {{foreign}}));
            f.refresh();
            f.addLink("withforeign", "device", "general/devices/probe0");
            group = f.resolve("withforeign");
            raw = group.attrs.zarr_link;
            if isstruct(raw), raw = num2cell(raw); end
            tc.verifyEqual(numel(raw), 2);
            tc.verifyEqual(raw{1}.extra, 'keep me');   % untouched, not re-encoded
            tc.verifyTrue(isfield(raw{1}, 'object_id'));
            tc.verifyEqual(raw{2}.name, 'device');
            % and both links still resolve
            tc.verifyClass(f.resolve("withforeign/other"), 'zarr.Array');
            tc.verifyClass(f.resolve("withforeign/device"), 'zarr.Group');
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
            tc.verifyEqual(string(char(dev.attrs.neurodata_type)), "Device");
        end
    end
end
