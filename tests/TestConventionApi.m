classdef TestConventionApi < matlab.unittest.TestCase
    %TESTCONVENTIONAPI Contract tests for the neutral conventions API.

    methods (Test)
        function referenceFormatsRoundTrip(testCase)
            reference = struct( ...
                "source", ".", ...
                "path", "/general/devices/probe0", ...
                "object_id", "device-id", ...
                "source_object_id", "file-id");

            record = hdmf.zarr.conventions.encodeReference(reference);
            json = hdmf.zarr.conventions.encodeReference(reference, Format="json");
            attribute = hdmf.zarr.conventions.encodeReference(reference, Format="attribute");

            expected = hdmf.zarr.conventions.decodeReference(reference);
            testCase.verifyEqual(hdmf.zarr.conventions.decodeReference(record), expected);
            testCase.verifyEqual(hdmf.zarr.conventions.decodeReference(json), expected);
            testCase.verifyEqual(hdmf.zarr.conventions.decodeReference(attribute), expected);
        end

        function externalReferenceRemainsNeutral(testCase)
            reference = struct( ...
                "source", "../external.nwb.zarr", ...
                "path", "/acquisition/data");

            decoded = hdmf.zarr.conventions.decodeReference(reference);

            testCase.verifyEqual(decoded.source, "../external.nwb.zarr");
            testCase.verifyEqual(decoded.path, "/acquisition/data");
            testCase.verifyEqual(decoded.object_id, "");
        end

        function malformedReferenceThrowsStableError(testCase)
            reference = struct("path", "/acquisition/data");

            testCase.verifyError( ...
                @() hdmf.zarr.conventions.decodeReference(reference), ...
                "hdmf:conventions:InvalidReference");
        end

        function regionReferenceIsExplicitlyUnsupported(testCase)
            reference = struct( ...
                "zarr_dtype", "region", ...
                "value", struct("source", ".", "path", "/acquisition/data"));

            testCase.verifyError( ...
                @() hdmf.zarr.conventions.decodeReference(reference), ...
                "hdmf:conventions:UnsupportedRegionReference");
        end

        function singletonLinkEncodesAsJsonList(testCase)
            link = struct( ...
                "name", "device", ...
                "source", ".", ...
                "path", "/general/devices/probe0");

            attributeValue = hdmf.zarr.conventions.encodeLinks(link);
            json = hdmf.zarr.conventions.encodeLinks(link, Format="json");
            decoded = hdmf.zarr.conventions.decodeLinks(json);

            testCase.verifyClass(attributeValue, "cell");
            testCase.verifyNumElements(attributeValue, 1);
            testCase.verifyTrue(startsWith(json, "["));
            testCase.verifyEqual(decoded.name, "device");
            testCase.verifyEqual(decoded.path, "/general/devices/probe0");
        end

        function externalLinkRoundTrips(testCase)
            link = struct( ...
                "name", "external_data", ...
                "source", "../external.nwb.zarr", ...
                "path", "/acquisition/data", ...
                "object_id", "dataset-id", ...
                "source_object_id", "external-file-id");

            encoded = hdmf.zarr.conventions.encodeLinks(link);
            decoded = hdmf.zarr.conventions.decodeLinks(encoded);

            testCase.verifyEqual(decoded.name, "external_data");
            testCase.verifyEqual(decoded.source, "../external.nwb.zarr");
            testCase.verifyEqual(decoded.object_id, "dataset-id");
        end

        function referenceArrayRequiresTypeAndMarker(testCase)
            objectAttributes = struct("zarr_dtype", "object");
            regionAttributes = struct("zarr_dtype", "region");

            testCase.verifyTrue( ...
                hdmf.zarr.conventions.isReferenceArray("string", objectAttributes));
            testCase.verifyFalse( ...
                hdmf.zarr.conventions.isReferenceArray("float64", objectAttributes));
            testCase.verifyFalse( ...
                hdmf.zarr.conventions.isReferenceArray("string", regionAttributes));
            testCase.verifyFalse( ...
                hdmf.zarr.conventions.isReferenceArray("string", struct()));
        end

        function specLocationUsesExactStorageKey(testCase)
            store = createStore();

            hdmf.zarr.conventions.writeSpecLocation(store, "/specifications");
            [rootBytes, ~] = store.get("zarr.json");
            rootText = string(native2unicode(rootBytes, "UTF-8"));

            testCase.verifySubstring(rootText, '".specloc":"/specifications"');
            testCase.verifyFalse(contains(rootText, '"x_specloc"'));
            testCase.verifyEqual( ...
                hdmf.zarr.conventions.readSpecLocation(store), "/specifications");
        end

        function specLocationSurvivesConsolidationRefresh(testCase)
            store = createStore();
            zarr.create_group(store, Path="first");
            zarr.consolidate_metadata(store);
            hdmf.zarr.conventions.writeSpecLocation(store, "/specifications");
            zarr.create_group(store, Path="second");

            wasRefreshed = hdmf.zarr.conventions.refreshConsolidatedMetadata(store);
            root = zarr.open(store);

            testCase.verifyTrue(wasRefreshed);
            testCase.verifyTrue(root.isKey("second"));
            testCase.verifyEqual( ...
                hdmf.zarr.conventions.readSpecLocation(store), "/specifications");
        end

        function unconsolidatedStoreRemainsUnconsolidated(testCase)
            store = createStore();

            wasRefreshed = hdmf.zarr.conventions.refreshConsolidatedMetadata(store);
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
