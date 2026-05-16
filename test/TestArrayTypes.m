% test/TestArrayTypes.m
classdef TestArrayTypes < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_test.array_types (" ...
                "  id Int32, arr_f64 Array(Float64), arr_str Array(String)" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.array_types");
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            delete(tc.Client);
        end
    end

    methods (Test)
        function testInsertAndQueryArrayFloat64(tc)
            data = table( ...
                int32([1; 2; 3]), ...
                {[1.1, 2.2, 3.3]; [4.4, 5.5]; [6.6]}, ...
                {{"a","b"}; {"c"}; {"d","e","f"}}, ...
                'VariableNames', {'id','arr_f64','arr_str'});
            tc.Client.insert("ch_matlab_test.array_types", data);

            r = tc.Client.query([ ...
                "SELECT id, arr_f64, arr_str " ...
                "FROM ch_matlab_test.array_types ORDER BY id"]);

            tc.verifyClass(r.arr_f64, 'cell');
            tc.verifyEqual(r.arr_f64{1}, [1.1, 2.2, 3.3], 'AbsTol', 1e-9);
            tc.verifyEqual(r.arr_f64{2}, [4.4, 5.5],       'AbsTol', 1e-9);
            tc.verifyEqual(r.arr_f64{3}, [6.6],             'AbsTol', 1e-9);

            tc.verifyClass(r.arr_str, 'cell');
            tc.verifyEqual(r.arr_str{1}, ["a","b"]);
            tc.verifyEqual(r.arr_str{2}, ["c"]);
            tc.verifyEqual(r.arr_str{3}, ["d","e","f"]);
        end

        function testEmptyArray(tc)
            data = table(int32(99), {double([])}, {{}}, ...
                         'VariableNames', {'id','arr_f64','arr_str'});
            tc.Client.insert("ch_matlab_test.array_types", data);
            r = tc.Client.query([ ...
                "SELECT arr_f64 FROM ch_matlab_test.array_types WHERE id = 99"]);
            tc.verifyEqual(r.arr_f64{1}, double([]));
        end
    end
end
