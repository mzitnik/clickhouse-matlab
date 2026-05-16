% test/TestInsertNumeric.m
classdef TestInsertNumeric < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_test.insert_numeric (" ...
                "  c_float64 Float64, c_float32 Float32," ...
                "  c_int8 Int8, c_int16 Int16, c_int32 Int32, c_int64 Int64," ...
                "  c_uint8 UInt8, c_uint16 UInt16, c_uint32 UInt32, c_uint64 UInt64" ...
                ") ENGINE = MergeTree() ORDER BY c_int32"]);
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.insert_numeric");
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            delete(tc.Client);
        end
    end

    methods (Test)
        function testRoundTripAllNumericTypes(tc)
            data = table( ...
                [1.5; 2.5],         ...  % Float64  (double)
                single([3.5; 4.5]), ...  % Float32  (single)
                int8([1; 2]),       ...  % Int8
                int16([3; 4]),      ...  % Int16
                int32([5; 6]),      ...  % Int32
                int64([7; 8]),      ...  % Int64
                uint8([9; 10]),     ...  % UInt8
                uint16([11; 12]),   ...  % UInt16
                uint32([13; 14]),   ...  % UInt32
                uint64([15; 16]),   ...  % UInt64
                'VariableNames', {'c_float64','c_float32','c_int8','c_int16', ...
                                  'c_int32','c_int64','c_uint8','c_uint16', ...
                                  'c_uint32','c_uint64'});
            tc.Client.insert("ch_matlab_test.insert_numeric", data);

            r = tc.Client.query([ ...
                "SELECT * FROM ch_matlab_test.insert_numeric ORDER BY c_int32"]);

            tc.verifyEqual(r.c_float64, [1.5; 2.5],        'AbsTol', 1e-9);
            tc.verifyEqual(r.c_float32, single([3.5; 4.5]), 'AbsTol', single(1e-5));
            tc.verifyEqual(r.c_int8,    int8([1; 2]));
            tc.verifyEqual(r.c_int16,   int16([3; 4]));
            tc.verifyEqual(r.c_int32,   int32([5; 6]));
            tc.verifyEqual(r.c_int64,   int64([7; 8]));
            tc.verifyEqual(r.c_uint8,   uint8([9; 10]));
            tc.verifyEqual(r.c_uint16,  uint16([11; 12]));
            tc.verifyEqual(r.c_uint32,  uint32([13; 14]));
            tc.verifyEqual(r.c_uint64,  uint64([15; 16]));
        end
    end
end
