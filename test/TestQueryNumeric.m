% test/TestQueryNumeric.m
classdef TestQueryNumeric < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query([ ...
                "CREATE TABLE IF NOT EXISTS ch_matlab_test.numeric_types (" ...
                "  c_float64 Float64, c_float32 Float32," ...
                "  c_int8 Int8, c_int16 Int16, c_int32 Int32, c_int64 Int64," ...
                "  c_uint8 UInt8, c_uint16 UInt16, c_uint32 UInt32, c_uint64 UInt64" ...
                ") ENGINE = MergeTree() ORDER BY c_int32"]);
            tc.Client.query("TRUNCATE TABLE ch_matlab_test.numeric_types");
            tc.Client.query([ ...
                "INSERT INTO ch_matlab_test.numeric_types VALUES " ...
                "(1.5, 2.5, 1, 2, 3, 4, 5, 6, 7, 8)," ...
                "(10.0, 20.0, 10, 20, 30, 40, 50, 60, 70, 80)"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            delete(tc.Client);
        end
    end

    methods (Test)
        function testFloat64(tc)
            r = tc.Client.query("SELECT c_float64 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_float64, 'double');
            tc.verifyEqual(r.c_float64, [1.5; 10.0], 'AbsTol', 1e-9);
        end

        function testFloat32(tc)
            r = tc.Client.query("SELECT c_float32 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_float32, 'single');
            tc.verifyEqual(r.c_float32, single([2.5; 20.0]), 'AbsTol', single(1e-5));
        end

        function testInt8(tc)
            r = tc.Client.query("SELECT c_int8 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_int8, 'int8');
            tc.verifyEqual(r.c_int8, int8([1; 10]));
        end

        function testInt16(tc)
            r = tc.Client.query("SELECT c_int16 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_int16, 'int16');
            tc.verifyEqual(r.c_int16, int16([2; 20]));
        end

        function testInt32(tc)
            r = tc.Client.query("SELECT c_int32 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_int32, 'int32');
            tc.verifyEqual(r.c_int32, int32([3; 30]));
        end

        function testInt64(tc)
            r = tc.Client.query("SELECT c_int64 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_int64, 'int64');
            tc.verifyEqual(r.c_int64, int64([4; 40]));
        end

        function testUInt8(tc)
            r = tc.Client.query("SELECT c_uint8 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_uint8, 'uint8');
            tc.verifyEqual(r.c_uint8, uint8([5; 50]));
        end

        function testUInt16(tc)
            r = tc.Client.query("SELECT c_uint16 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_uint16, 'uint16');
            tc.verifyEqual(r.c_uint16, uint16([6; 60]));
        end

        function testUInt32(tc)
            r = tc.Client.query("SELECT c_uint32 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_uint32, 'uint32');
            tc.verifyEqual(r.c_uint32, uint32([7; 70]));
        end

        function testUInt64(tc)
            r = tc.Client.query("SELECT c_uint64 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyClass(r.c_uint64, 'uint64');
            tc.verifyEqual(r.c_uint64, uint64([8; 80]));
        end

        function testMultipleColumns(tc)
            r = tc.Client.query("SELECT c_float64, c_int32 FROM ch_matlab_test.numeric_types ORDER BY c_int32");
            tc.verifyEqual(width(r), 2);
            tc.verifyEqual(height(r), 2);
        end

        function testEmptyResult(tc)
            r = tc.Client.query("SELECT c_int32 FROM ch_matlab_test.numeric_types WHERE c_int32 = -999");
            tc.verifyEqual(height(r), 0);
        end
    end
end
