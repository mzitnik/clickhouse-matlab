% perf/TestInsertPerf.m
classdef TestInsertPerf < matlab.perftest.TestCase
    % Run with: runperf('TestInsertPerf')
    %
    % Each Test method is measured by the perftest framework: warm-up runs
    % are taken automatically, then samples are collected until the variance
    % criterion is met. Only the region between startMeasuring/stopMeasuring
    % is timed — data generation and TRUNCATE are excluded.

    properties
        Clients        % containers.Map: int32 compression code -> ClickHouseClient
        SchemaMixed
        SchemaNumeric
    end

    properties (TestParameter)
        NumRows = struct('rows_1k', 1e3, 'rows_10k', 1e4, 'rows_100k', 1e5, 'rows_1m', 1e6);
        Comp = struct('none', Compression.None, 'lz4', Compression.LZ4, 'zstd', Compression.ZSTD);
    end

    methods (TestClassSetup)
        function setupClass(tc)
            % Keep in sync with the Comp TestParameter above.
            methodsToTest = [Compression.None, Compression.LZ4, Compression.ZSTD];
            tc.Clients = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            for m = methodsToTest
                opts = struct('maxRetries', 0, 'compression', m);
                tc.Clients(int32(m)) = ClickHouseClient("localhost", 9000, "default", "", opts);
            end
            c = tc.Clients(int32(Compression.None));   % any client for DDL
            c.query("CREATE DATABASE IF NOT EXISTS ch_matlab_perf");
            % Memory engine: no disk I/O, no merges, no server-side compression
            % — isolates the driver path. Block compression here is on the wire,
            % independent of the storage engine.
            c.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_perf.insert_perf (" ...
                "  c_int64 Int64, c_float64 Float64, c_string String" ...
                ") ENGINE = Memory"]);
            c.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_perf.insert_numeric (" ...
                "  c_int64 Int64, c_int32 Int32, c_float64 Float64, c_float32 Float32" ...
                ") ENGINE = Memory"]);
            % Cache schemas for the *WithSchema variants — measures the
            % insert path without the per-call DESCRIBE round-trip.
            tc.SchemaMixed   = c.describe("ch_matlab_perf.insert_perf");
            tc.SchemaNumeric = c.describe("ch_matlab_perf.insert_numeric");
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            % Guard the DROP so a partial setup (e.g. a client failing to
            % connect mid-loop) still reaches the delete loop and closes the
            % clients that did open.
            key = int32(Compression.None);
            if isKey(tc.Clients, key)
                c = tc.Clients(key);
                c.query("DROP TABLE IF EXISTS ch_matlab_perf.insert_perf");
                c.query("DROP TABLE IF EXISTS ch_matlab_perf.insert_numeric");
            end
            ks = tc.Clients.keys;
            for i = 1:numel(ks)
                delete(tc.Clients(ks{i}));
            end
        end
    end

    methods (Test)
        function insertMixed(tc, NumRows, Comp)
            client = tc.Clients(int32(Comp));
            n = NumRows;
            data = table( ...
                int64((1:n)'), ...
                rand(n, 1), ...
                repmat("row_text", n, 1), ...
                'VariableNames', {'c_int64', 'c_float64', 'c_string'});
            client.query("TRUNCATE TABLE ch_matlab_perf.insert_perf");

            startMeasuring(tc);
            client.insert("ch_matlab_perf.insert_perf", data);
            stopMeasuring(tc);
        end

        function insertMixedWithSchema(tc, NumRows, Comp)
            % Same as insertMixed but passes the cached schema, isolating
            % the cost of the per-insert DESCRIBE round-trip.
            client = tc.Clients(int32(Comp));
            n = NumRows;
            data = table( ...
                int64((1:n)'), ...
                rand(n, 1), ...
                repmat("row_text", n, 1), ...
                'VariableNames', {'c_int64', 'c_float64', 'c_string'});
            client.query("TRUNCATE TABLE ch_matlab_perf.insert_perf");

            startMeasuring(tc);
            client.insert("ch_matlab_perf.insert_perf", data, tc.SchemaMixed);
            stopMeasuring(tc);
        end

        function insertNumeric(tc, NumRows, Comp)
            % Pure numeric — exercises the memcpy fast paths for the four
            % type-matched widths (Int64, Int32, Float64, Float32) without
            % any String/Array overhead.
            client = tc.Clients(int32(Comp));
            n = NumRows;
            data = table( ...
                int64((1:n)'),        ...
                int32((1:n)'),        ...
                rand(n, 1),           ...
                single(rand(n, 1)),   ...
                'VariableNames', {'c_int64', 'c_int32', 'c_float64', 'c_float32'});
            client.query("TRUNCATE TABLE ch_matlab_perf.insert_numeric");

            startMeasuring(tc);
            client.insert("ch_matlab_perf.insert_numeric", data);
            stopMeasuring(tc);
        end

        function insertNumericWithSchema(tc, NumRows, Comp)
            % Same as insertNumeric but passes the cached schema.
            client = tc.Clients(int32(Comp));
            n = NumRows;
            data = table( ...
                int64((1:n)'),        ...
                int32((1:n)'),        ...
                rand(n, 1),           ...
                single(rand(n, 1)),   ...
                'VariableNames', {'c_int64', 'c_int32', 'c_float64', 'c_float32'});
            client.query("TRUNCATE TABLE ch_matlab_perf.insert_numeric");

            startMeasuring(tc);
            client.insert("ch_matlab_perf.insert_numeric", data, tc.SchemaNumeric);
            stopMeasuring(tc);
        end
    end
end
