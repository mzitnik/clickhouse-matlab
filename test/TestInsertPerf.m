% test/TestInsertPerf.m
classdef TestInsertPerf < matlab.perftest.TestCase
    % Run with: runperf('TestInsertPerf')
    %
    % Each Test method is measured by the perftest framework: warm-up runs
    % are taken automatically, then samples are collected until the variance
    % criterion is met. Only the region between startMeasuring/stopMeasuring
    % is timed — data generation and TRUNCATE are excluded.

    properties
        Client
    end

    properties (TestParameter)
        NumRows = struct('rows_1k', 1e3, 'rows_10k', 1e4, 'rows_100k', 1e5);
    end

    methods (TestClassSetup)
        function setupClass(tc)
            opts = struct('maxRetries', 0);
            tc.Client = ClickHouseClient("localhost", 9000, "default", "", opts);
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_perf");
            % Memory engine: no disk I/O, no background merges, no compression
            % — isolates the driver path from server-side storage variance.
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_perf.insert_perf (" ...
                "  c_int64 Int64, c_float64 Float64, c_string String" ...
                ") ENGINE = Memory"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_perf.insert_perf");
            delete(tc.Client);
        end
    end

    methods (Test)
        function insertMixed(tc, NumRows)
            n = NumRows;
            data = table( ...
                int64((1:n)'), ...
                rand(n, 1), ...
                repmat("row_text", n, 1), ...
                'VariableNames', {'c_int64', 'c_float64', 'c_string'});
            tc.Client.query("TRUNCATE TABLE ch_matlab_perf.insert_perf");

            startMeasuring(tc);
            tc.Client.insert("ch_matlab_perf.insert_perf", data);
            stopMeasuring(tc);
        end
    end
end
