% test/TestNullable.m
classdef TestNullable < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query(["CREATE TABLE IF NOT EXISTS ch_matlab_test.nullable_types (" ...
                "  id Int32," ...
                "  n_f64 Nullable(Float64)," ...
                "  n_f32 Nullable(Float32)," ...
                "  n_i32 Nullable(Int32)," ...
                "  n_str Nullable(String)" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.nullable_types");
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            delete(tc.Client);
        end
    end

    methods (Test)
        function testNullableFloat64RoundTrip(tc)
            data = table(int32([1;2;3]), [1.5; NaN; 3.5], ...
                'VariableNames', {'id','n_f64'});
            tc.Client.insert("ch_matlab_test.nullable_types", data);

            r = tc.Client.query([ ...
                "SELECT id, n_f64 FROM ch_matlab_test.nullable_types " ...
                "WHERE id IN (1,2,3) ORDER BY id"]);

            tc.verifyEqual(r.n_f64(1), 1.5, 'AbsTol', 1e-9);
            tc.verifyTrue(isnan(r.n_f64(2)));
            tc.verifyEqual(r.n_f64(3), 3.5, 'AbsTol', 1e-9);
        end

        function testNullableFloat32RoundTrip(tc)
            data = table(int32([4;5;6]), single([10.5; NaN; 30.5]), ...
                'VariableNames', {'id','n_f32'});
            tc.Client.insert("ch_matlab_test.nullable_types", data);

            r = tc.Client.query([ ...
                "SELECT id, n_f32 FROM ch_matlab_test.nullable_types " ...
                "WHERE id IN (4,5,6) ORDER BY id"]);

            tc.verifyClass(r.n_f32, 'single');
            tc.verifyEqual(r.n_f32(1), single(10.5), 'AbsTol', single(1e-5));
            tc.verifyTrue(isnan(r.n_f32(2)));
            tc.verifyEqual(r.n_f32(3), single(30.5), 'AbsTol', single(1e-5));
        end

        function testNullableStringRoundTrip(tc)
            data = table(int32([7;8;9]), ["hello"; missing; "world"], ...
                'VariableNames', {'id','n_str'});
            tc.Client.insert("ch_matlab_test.nullable_types", data);

            r = tc.Client.query([ ...
                "SELECT id, n_str FROM ch_matlab_test.nullable_types " ...
                "WHERE id IN (7,8,9) ORDER BY id"]);

            tc.verifyClass(r.n_str, 'string');
            tc.verifyEqual(r.n_str(1), "hello");
            tc.verifyTrue(ismissing(r.n_str(2)));
            tc.verifyEqual(r.n_str(3), "world");
        end

        function testNullableInt32Query(tc)
            % Insert via SQL so we don't need Nullable(Int32) insert support
            tc.Client.query([ ...
                "INSERT INTO ch_matlab_test.nullable_types (id, n_i32) VALUES " ...
                "(10, 100), (11, NULL), (12, 300)"]);

            r = tc.Client.query([ ...
                "SELECT id, n_i32 FROM ch_matlab_test.nullable_types " ...
                "WHERE id IN (10,11,12) ORDER BY id"]);

            tc.verifyClass(r.n_i32, 'double');
            tc.verifyEqual(r.n_i32(1), 100.0);
            tc.verifyTrue(isnan(r.n_i32(2)));
            tc.verifyEqual(r.n_i32(3), 300.0);
        end

        function testAllNullColumn(tc)
            tc.Client.query([ ...
                "INSERT INTO ch_matlab_test.nullable_types (id, n_f64) VALUES " ...
                "(20, NULL), (21, NULL)"]);

            r = tc.Client.query([ ...
                "SELECT n_f64 FROM ch_matlab_test.nullable_types " ...
                "WHERE id IN (20,21) ORDER BY id"]);

            tc.verifyTrue(isnan(r.n_f64(1)));
            tc.verifyTrue(isnan(r.n_f64(2)));
        end

        function testNoNullsIsNotNullable(tc)
            % A double column with no NaN should insert as plain Float64
            data = table(int32([30;31]), [1.0; 2.0], ...
                'VariableNames', {'id','n_f64'});
            tc.Client.insert("ch_matlab_test.nullable_types", data);

            r = tc.Client.query([ ...
                "SELECT n_f64 FROM ch_matlab_test.nullable_types " ...
                "WHERE id IN (30,31) ORDER BY id"]);

            tc.verifyFalse(any(isnan(r.n_f64)));
            tc.verifyEqual(r.n_f64, [1.0; 2.0], 'AbsTol', 1e-9);
        end
    end
end
