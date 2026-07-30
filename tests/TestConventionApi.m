classdef TestConventionApi < matlab.unittest.TestCase
    %TESTCONVENTIONAPI Contract tests for the public HDMF-Zarr API.

    methods (Test)
        function referenceFormatsRoundTrip(testCase)
            reference = struct( ...
                "source", ".", ...
                "path", "/general/devices/probe0", ...
                "object_id", "device-id", ...
                "source_object_id", "file-id");

            record = hdmf.zarr.encodeReference(reference);
            json = hdmf.zarr.encodeReference(reference, Format="json");
            attribute = hdmf.zarr.encodeReference(reference, Format="attribute");

            expected = hdmf.zarr.decodeReference(reference);
            testCase.verifyEqual(hdmf.zarr.decodeReference(record), expected);
            testCase.verifyEqual(hdmf.zarr.decodeReference(json), expected);
            testCase.verifyEqual(hdmf.zarr.decodeReference(attribute), expected);
        end

        function externalReferenceRemainsNeutral(testCase)
            reference = struct( ...
                "source", "../external.nwb.zarr", ...
                "path", "/acquisition/data");

            decoded = hdmf.zarr.decodeReference(reference);

            testCase.verifyEqual(decoded.source, "../external.nwb.zarr");
            testCase.verifyEqual(decoded.path, "/acquisition/data");
            testCase.verifyEqual(decoded.object_id, "");
        end

        function malformedReferenceThrowsStableError(testCase)
            reference = struct("path", "/acquisition/data");

            testCase.verifyError( ...
                @() hdmf.zarr.decodeReference(reference), ...
                "hdmf:conventions:InvalidReference");
        end

        function regionReferenceIsExplicitlyUnsupported(testCase)
            reference = struct( ...
                "zarr_dtype", "region", ...
                "value", struct("source", ".", "path", "/acquisition/data"));

            testCase.verifyError( ...
                @() hdmf.zarr.decodeReference(reference), ...
                "hdmf:conventions:UnsupportedRegionReference");
        end

        function fileWritesSingletonLinkAsJsonList(testCase)
            [file, store] = createFile();

            file.addLink("links", "device", "target");
            links = file.links("links");
            [bytes, ~] = store.get("links/zarr.json");
            json = string(native2unicode(bytes, "UTF-8"));

            testCase.verifyEqual(links.name, "device");
            testCase.verifyEqual(links.path, "/target");
            testCase.verifySubstring(json, '"zarr_link":[{');
        end

        function fileWritesExternalLinks(testCase)
            [file, ~] = createFile();
            link = struct( ...
                "name", "external_data", ...
                "source", "../external.nwb.zarr", ...
                "path", "/acquisition/data", ...
                "object_id", "dataset-id", ...
                "source_object_id", "external-file-id");

            file.writeLinks("links", link);
            decoded = file.links("links");

            testCase.verifyEqual(decoded.name, "external_data");
            testCase.verifyEqual(decoded.source, "../external.nwb.zarr");
            testCase.verifyEqual(decoded.object_id, "dataset-id");
        end

        function fileIdentifiesReferenceArrays(testCase)
            [file, store] = createFile();
            objectArray = zarr.create(store, 1, "string", Path="object");
            objectArray.setAttr("zarr_dtype", "object");
            numericArray = zarr.create(store, 1, "float64", Path="numeric");
            numericArray.setAttr("zarr_dtype", "object");
            regionArray = zarr.create(store, 1, "string", Path="region");
            regionArray.setAttr("zarr_dtype", "region");
            stringArray = zarr.create(store, 1, "string", Path="string");

            testCase.verifyTrue(file.isRefArray(objectArray));
            testCase.verifyFalse(file.isRefArray(numericArray));
            testCase.verifyFalse(file.isRefArray(regionArray));
            testCase.verifyFalse(file.isRefArray(stringArray));
        end

        function fileWritesSpecLocationWithExactStorageKey(testCase)
            store = createStore();
            file = hdmf.zarr.open(store);

            file.setSpecLoc("/specifications");
            [rootBytes, ~] = store.get("zarr.json");
            rootText = string(native2unicode(rootBytes, "UTF-8"));

            testCase.verifySubstring(rootText, '".specloc":"/specifications"');
            testCase.verifyFalse(contains(rootText, '"x_specloc"'));
            testCase.verifyEqual(file.specLoc(), "/specifications");
        end

        function fileRefreshPreservesSpecLocation(testCase)
            store = createStore();
            zarr.create_group(store, Path="first");
            zarr.consolidate_metadata(store);
            file = hdmf.zarr.open(store);
            file.setSpecLoc("/specifications");
            zarr.create_group(store, Path="second");

            wasRefreshed = file.refresh();

            testCase.verifyTrue(wasRefreshed);
            testCase.verifyTrue(file.root.isKey("second"));
            testCase.verifyEqual(file.specLoc(), "/specifications");
        end

        function fileRefreshLeavesUnconsolidatedStoreUnconsolidated(testCase)
            store = createStore();
            file = hdmf.zarr.open(store);

            wasRefreshed = file.refresh();
            [rootBytes, ~] = store.get("zarr.json");
            rootText = string(native2unicode(rootBytes, "UTF-8"));

            testCase.verifyFalse(wasRefreshed);
            testCase.verifyFalse(contains(rootText, '"consolidated_metadata"'));
        end

        function fileFacadeUsesSpecLocationApi(testCase)
            store = createStore();
            file = hdmf.zarr.open(store);

            file.setSpecLoc("/specifications");

            testCase.verifyEqual(file.specLoc(), "/specifications");
        end
    end
end

function store = createStore()
    store = zarr.stores.MemoryStore();
    zarr.create_group(store, Attributes=struct("object_id", "file-id"));
end

function [file, store] = createFile()
    store = createStore();
    zarr.create_group(store, Path="links");
    zarr.create_group(store, Path="target");
    file = hdmf.zarr.open(store);
end
