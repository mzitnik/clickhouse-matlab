% test/TestQueryString.m
classdef TestQueryString < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_test.string_types (" ...
                "  id Int32, name String" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.string_types");
            tc.Client.query([ ...
                "INSERT INTO ch_matlab_test.string_types VALUES " ...
                "(1, 'alice'), (2, 'bob'), (3, 'carol')"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            delete(tc.Client);
        end
    end

    methods (Test)
        function testStringColumnIsStringArray(tc)
            r = tc.Client.query("SELECT name FROM ch_matlab_test.string_types ORDER BY id");
            tc.verifyClass(r.name, 'string');
            tc.verifyEqual(r.name, ["alice"; "bob"; "carol"]);
        end

        function testEmptyString(tc)
            tc.Client.query([ ...
                "INSERT INTO ch_matlab_test.string_types VALUES (99, '')"]);
            r = tc.Client.query([ ...
                "SELECT name FROM ch_matlab_test.string_types WHERE id = 99"]);
            tc.verifyEqual(r.name, string(""));
        end

        function testUnicode(tc)
            tc.Client.query([ ...
                "INSERT INTO ch_matlab_test.string_types VALUES (100, '日本語')"]);
            r = tc.Client.query([ ...
                "SELECT name FROM ch_matlab_test.string_types WHERE id = 100"]);
            tc.verifyEqual(r.name, string("日本語"));
        end
    end
end
