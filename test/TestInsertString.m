% test/TestInsertString.m
classdef TestInsertString < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_test.insert_string (" ...
                "  id Int32, name String" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.insert_string");
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            delete(tc.Client);
        end
    end

    methods (Test)
        function testInsertStringArrayRoundTrip(tc)
            data = table(int32([1;2;3]), ["alice";"bob";"carol"], ...
                         'VariableNames', {'id','name'});
            tc.Client.insert("ch_matlab_test.insert_string", data);
            r = tc.Client.query([ ...
                "SELECT id, name FROM ch_matlab_test.insert_string ORDER BY id"]);
            tc.verifyEqual(r.name, ["alice";"bob";"carol"]);
        end

        function testInsertCellstrRoundTrip(tc)
            data = struct();
            data.id   = int32([4; 5]);
            data.name = {'dave'; 'eve'};
            tc.Client.insert("ch_matlab_test.insert_string", data);
            r = tc.Client.query([ ...
                "SELECT name FROM ch_matlab_test.insert_string WHERE id IN (4,5) ORDER BY id"]);
            tc.verifyEqual(r.name, ["dave";"eve"]);
        end
    end
end
