% test/TestDescribeSchema.m
classdef TestDescribeSchema < matlab.unittest.TestCase
    % Covers the describe() method and the optional schema arg on insert().

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_test.describe_schema (" ...
                "  c_int32 Int32, c_float64 Float64, c_nullable_int Nullable(Int32)" ...
                ") ENGINE = MergeTree() ORDER BY c_int32"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.describe_schema");
            delete(tc.Client);
        end
    end

    methods (TestMethodSetup)
        function methodSetup(tc)
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.describe_schema");
        end
    end

    methods (Test)
        function testDescribeReturnsSchemaTable(tc)
            schema = tc.Client.describe("ch_matlab_test.describe_schema");
            tc.verifyClass(schema, 'table');
            tc.verifyTrue(ismember('name', schema.Properties.VariableNames));
            tc.verifyTrue(ismember('type', schema.Properties.VariableNames));
            tc.verifyEqual(height(schema), 3);
            % Spot-check that the types are reported as expected
            int32_type    = string(schema.type(schema.name == "c_int32"));
            float64_type  = string(schema.type(schema.name == "c_float64"));
            nullable_type = string(schema.type(schema.name == "c_nullable_int"));
            tc.verifyEqual(int32_type,    "Int32");
            tc.verifyEqual(float64_type,  "Float64");
            tc.verifyEqual(nullable_type, "Nullable(Int32)");
        end

        function testInsertWithExplicitSchema(tc)
            % insert(table, data, schema) should produce the same DB state
            % as insert(table, data) without the third arg.
            schema = tc.Client.describe("ch_matlab_test.describe_schema");
            data = table( ...
                int32([1; 2; 3]), ...
                [1.5; 2.5; 3.5], ...
                [int32(10); int32(20); int32(30)], ...
                'VariableNames', {'c_int32','c_float64','c_nullable_int'});

            tc.Client.insert("ch_matlab_test.describe_schema", data, schema);

            r = tc.Client.query("SELECT * FROM ch_matlab_test.describe_schema ORDER BY c_int32");
            tc.verifyEqual(r.c_int32,        int32([1; 2; 3]));
            tc.verifyEqual(r.c_float64,      [1.5; 2.5; 3.5], 'AbsTol', 1e-9);
            % Nullable(Int32) round-trips as double (NaN for null) — see TestNullable
            tc.verifyEqual(r.c_nullable_int, [10.0; 20.0; 30.0], 'AbsTol', 1e-9);
        end

        function testInsertSchemaAppliesNullableHint(tc)
            % If the schema is honoured, inserting an int32 column into a
            % Nullable(Int32) column must still succeed — without the hint,
            % the MEX layer would build a plain ColumnInt32 and ClickHouse
            % would reject it. This test fails if the schema arg is being
            % ignored.
            schema = tc.Client.describe("ch_matlab_test.describe_schema");
            data = table( ...
                int32([42]), ...
                [3.14], ...
                int32([99]), ...
                'VariableNames', {'c_int32','c_float64','c_nullable_int'});

            % This must not throw — proves the Nullable hint is wired through
            tc.Client.insert("ch_matlab_test.describe_schema", data, schema);

            r = tc.Client.query("SELECT c_nullable_int FROM ch_matlab_test.describe_schema");
            % Nullable(Int32) round-trips as double — see testInsertWithExplicitSchema
            tc.verifyEqual(r.c_nullable_int, 99.0, 'AbsTol', 1e-9);
        end

        function testInsertWithBadSchemaThrows(tc)
            % Passing anything other than a valid schema table (from
            % describe()) must throw ClickHouse:badSchema rather than
            % silently producing a malformed insert.
            data = table( ...
                int32([1]), [1.0], int32([1]), ...
                'VariableNames', {'c_int32','c_float64','c_nullable_int'});

            % Empty array — likely user error
            tc.verifyError( ...
                @() tc.Client.insert("ch_matlab_test.describe_schema", data, []), ...
                "ClickHouse:badSchema");

            % Struct instead of table — user passed the wrong thing
            tc.verifyError( ...
                @() tc.Client.insert("ch_matlab_test.describe_schema", data, struct()), ...
                "ClickHouse:badSchema");

            % Table without a 'type' column — not a schema
            bad = table([1;2], 'VariableNames', {'name'});
            tc.verifyError( ...
                @() tc.Client.insert("ch_matlab_test.describe_schema", data, bad), ...
                "ClickHouse:badSchema");
        end

        function testSchemaIsReusable(tc)
            % The same schema value should drive multiple inserts without
            % needing to be re-fetched — this is the whole point of the
            % new arg.
            schema = tc.Client.describe("ch_matlab_test.describe_schema");

            for i = 1:3
                data = table( ...
                    int32(i),  ...
                    double(i) * 1.1, ...
                    int32(i) * 100, ...
                    'VariableNames', {'c_int32','c_float64','c_nullable_int'});
                tc.Client.insert("ch_matlab_test.describe_schema", data, schema);
            end

            r = tc.Client.query("SELECT count() AS n FROM ch_matlab_test.describe_schema");
            tc.verifyEqual(double(r.n), 3);
        end
    end
end
