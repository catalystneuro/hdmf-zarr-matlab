classdef TestCompound < matlab.unittest.TestCase
    %Compound datasets: the field layout and its reference fields.
    %
    %   Reading is checked against a fixture written by hdmf-zarr itself
    %   (tools/make_compound_fixture.py), so what the conventions layer
    %   claims about the on-disk shape is checked against the shape
    %   hdmf-zarr actually writes. Writing is checked by round-trip here
    %   and, in CI, by hdmf-zarr reading a MATLAB-written store back.

    properties
        fixture
    end

    methods (TestClassSetup)
        function findOrMakeFixture(tc)
            root = fileparts(fileparts(mfilename('fullpath')));
            tc.fixture = fullfile(root, 'scratch', 'fixture.compound.zarr');
            if ~isfolder(tc.fixture)
                py = fullfile(root, '.venv', 'bin', 'python');
                if ~isfile(py)
                    tc.assumeFail('fixture missing and no .venv to generate it');
                end
                status = system(sprintf('cd "%s" && "%s" tools/make_compound_fixture.py "%s"', ...
                    root, py, tc.fixture));
                tc.assumeEqual(status, 0, 'fixture generation failed');
            end
        end
    end

    methods (Test)
        % ------------------------------------------------------------------
        % Reading what hdmf-zarr wrote

        function readsPlainCompound(tc)
            f = hdmf.zarr.open(tc.fixture);
            [records, dtype] = f.readCompound("plain_compound");
            tc.verifyEqual(dtype.Names, ["id", "name"]);
            tc.verifyEqual(dtype.isReferenceField(), [false false]);
            tc.verifyEqual([records.id], int32([1 2 3]));
            tc.verifyEqual([records.name], ["Allen", "Bob", "Mike"]);
        end

        function readsReferenceFieldsAsReferences(tc)
            f = hdmf.zarr.open(tc.fixture);
            [records, dtype] = f.readCompound("ref_compound");
            tc.verifyEqual(dtype.Types, ["int32", "str_", "object"]);
            tc.verifyEqual(dtype.isReferenceField(), [false false true]);
            tc.verifyClass(records(1).reference, 'hdmf.zarr.Reference');
            tc.verifyEqual([records.name], ["dataset_1", "dataset_2"]);
            tc.verifyEqual(records(1).reference.Path, "/dataset_1");
            tc.verifyEqual(records(2).reference.Path, "/dataset_2");
        end

        function referenceFieldDereferences(tc)
            f = hdmf.zarr.open(tc.fixture);
            records = f.readCompound("ref_compound");
            targets = f.derefAll([records.reference]);
            tc.verifyEqual(size(targets{1}), [2 5]);
            tc.verifyEqual(size(targets{2}), [4 5]);
            % numpy's arange gives the fixture int64 data; the point here
            % is which array the reference reached, not its element type.
            values = double(targets{2}.read());
            tc.verifyEqual(values(1, :), 0:10:40);
        end

        function readCompoundRejectsNonCompound(tc)
            f = hdmf.zarr.open(tc.fixture);
            tc.verifyFalse(hdmf.zarr.isCompoundDataset(f.resolve("dataset_1")));
            tc.verifyError(@() f.readCompound("dataset_1"), "hdmf:NotCompoundDataset");
        end

        function predicatesTellCompoundFromReferenceDataset(tc)
            % Both hold references stored as text; only the compound one
            % has a record data type.
            f = hdmf.zarr.open(tc.fixture);
            compound = f.resolve("ref_compound");
            tc.verifyTrue(hdmf.zarr.isCompoundDataset(compound));
            tc.verifyFalse(hdmf.zarr.isReferenceArray(compound));
        end

        % ------------------------------------------------------------------
        % Writing, and reading back what we wrote

        function writeCompoundRoundTrips(tc)
            f = tc.newStore();
            records = struct( ...
                'id', {int32(1); int32(2)}, ...
                'weight', {1.5; -2.25}, ...
                'label', {"alpha"; "beta"}, ...
                'device', {f.makeReference("devices/probe0"); f.makeReference("devices/probe1")});
            f.writeCompound("table", records);

            [back, dtype] = f.readCompound("table");
            tc.verifyEqual(dtype.Types, ["int32", "float64", "str_", "object"]);
            tc.verifyEqual([back.id], int32([1 2]));
            tc.verifyEqual([back.weight], [1.5 -2.25]);
            tc.verifyEqual([back.label], ["alpha", "beta"]);
            tc.verifyEqual(back(2).device.Path, "/devices/probe1");
        end

        function writeCompoundAcceptsPathsAsReferences(tc)
            % A reference field given as paths needs a declared layout:
            % text and references are indistinguishable in the data.
            f = tc.newStore();
            records = struct('id', {int32(1); int32(2)}, ...
                'device', {"devices/probe0"; "devices/probe1"});
            dtype = hdmf.zarr.CompoundDtype(["id", "device"], ["int32", "object"]);
            f.writeCompound("table", records, Dtype=dtype);

            back = f.readCompound("table");
            tc.verifyClass(back(1).device, 'hdmf.zarr.Reference');
            tc.verifyEqual(back(1).device.Path, "/devices/probe0");
        end

        function writeCompoundStoresSpecShapedMetadata(tc)
            f = tc.newStore();
            records = struct('id', {int32(7)}, 'device', {f.makeReference("devices/probe0")});
            node = f.writeCompound("table", records);

            % _REFERENCE_FIELDS is a LIST of field names even for one
            % field, and reference fields are stored as ordinary
            % fixed-length text holding the target path.
            txt = fileread(fullfile(node.store.root, "table", "zarr.json"));
            tc.verifySubstring(txt, '"_REFERENCE_FIELDS":["device"]');
            tc.verifyFalse(contains(txt, "zarr_dtype"));
            meta = jsondecode(txt);
            tc.verifyEqual(string(meta.data_type.name), "struct");
            tc.verifyEqual(string(meta.data_type.configuration.fields(2).data_type.name), ...
                "fixed_length_utf32");
            tc.verifyEqual(node.read().device, "/devices/probe0");
        end

        function writeCompoundWithoutReferencesOmitsReferenceFields(tc)
            % as hdmf-zarr writes a compound that holds no references
            f = tc.newStore();
            node = f.writeCompound("table", struct('id', {int32(1)}, 'label', {"a"}));
            tc.verifyFalse(isKey(node.attrs, "_REFERENCE_FIELDS"));
            [~, dtype] = f.readCompound("table");
            tc.verifyEqual(dtype.isReferenceField(), [false false]);
        end

        function writeCompoundSizesTextToFitWithHeadroom(tc)
            % Fields are never narrower than hdmf-zarr's minimum, and widen
            % to fit a value longer than it.
            f = tc.newStore();
            long = string(repmat('x', 1, 700));
            records = struct('label', {"short"; long});
            node = f.writeCompound("table", records);

            meta = jsondecode(fileread(fullfile(node.store.root, "table", "zarr.json")));
            tc.verifyEqual(meta.data_type.configuration.fields(1).data_type.configuration.length_bytes, ...
                4 * 700);
            back = f.readCompound("table");
            tc.verifyEqual(back(2).label, long);
        end

        function writeCompoundWidensDeclaredCapacityToFit(tc)
            % A fixed-length field cannot hold a value longer than its
            % capacity, so a declared capacity is a minimum.
            f = tc.newStore();
            long = string(repmat('x', 1, 700));
            dtype = hdmf.zarr.CompoundDtype("label", "str_");
            node = f.writeCompound("table", struct('label', {"short"; long}), Dtype=dtype);

            tc.verifyEqual(textFieldChars(node, 1), 700);
            back = f.readCompound("table");
            tc.verifyEqual(back(2).label, long);
        end

        function writeCompoundKeepsDeclaredCapacityThatFits(tc)
            % Narrower than hdmf-zarr's minimum, but declared and
            % sufficient, so it is written as declared.
            f = tc.newStore();
            dtype = hdmf.zarr.CompoundDtype("label", "str_", StringChars=64);
            node = f.writeCompound("table", struct('label', {"short"}), Dtype=dtype);
            tc.verifyEqual(textFieldChars(node, 1), 64);
        end

        function writeCompoundSizesPathReferencesByStoredPath(tc)
            % A reference given as a relative path occupies the absolute
            % path it becomes, which is one character longer.
            f = tc.newStore();
            path = "devices/probe0";
            dtype = hdmf.zarr.CompoundDtype("device", "object", StringChars=strlength(path));
            node = f.writeCompound("table", struct('device', {path}), Dtype=dtype);

            tc.verifyEqual(textFieldChars(node, 1), strlength("/" + path));
            back = f.readCompound("table");
            tc.verifyEqual(back.device.Path, "/devices/probe0");
        end

        function writeCompoundRejectsUndeclaredField(tc)
            f = tc.newStore();
            records = struct('id', {int32(1)});
            dtype = hdmf.zarr.CompoundDtype(["id", "missing"], ["int32", "int32"]);
            tc.verifyError(@() f.writeCompound("table", records, Dtype=dtype), ...
                "hdmf:InvalidCompoundData");
        end

        function writeCompoundRejectsEmptyData(tc)
            f = tc.newStore();
            tc.verifyError(@() f.writeCompound("table", struct('id', {})), ...
                "hdmf:InvalidCompoundData");
        end

        function writeCompoundAcceptsDictionaryAttributes(tc)
            % Attributes read from a store arrive as a dictionary, so one
            % can be handed straight back.
            f = tc.newStore();
            attributes = dictionary(string.empty, {});
            attributes("neurodata_type") = {"DynamicTable"};
            node = f.writeCompound("table", struct('id', {int32(1)}), Attributes=attributes);
            tc.verifyEqual(node.attrs{"neurodata_type"}, "DynamicTable");
        end

        function writeCompoundAddsReferenceFieldsToStructAttributes(tc)
            f = tc.newStore();
            records = struct('device', {f.makeReference("devices/probe0")});
            f.writeCompound("table", records, ...
                Attributes=struct('neurodata_type', 'DynamicTable'));
            node = f.resolve("table");
            tc.verifyEqual(node.attrs{"neurodata_type"}, "DynamicTable");
            tc.verifyEqual(node.attrs{"_REFERENCE_FIELDS"}, {"device"});
        end

        function readCompoundRejectsUnknownReferenceField(tc)
            f = tc.newStore();
            attributes = dictionary(string.empty, {});
            attributes("_REFERENCE_FIELDS") = {{'nope'}};
            f.writeCompound("table", struct('id', {int32(1)}), Attributes=attributes);
            tc.verifyError(@() f.readCompound("table"), "hdmf:InvalidCompoundDtype");
        end

        % ------------------------------------------------------------------
        % Reading what hdmf-zarr wrote before 0.14

        function readsLegacyCompound(tc)
            % per-field types in a zarr_dtype list, references as JSON text
            f = tc.newStore();
            dtype = hdmf.zarr.CompoundDtype(["id", "device"], ["int32", "object"]);
            legacyTypes = {struct('name', 'id', 'dtype', 'int32'), ...
                struct('name', 'device', 'dtype', 'object')};
            node = zarr.create(f.store, 2, dtype.encodeDataType(), Path="legacy", ...
                Attributes=struct('zarr_dtype', {legacyTypes}));
            node.write(struct('id', {int32(1); int32(2)}, 'device', ...
                {"{""source"":""."",""path"":""/devices/probe0"",""object_id"":""p0""}"; ...
                 "{""source"":""."",""path"":""/devices/probe1""}"}));
            f.refresh();

            [records, readDtype] = f.readCompound("legacy");
            tc.verifyEqual(readDtype.Types, ["int32", "object"]);
            devices = [records.device];
            tc.verifyEqual([devices.Path], ["/devices/probe0", "/devices/probe1"]);
            tc.verifyEqual(records(1).device.ObjectId, "p0");
        end

        % ------------------------------------------------------------------
        % CompoundDtype on its own

        function dtypeDecodesAttributeList(tc)
            value = {struct('name', 'id', 'dtype', 'int32'), ...
                     struct('name', 'ref', 'dtype', 'object')};
            dtype = hdmf.zarr.CompoundDtype.decode(value);
            tc.verifyEqual(dtype.Names, ["id", "ref"]);
            tc.verifyEqual(dtype.isReferenceField(), [false true]);
        end

        function dtypeDecodesStructArrayForm(tc)
            % A struct array is what a MATLAB caller builds when every
            % record has the same fields.
            value = struct('name', {'id'; 'name'}, 'dtype', {'int32'; 'str_'});
            dtype = hdmf.zarr.CompoundDtype.decode(value);
            tc.verifyEqual(dtype.Names, ["id", "name"]);
        end

        function dtypeDecodesDictionaryList(tc)
            % Read from a store, zarr_dtype is a cell of dictionaries: how
            % zarr-matlab returns a JSON list of objects.
            value = {recordDictionary("id", "int32"); recordDictionary("ref", "object")};
            dtype = hdmf.zarr.CompoundDtype.decode(value);
            tc.verifyEqual(dtype.Names, ["id", "ref"]);
            tc.verifyEqual(dtype.isReferenceField(), [false true]);
        end

        function dtypeRejectsPlainReferenceDtype(tc)
            % What a (non-compound) reference dataset carries instead.
            tc.verifyError(@() hdmf.zarr.CompoundDtype.decode('object'), ...
                "hdmf:InvalidCompoundDtype");
        end

        function dtypeRejectsMismatchedLengths(tc)
            tc.verifyError(@() hdmf.zarr.CompoundDtype(["a", "b"], "int32"), ...
                "hdmf:InvalidCompoundDtype");
        end

        function dtypeEncodesReferenceFieldsAsList(tc)
            dtype = hdmf.zarr.CompoundDtype(["id", "ref"], ["int32", "object"]);
            value = dtype.encodeReferenceFields();
            tc.verifyClass(value, 'cell');
            tc.verifyEqual(string(jsonencode(value)), "[""ref""]");
        end

        function dtypeSizesReferenceFieldsByPath(tc)
            % A reference is stored, and measured, as its target path.
            longPath = "/" + string(repmat('d', 1, 600));
            records = struct('ref', {hdmf.zarr.Reference(longPath)});
            dtype = hdmf.zarr.CompoundDtype.fromData(records);
            tc.verifyEqual(dtype.Types, "object");
            tc.verifyEqual(dtype.StringChars, 601);
        end

        function dtypeWidensOnlyFieldsThatNeedRoom(tc)
            dtype = hdmf.zarr.CompoundDtype(["id", "label", "note"], ...
                ["int32", "str_", "str_"], StringChars=4);
            records = struct('id', {int32(1)}, 'label', {"abcdefgh"}, 'note', {"ab"});
            widened = dtype.widenToFit(records);
            tc.verifyEqual(widened.StringChars, [4 8 4]);
        end

        function dtypeWidenRejectsDataWithoutDeclaredField(tc)
            dtype = hdmf.zarr.CompoundDtype(["id", "label"], ["int32", "str_"]);
            tc.verifyError(@() dtype.widenToFit(struct('id', {int32(1)})), ...
                "hdmf:InvalidCompoundData");
        end

        function dtypeRejectsUnsupportedFieldClass(tc)
            records = struct('bad', {{1, 2}});
            tc.verifyError(@() hdmf.zarr.CompoundDtype.fromData(records), ...
                "hdmf:InvalidCompoundDtype");
        end
    end

    methods (Access = private)
        function f = newStore(tc)
        %newStore - An empty store with two referenceable target groups

            import matlab.unittest.fixtures.TemporaryFolderFixture
            tempFixture = tc.applyFixture(TemporaryFolderFixture);
            store = zarr.stores.LocalStore(fullfile(tempFixture.Folder, "store.zarr"));
            zarr.create_group(store);
            zarr.create_group(store, Path="devices/probe0");
            zarr.create_group(store, Path="devices/probe1");
            f = hdmf.zarr.open(store);
        end
    end
end

function d = recordDictionary(name, type)
%recordDictionary - A {name, dtype} record in the form a store returns it

d = dictionary(string.empty, {});
d("name") = {name};
d("dtype") = {type};
end

function chars = textFieldChars(node, fieldIndex)
%textFieldChars - Capacity, in characters, a written dataset gives a text field
%   Read from the dataset's own zarr.json: the array's data_type, not the
%   layout it was created from, governs what a field can hold.

meta = jsondecode(fileread(fullfile(node.store.root, node.path, "zarr.json")));
lengthBytes = meta.data_type.configuration.fields(fieldIndex).data_type.configuration.length_bytes;
bytesPerChar = 4;   % fixed_length_utf32
chars = lengthBytes / bytesPerChar;
end
