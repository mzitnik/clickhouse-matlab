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
        SchemaMixed
        SchemaNumeric
    end

    properties (TestParameter)
        NumRows = struct('rows_1k', 1e3, 'rows_10k', 1e4, 'rows_100k', 1e5, 'rows_1m', 1e6);
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
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_perf.insert_numeric (" ...
                "  c_int64 Int64, c_int32 Int32, c_float64 Float64, c_float32 Float32" ...
                ") ENGINE = Memory"]);
            % Cache schemas for the *WithSchema variants — measures the
            % insert path without the per-call DESCRIBE round-trip.
            tc.SchemaMixed   = tc.Client.describe("ch_matlab_perf.insert_perf");
            tc.SchemaNumeric = tc.Client.describe("ch_matlab_perf.insert_numeric");
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_perf.insert_perf");
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_perf.insert_numeric");
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

        function insertMixedWithSchema(tc, NumRows)
            % Same as insertMixed but passes the cached schema, isolating
            % the cost of the per-insert DESCRIBE round-trip.
            n = NumRows;
            data = table( ...
                int64((1:n)'), ...
                rand(n, 1), ...
                repmat("row_text", n, 1), ...
                'VariableNames', {'c_int64', 'c_float64', 'c_string'});
            tc.Client.query("TRUNCATE TABLE ch_matlab_perf.insert_perf");

            startMeasuring(tc);
            tc.Client.insert("ch_matlab_perf.insert_perf", data, tc.SchemaMixed);
            stopMeasuring(tc);
        end

        function insertNumeric(tc, NumRows)
            % Pure numeric — exercises the memcpy fast paths for the four
            % type-matched widths (Int64, Int32, Float64, Float32) without
            % any String/Array overhead.
            n = NumRows;
            data = table( ...
                int64((1:n)'),        ...
                int32((1:n)'),        ...
                rand(n, 1),           ...
                single(rand(n, 1)),   ...
                'VariableNames', {'c_int64', 'c_int32', 'c_float64', 'c_float32'});
            tc.Client.query("TRUNCATE TABLE ch_matlab_perf.insert_numeric");

            startMeasuring(tc);
            tc.Client.insert("ch_matlab_perf.insert_numeric", data);
            stopMeasuring(tc);
        end

        function insertNumericWithSchema(tc, NumRows)
            % Same as insertNumeric but passes the cached schema.
            n = NumRows;
            data = table( ...
                int64((1:n)'),        ...
                int32((1:n)'),        ...
                rand(n, 1),           ...
                single(rand(n, 1)),   ...
                'VariableNames', {'c_int64', 'c_int32', 'c_float64', 'c_float32'});
            tc.Client.query("TRUNCATE TABLE ch_matlab_perf.insert_numeric");

            startMeasuring(tc);
            tc.Client.insert("ch_matlab_perf.insert_numeric", data, tc.SchemaNumeric);
            stopMeasuring(tc);
        end
    end
end
