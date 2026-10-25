function results = runTests()
%RUNTESTS Run numerical, exported-function, Excel and UI integration checks.
root=fileparts(mfilename('fullpath')); addpath(root);
results=runtests(fullfile(root,'tests'));
disp(table(results));
assert(all([results.Passed]),'APC tests failed. Inspect the failures above.');
end
