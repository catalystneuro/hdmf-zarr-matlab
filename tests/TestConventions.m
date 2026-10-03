classdef TestConventions < matlab.unittest.TestCase
    %Reads the NWB fixture written by hdmf-zarr 0.14: links, references
    %   in attributes and datasets, scalar datasets, spec caching, and
    %   array data.

    properties
        fixture
    end

    methods (TestClassSetup)
        function findOrMakeFixture(tc)
            root = fileparts(fileparts(mfilename('fullpath')));
            tc.fixture = fullfile(root, 'scratch', 'fixture.nwb.zarr');
            if ~isfolder(tc.fixture)
                py = fullfile(root, '.venv', 'bin', 'python');
                if ~isfile(py)
                    tc.assumeFail('fixture missing and no .venv to generate it');
                end
                status = system(sprintf('cd "%s" && "%s" tools/make_nwb_fixture.py "%s"', ...
                    root, py, tc.fixture));
                tc.assumeEqual(status, 0, 'fixture generation failed');
            end
        end
    end

    methods (Test)
        function opensAndHasNwbRoot(tc)
            f = hdmf.zarr.open(tc.fixture);
            tc.verifyEqual(f.root.attrs{"neurodata_type"}, "NWBFile");
            tc.verifyNotEmpty(char(f.root.attrs{"object_id"}));
        end

        function resolveFollowsLinks(tc)
            f = hdmf.zarr.open(tc.fixture);
            % 'device' under shank0 exists only as a link
            dev = f.resolve("general/extracellular_ephys/shank0/device");
            tc.verifyEqual(dev.attrs{"neurodata_type"}, "Device");
            tc.verifyTrue(contains(dev.path, "devices/probe0"));
            % links() surfaces it explicitly
            L = f.links("general/extracellular_ephys/shank0");
            tc.verifyClass(L, 'hdmf.zarr.Link');
            tc.verifyEqual(L(1).Name, "device");
            tc.verifyEqual(L(1).Target.Source, ".");
        end

        function attributeReferenceDereferences(tc)
            f = hdmf.zarr.open(tc.fixture);
            region = f.resolve("acquisition/eseries/electrodes");
            table = f.deref(region.attrs{"table"});
            tc.verifyClass(table, 'zarr.Group');
            tc.verifyTrue(ismember(table.attrs{"neurodata_type"}, ...
                ["DynamicTable", "ElectrodesTable"]));  % renamed in newer NWB schema
            % the region's own data selects rows 0..3
            tc.verifyEqual(region.read(), int64((0:3)'));
        end

        function datasetReferencesDereference(tc)
            f = hdmf.zarr.open(tc.fixture);
            col = f.resolve("general/extracellular_ephys/electrodes/group");
            tc.verifyTrue(hdmf.zarr.isReferenceArray(col));
            groups = f.derefAll(col);
            tc.verifyEqual(numel(groups), 4);
            for i = 1:numel(groups)
                tc.verifyEqual(groups{i}.attrs{"neurodata_type"}, ...
                    "ElectrodeGroup");
            end
        end

        function scalarDatasetReads(tc)
            % hdmf-zarr stores a scalar dataset as a zero-dimensional array
            f = hdmf.zarr.open(tc.fixture);
            description = f.resolve("session_description");
            tc.verifyEqual(description.read(), "hdmf-zarr-matlab conventions fixture");
        end

        function arrayDataReads(tc)
            f = hdmf.zarr.open(tc.fixture);
            es = f.resolve("acquisition/eseries/data");
            expected = single(reshape(0:399, [4 100])' * 0.5);  % C-order fill
            tc.verifyEqual(es.read(), expected);
            tc.verifyEqual(es(2, 3), single((1 * 4 + 2) * 0.5));
        end

        function specificationsCached(tc)
            f = hdmf.zarr.open(tc.fixture);
            tc.verifyNotEqual(f.specLoc(), "");
            spec = f.resolve(f.specLoc());
            tc.verifyClass(spec, 'zarr.Group');
            [~, gn] = spec.children();
            tc.verifyTrue(ismember("core", gn));
        end
    end
end
