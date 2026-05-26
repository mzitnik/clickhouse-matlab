% test/TestVersion.m
classdef TestVersion < matlab.unittest.TestCase
    % TestVersion  Verifies that the compile-time CLICKHOUSE_MATLAB_VERSION
    % macro embedded in the MEX matches the contents of version.txt at the
    % repo root. Constructs a client against localhost:9000 (same convention
    % as the rest of the test suite).

    methods (Test)
        function testVersionMatchesFile(tc)
            test_dir = fileparts(mfilename('fullpath'));
            repo_root = fileparts(test_dir);
            expected = string(strtrim(fileread(fullfile(repo_root, 'version.txt'))));

            client = ClickHouseClient("localhost", 9000, "default", "");
            cleaner = onCleanup(@() delete(client)); %#ok<NASGU>
            actual = client.version();

            tc.verifyEqual(actual, expected, ...
                'Compiled-in version does not match version.txt');
        end
    end
end
