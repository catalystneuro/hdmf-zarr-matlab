function run_tests()
%RUN_TESTS Run the hdmf-zarr-matlab suite (zarr-matlab must be available:
%   sibling checkout or ZARR_MATLAB_PATH).

root = fileparts(fileparts(mfilename('fullpath')));
zm = string(getenv('ZARR_MATLAB_PATH'));
if strlength(zm) == 0
    zm = fullfile(fileparts(root), 'zarr-matlab');
end
if ~isfolder(fullfile(zm, '+zarr'))
    error("hdmf:Setup", ...
        "zarr-matlab not found at '%s'. Clone it as a sibling or set ZARR_MATLAB_PATH.", zm);
end
addpath(char(zm), root, fullfile(root, 'tools'));

results = runtests(fullfile(root, 'tests'));
disp(table(results));
if any([results.Failed])
    error("hdmf:TestsFailed", "%d test(s) failed.", nnz([results.Failed]));
end
fprintf('%d passed, %d skipped\n', nnz([results.Passed]), ...
    nnz([results.Incomplete] & ~[results.Failed]));
end
