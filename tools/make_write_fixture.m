function make_write_fixture(outDir)
%MAKE_WRITE_FIXTURE MATLAB-written conventions store for python validation.

if isfolder(outDir), rmdir(outDir, 's'); end
store = zarr.stores.LocalStore(outDir);
zarr.create_group(store, Attributes=struct('object_id', 'root-oid-1'));
zarr.create_group(store, Path="general/devices/probe0", ...
    Attributes=struct('object_id', 'dev-oid-1', 'neurodata_type', 'Device'));
z = zarr.create(store, [4 3], "float64", Path="acquisition/ts/data", ChunkShape=[2 3]);
z.write(reshape(1:12, [4 3]));

f = hdmf.zarr.open(store);
f.addLink("acquisition", "device", "general/devices/probe0");
f.writeRefs("acquisition/ts/refs", ["general/devices/probe0", "acquisition/ts/data"]);
f.setRefAttr("acquisition/ts/data", "table", "general/devices/probe0");
rows = struct( ...
    'id', {int32(1); int32(2)}, ...
    'name', {"probe0"; "series"}, ...
    'reference', {f.makeReference("general/devices/probe0"); ...
                  f.makeReference("acquisition/ts/data")});
f.writeCompound("acquisition/ts/compound", rows);
zarr.consolidate_metadata(store);
fprintf('write fixture at %s\n', outDir);
end
