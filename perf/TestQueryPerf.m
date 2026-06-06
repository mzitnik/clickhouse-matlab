% perf/TestQueryPerf.m
classdef TestQueryPerf < matlab.perftest.TestCase
    % Run with: runperf('TestQueryPerf')
    %
    % The table is populated once in TestClassSetup using INSERT ... SELECT,
    % so driver insert overhead is not on the critical path. Each Test method
    % times only the query call via startMeasuring/stopMeasuring.

    properties
        Clients   % containers.Map: int32 compression code -> ClickHouseClient
    end

    properties (Constant)
        TableName = "ch_matlab_perf.query_perf"
        NumRowsPopulated = 1e5
    end

    properties (TestParameter)
        Limit = struct('rows_1k', 1e3, 'rows_10k', 1e4, 'rows_100k', 1e5);
        Comp  = struct('none', Compression.None, 'lz4', Compression.LZ4, 'zstd', Compression.ZSTD);
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
            c = tc.Clients(int32(Compression.None));
            c.query("CREATE DATABASE IF NOT EXISTS ch_matlab_perf");
            % Memory engine: isolates the driver path; block compression is on
            % the wire, independent of the storage engine.
            c.query([ ...
                "CREATE TABLE IF NOT EXISTS " + tc.TableName + " (" ...
                "  c_int64 Int64, c_float64 Float64, c_string String" ...
                ") ENGINE = Memory"]);
            c.query("TRUNCATE TABLE " + tc.TableName);
            % Server-side populate avoids driver insert overhead during setup.
            c.query(sprintf( ...
                "INSERT INTO %s SELECT number, randCanonical(), 'row_text' FROM numbers(%d)", ...
                tc.TableName, tc.NumRowsPopulated));
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            % Guard the DROP so a partial setup still reaches the delete loop
            % and closes the clients that did open.
            key = int32(Compression.None);
            if isKey(tc.Clients, key)
                tc.Clients(key).query("DROP TABLE IF EXISTS " + tc.TableName);
            end
            ks = tc.Clients.keys;
            for i = 1:numel(ks)
                delete(tc.Clients(ks{i}));
            end
        end
    end

    methods (Test)
        function querySelect(tc, Limit, Comp)
            client = tc.Clients(int32(Comp));
            sql = sprintf("SELECT c_int64, c_float64, c_string FROM %s ORDER BY c_int64 LIMIT %d", ...
                tc.TableName, Limit);
            startMeasuring(tc);
            r = client.query(sql); %#ok<NASGU>
            stopMeasuring(tc);
        end
    end
end
