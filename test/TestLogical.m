% test/TestLogical.m
% Tests MATLAB logical array insert into ClickHouse Bool and UInt8 columns.
%
% Notes:
%   - clickhouse-cpp maps Bool → Type::UInt8 (no separate Bool code in this
%     library version), so Bool columns are returned as uint8 on query.
%   - Cast the result with logical(r.col) when a logical array is needed.
classdef TestLogical < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.logical_test");
            tc.Client.query([ ...
                "CREATE TABLE ch_matlab_test.logical_test (" ...
                "  id     Int32," ...
                "  flag_b Bool," ...
                "  flag_u UInt8" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.logical_test");
            delete(tc.Client);
        end
    end

    methods (Test)
        function testInsertLogicalIntoBoolAndUInt8(tc)
            % logical array inserts correctly into both Bool and UInt8 columns
            id     = int32((1:6)');
            flag_b = logical([1; 0; 1; 1; 0; 1]);
            flag_u = logical([0; 1; 0; 0; 1; 0]);

            tc.Client.insert("ch_matlab_test.logical_test", table(id, flag_b, flag_u));

            r = tc.Client.query([ ...
                "SELECT id, flag_b, flag_u " ...
                "FROM ch_matlab_test.logical_test " ...
                "WHERE id <= 6 ORDER BY id"]);

            tc.verifyEqual(height(r), 6);
            % Bool and UInt8 both return as uint8
            tc.verifyEqual(r.flag_b, uint8(flag_b));
            tc.verifyEqual(r.flag_u, uint8(flag_u));
        end

        function testAllTrue(tc)
            id     = int32([11; 12; 13]);
            flag_b = true(3, 1);
            flag_u = true(3, 1);

            tc.Client.insert("ch_matlab_test.logical_test", table(id, flag_b, flag_u));

            r = tc.Client.query([ ...
                "SELECT flag_b, flag_u " ...
                "FROM ch_matlab_test.logical_test " ...
                "WHERE id IN (11,12,13) ORDER BY id"]);

            tc.verifyEqual(r.flag_b, uint8([1; 1; 1]));
            tc.verifyEqual(r.flag_u, uint8([1; 1; 1]));
        end

        function testAllFalse(tc)
            id     = int32([21; 22; 23]);
            flag_b = false(3, 1);
            flag_u = false(3, 1);

            tc.Client.insert("ch_matlab_test.logical_test", table(id, flag_b, flag_u));

            r = tc.Client.query([ ...
                "SELECT flag_b, flag_u " ...
                "FROM ch_matlab_test.logical_test " ...
                "WHERE id IN (21,22,23) ORDER BY id"]);

            tc.verifyEqual(r.flag_b, uint8([0; 0; 0]));
            tc.verifyEqual(r.flag_u, uint8([0; 0; 0]));
        end

        function testCastQueryResultToLogical(tc)
            % Verify that uint8 query results can be cast back to logical
            id     = int32([31; 32]);
            flag_b = logical([1; 0]);
            flag_u = logical([0; 1]);

            tc.Client.insert("ch_matlab_test.logical_test", table(id, flag_b, flag_u));

            r = tc.Client.query([ ...
                "SELECT id, flag_b, flag_u " ...
                "FROM ch_matlab_test.logical_test " ...
                "WHERE id IN (31,32) ORDER BY id"]);

            tc.verifyTrue( logical(r.flag_b(1)));
            tc.verifyFalse(logical(r.flag_b(2)));
            tc.verifyFalse(logical(r.flag_u(1)));
            tc.verifyTrue( logical(r.flag_u(2)));
        end

        function testQueryBoolColumnDirectly(tc)
            % SELECT bool column without casting returns uint8 0/1
            id     = int32([41; 42; 43]);
            flag_b = logical([1; 0; 1]);
            flag_u = logical([0; 1; 0]);

            tc.Client.insert("ch_matlab_test.logical_test", table(id, flag_b, flag_u));

            r = tc.Client.query([ ...
                "SELECT flag_b, flag_u " ...
                "FROM ch_matlab_test.logical_test " ...
                "WHERE id IN (41,42,43) ORDER BY id"]);

            tc.verifyClass(r.flag_b, 'uint8');
            tc.verifyClass(r.flag_u, 'uint8');
            tc.verifyEqual(r.flag_b, uint8([1; 0; 1]));
            tc.verifyEqual(r.flag_u, uint8([0; 1; 0]));
        end
    end
end
