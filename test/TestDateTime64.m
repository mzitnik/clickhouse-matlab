% test/TestDateTime64.m
% Tests DateTime64 insert and query for precisions 0 (seconds), 3 (ms), 6 (µs)
% and Nullable(DateTime64(3)).
%
% Wire representation:
%   ClickHouse DateTime64(N) stores int64 ticks = POSIX_seconds * 10^N.
%   The driver converts to/from MATLAB double (POSIX seconds).
%   Nullable(DateTime64): NaN = SQL NULL.
classdef TestDateTime64 < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.datetime64_test");
            tc.Client.query([ ...
                "CREATE TABLE ch_matlab_test.datetime64_test (" ...
                "  id          Int32," ...
                "  ts_s        DateTime64(0)," ...
                "  ts_ms       DateTime64(3)," ...
                "  ts_us       DateTime64(6)," ...
                "  ts_nullable Nullable(DateTime64(3))" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.datetime64_test");
            delete(tc.Client);
        end
    end

    methods (Test)
        function testRoundTripAllPrecisions(tc)
            % 2024-01-15 12:00:00 UTC = POSIX 1705320000
            base = 1705320000.0;
            N = 5;
            id    = int32((1:N)');
            ts_s  = base + (0:N-1)';             % whole seconds
            ts_ms = base + (0:N-1)' * 0.001;     % 1 ms apart
            ts_us = base + (0:N-1)' * 0.000001;  % 1 µs apart
            ts_nullable = ts_ms;
            ts_nullable([2 4]) = NaN;

            tc.Client.insert("ch_matlab_test.datetime64_test", ...
                table(id, ts_s, ts_ms, ts_us, ts_nullable));

            r = tc.Client.query([ ...
                "SELECT id, ts_s, ts_ms, ts_us, ts_nullable " ...
                "FROM ch_matlab_test.datetime64_test " ...
                "WHERE id BETWEEN 1 AND 5 ORDER BY id"]);

            tc.verifyEqual(height(r), N);

            % DateTime64(0): whole-second precision
            tc.verifyEqual(r.ts_s, ts_s, 'AbsTol', 1.0);

            % DateTime64(3): millisecond precision
            tc.verifyEqual(r.ts_ms, ts_ms, 'AbsTol', 1e-3);

            % DateTime64(6): microsecond precision
            tc.verifyEqual(r.ts_us, ts_us, 'AbsTol', 1e-6);

            % Nullable: NaN for nulls, value for non-nulls
            tc.verifyTrue( isnan(r.ts_nullable(2)));
            tc.verifyTrue( isnan(r.ts_nullable(4)));
            tc.verifyFalse(isnan(r.ts_nullable(1)));
            tc.verifyFalse(isnan(r.ts_nullable(3)));
            tc.verifyFalse(isnan(r.ts_nullable(5)));
            tc.verifyEqual(r.ts_nullable(1), ts_nullable(1), 'AbsTol', 1e-3);
            tc.verifyEqual(r.ts_nullable(3), ts_nullable(3), 'AbsTol', 1e-3);
            tc.verifyEqual(r.ts_nullable(5), ts_nullable(5), 'AbsTol', 1e-3);
        end

        function testSubSecondPrecision(tc)
            % Verify that sub-second values survive the round-trip
            id = int32([11; 12; 13]);
            base = 1705320000.0;
            ts_s  = [base; base; base];
            ts_ms = [base + 0.000; base + 0.500; base + 0.999];
            ts_us = [base + 0.000000; base + 0.000500; base + 0.000999];
            ts_nullable = ts_ms;

            tc.Client.insert("ch_matlab_test.datetime64_test", ...
                table(id, ts_s, ts_ms, ts_us, ts_nullable));

            r = tc.Client.query([ ...
                "SELECT ts_ms, ts_us " ...
                "FROM ch_matlab_test.datetime64_test " ...
                "WHERE id IN (11,12,13) ORDER BY id"]);

            tc.verifyEqual(r.ts_ms, ts_ms, 'AbsTol', 1e-3);
            tc.verifyEqual(r.ts_us, ts_us, 'AbsTol', 1e-6);
        end

        function testNullableAllNull(tc)
            id = int32([21; 22]);
            base = 1705320000.0;
            ts_s = [base; base + 1]; ts_ms = ts_s; ts_us = ts_s;
            ts_nullable = [NaN; NaN];

            tc.Client.insert("ch_matlab_test.datetime64_test", ...
                table(id, ts_s, ts_ms, ts_us, ts_nullable));

            r = tc.Client.query([ ...
                "SELECT ts_nullable " ...
                "FROM ch_matlab_test.datetime64_test " ...
                "WHERE id IN (21,22) ORDER BY id"]);

            tc.verifyTrue(isnan(r.ts_nullable(1)));
            tc.verifyTrue(isnan(r.ts_nullable(2)));
        end

        function testNullableAllNonNull(tc)
            id = int32([31; 32]);
            base = 1705320000.0;
            ts_s = [base; base + 1]; ts_ms = ts_s; ts_us = ts_s;
            ts_nullable = [base + 0.100; base + 0.200];

            tc.Client.insert("ch_matlab_test.datetime64_test", ...
                table(id, ts_s, ts_ms, ts_us, ts_nullable));

            r = tc.Client.query([ ...
                "SELECT ts_nullable " ...
                "FROM ch_matlab_test.datetime64_test " ...
                "WHERE id IN (31,32) ORDER BY id"]);

            tc.verifyFalse(isnan(r.ts_nullable(1)));
            tc.verifyFalse(isnan(r.ts_nullable(2)));
            tc.verifyEqual(r.ts_nullable, ts_nullable, 'AbsTol', 1e-3);
        end

        function testReturnTypeIsDouble(tc)
            % All DateTime64 variants return as MATLAB double (POSIX seconds)
            id = int32([41]);
            base = 1705320000.0;
            ts_s = base; ts_ms = base; ts_us = base; ts_nullable = base;

            tc.Client.insert("ch_matlab_test.datetime64_test", ...
                table(id, ts_s, ts_ms, ts_us, ts_nullable));

            r = tc.Client.query([ ...
                "SELECT ts_s, ts_ms, ts_us, ts_nullable " ...
                "FROM ch_matlab_test.datetime64_test WHERE id = 41"]);

            tc.verifyClass(r.ts_s,        'double');
            tc.verifyClass(r.ts_ms,       'double');
            tc.verifyClass(r.ts_us,       'double');
            tc.verifyClass(r.ts_nullable, 'double');
        end

        function testEmptyResultSchema(tc)
            % Empty result for DateTime64 columns returns empty double column
            r = tc.Client.query([ ...
                "SELECT ts_ms, ts_us, ts_nullable " ...
                "FROM ch_matlab_test.datetime64_test " ...
                "WHERE id = -9999"]);

            tc.verifyEqual(height(r), 0);
            tc.verifyClass(r.ts_ms,       'double');
            tc.verifyClass(r.ts_us,       'double');
            tc.verifyClass(r.ts_nullable, 'double');
        end

        function testMultipleTimestamps(tc)
            % Insert a larger batch spanning different dates
            N = 10;
            id = int32((51:51+N-1)');
            % Span one hour in millisecond steps
            ts_ms = 1705320000.0 + (0:N-1)' * 360.0;
            ts_s  = floor(ts_ms);
            ts_us = ts_ms;
            ts_nullable = ts_ms;
            ts_nullable([3 7]) = NaN;

            tc.Client.insert("ch_matlab_test.datetime64_test", ...
                table(id, ts_s, ts_ms, ts_us, ts_nullable));

            r = tc.Client.query([ ...
                "SELECT id, ts_s, ts_ms, ts_us, ts_nullable " ...
                "FROM ch_matlab_test.datetime64_test " ...
                "WHERE id BETWEEN 51 AND 60 ORDER BY id"]);

            tc.verifyEqual(height(r), N);
            tc.verifyEqual(r.ts_ms, ts_ms, 'AbsTol', 1e-3);
            tc.verifyEqual(r.ts_s,  ts_s,  'AbsTol', 1.0);
            tc.verifyEqual(r.ts_us, ts_us, 'AbsTol', 1e-6);

            tc.verifyTrue( isnan(r.ts_nullable(3)));
            tc.verifyTrue( isnan(r.ts_nullable(7)));
            tc.verifyFalse(isnan(r.ts_nullable(1)));
        end
    end
end
