% test/TestQueryPerf.m
classdef TestQueryPerf < matlab.perftest.TestCase
    % Run with: runperf('TestQueryPerf')
    %
    % The table is populated once in TestClassSetup using INSERT ... SELECT,
    % so driver insert overhead is not on the critical path. Each Test method
    % times only the query call via startMeasuring/stopMeasuring.

    properties
        Client
    end

    properties (Constant)
        TableName = "ch_matlab_perf.query_perf"
        NumRowsPopulated = 1e5
    end

    properties (TestParameter)
        Limit = struct('rows_1k', 1e3, 'rows_10k', 1e4, 'rows_100k', 1e5);
    end

    methods (TestClassSetup)
        function setupClass(tc)
            opts = struct('maxRetries', 0);
            tc.Client = ClickHouseClient("localhost", 9000, "default", "", opts);
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_perf");
            % Memory engine: no disk I/O, no background merges, no compression
            % — isolates the driver path from server-side storage variance.
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS " + tc.TableName + " (" ...
                "  c_int64 Int64, c_float64 Float64, c_string String" ...
                ") ENGINE = Memory"]);
            tc.Client.query("TRUNCATE TABLE " + tc.TableName);
            % Server-side populate avoids driver insert overhead during setup.
            tc.Client.query(sprintf( ...
                "INSERT INTO %s SELECT number, randCanonical(), 'row_text' FROM numbers(%d)", ...
                tc.TableName, tc.NumRowsPopulated));
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS " + tc.TableName);
            delete(tc.Client);
        end
    end

    methods (Test)
        function querySelect(tc, Limit)
            sql = sprintf("SELECT c_int64, c_float64, c_string FROM %s ORDER BY c_int64 LIMIT %d", ...
                tc.TableName, Limit);
            startMeasuring(tc);
            r = tc.Client.query(sql); %#ok<NASGU>
            stopMeasuring(tc);
        end
    end
end
