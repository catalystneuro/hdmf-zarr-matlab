function make_write_fixture(outDir)
%MAKE_WRITE_FIXTURE MATLAB-written conventions store for python validation.

if isfolder(outDir), rmdir(outDir, 's'); end
store = zarr.stores.LocalStore(outDir);
zarr.create_group(store, Attributes=struct('object_id', 'root-oid-1'));
zarr.create_group(store, Path="general/devices/probe0", ...
    Attributes=struct('object_id', 'dev-oid-1', 'neurodata_type', 'Device'));
zarr.create_group(store, Path="specifications");
z = zarr.create(store, [4 3], "float64", Path="acquisition/ts/data", ChunkShape=[2 3]);
z.write(reshape(1:12, [4 3]));

f = hdmf.zarr.open(store);
f.setSpecLoc("/specifications");
f.addLink("acquisition", "device", "general/devices/probe0");
f.writeRefs("acquisition/ts/refs", ["general/devices/probe0", "acquisition/ts/data"]);
f.setRefAttr("acquisition/ts/data", "table", "general/devices/probe0");

acquisition = f.resolve("acquisition");
links = hdmf.zarr.conventions.decodeLinks(acquisition.attrs.zarr_link);
externalLink = struct( ...
    "name", "external_data", ...
    "source", "../external.nwb.zarr", ...
    "path", "/acquisition/data", ...
    "object_id", "", ...
    "source_object_id", "");
acquisition.setAttr("zarr_link", ...
    hdmf.zarr.conventions.encodeLinks([links, externalLink]));
zarr.consolidate_metadata(store);
hdmf.zarr.conventions.writeSpecLocation(store, "/specifications");
fprintf('write fixture at %s\n', outDir);
end
