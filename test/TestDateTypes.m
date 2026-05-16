% test/TestDateTypes.m
% Tests Date, Date32, DateTime, LowCardinality, and Nullable(Int*/UInt*)
% insert and query round-trips.
%
% MATLAB representation:
%   Date / Date32 / DateTime → double (POSIX seconds).
%   LowCardinality(T)        → same as T (transparent to user).
%   Nullable(Int*/UInt*)     → double (NaN = NULL).
classdef TestDateTypes < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.date_types_test");
            tc.Client.query([ ...
                "CREATE TABLE ch_matlab_test.date_types_test (" ...
                "  id            Int32," ...
                "  d             Date," ...
                "  d32           Date32," ...
                "  dt            DateTime," ...
                "  dt_tz         DateTime('UTC')," ...
                "  lc_str        LowCardinality(String)," ...
                "  n_int32       Nullable(Int32)," ...
                "  n_uint64      Nullable(UInt64)," ...
                "  n_int8        Nullable(Int8)," ...
                "  n_date        Nullable(Date)," ...
                "  n_datetime    Nullable(DateTime)" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.date_types_test");
            delete(tc.Client);
        end
    end

    methods (Test)

        function testDateRoundTrip(tc)
            % Date: POSIX seconds at midnight (days * 86400)
            % 2024-01-15 = day 19737 since epoch = 19737 * 86400
            base_day = 19737;  % 2024-01-15
            N = 5;
            id  = int32((1:N)');
            d   = double((base_day:base_day+N-1)') * 86400;  % Date
            d32 = d;                                           % Date32
            dt  = d + 3600;                                    % DateTime (add 1 hour)
            dt_tz = dt;
            lc_str = ["alpha"; "beta"; "gamma"; "alpha"; "beta"];
            n_int32  = [100.0; NaN; 300.0; NaN; 500.0];
            n_uint64 = [1e9; NaN; 3e9; NaN; 5e9];
            n_int8   = [1.0; NaN; 3.0; NaN; 5.0];
            n_date   = d;  n_date([2 4]) = NaN;
            n_datetime = dt; n_datetime([2 4]) = NaN;

            tc.Client.insert("ch_matlab_test.date_types_test", table( ...
                id, d, d32, dt, dt_tz, lc_str, ...
                n_int32, n_uint64, n_int8, n_date, n_datetime));

            r = tc.Client.query([ ...
                "SELECT id, d, d32, dt, dt_tz, lc_str," ...
                "  n_int32, n_uint64, n_int8, n_date, n_datetime" ...
                " FROM ch_matlab_test.date_types_test ORDER BY id"]);

            tc.verifyEqual(height(r), N);

            % Date and Date32: round-trip to nearest day (86400 sec resolution)
            tc.verifyClass(r.d, 'double');
            tc.verifyClass(r.d32, 'double');
            tc.verifyEqual(r.d,   d,   'AbsTol', 86400.0, 'Date round-trip');
            tc.verifyEqual(r.d32, d32, 'AbsTol', 86400.0, 'Date32 round-trip');

            % DateTime: 1-second resolution
            tc.verifyClass(r.dt, 'double');
            tc.verifyEqual(r.dt,    dt,    'AbsTol', 1.0, 'DateTime round-trip');
            tc.verifyEqual(r.dt_tz, dt_tz, 'AbsTol', 1.0, 'DateTime(UTC) round-trip');

            % LowCardinality(String): transparent, returns string
            tc.verifyClass(r.lc_str, 'string');
            tc.verifyEqual(r.lc_str, lc_str);

            % Nullable(Int32): double with NaN=NULL
            tc.verifyClass(r.n_int32, 'double');
            tc.verifyTrue( isnan(r.n_int32(2)));
            tc.verifyTrue( isnan(r.n_int32(4)));
            tc.verifyFalse(isnan(r.n_int32(1)));
            tc.verifyEqual(r.n_int32(1), 100.0);
            tc.verifyEqual(r.n_int32(3), 300.0);
            tc.verifyEqual(r.n_int32(5), 500.0);

            % Nullable(UInt64): double with NaN=NULL
            tc.verifyClass(r.n_uint64, 'double');
            tc.verifyTrue( isnan(r.n_uint64(2)));
            tc.verifyTrue( isnan(r.n_uint64(4)));
            tc.verifyEqual(r.n_uint64(1), 1e9, 'AbsTol', 1);
            tc.verifyEqual(r.n_uint64(3), 3e9, 'AbsTol', 1);
            tc.verifyEqual(r.n_uint64(5), 5e9, 'AbsTol', 1);

            % Nullable(Int8): double with NaN=NULL
            tc.verifyClass(r.n_int8, 'double');
            tc.verifyTrue( isnan(r.n_int8(2)));
            tc.verifyTrue( isnan(r.n_int8(4)));
            tc.verifyEqual(r.n_int8(1), 1.0);
            tc.verifyEqual(r.n_int8(3), 3.0);

            % Nullable(Date): double with NaN=NULL
            tc.verifyClass(r.n_date, 'double');
            tc.verifyTrue( isnan(r.n_date(2)));
            tc.verifyTrue( isnan(r.n_date(4)));
            tc.verifyFalse(isnan(r.n_date(1)));
            tc.verifyEqual(r.n_date(1), d(1), 'AbsTol', 86400.0);

            % Nullable(DateTime): double with NaN=NULL
            tc.verifyClass(r.n_datetime, 'double');
            tc.verifyTrue( isnan(r.n_datetime(2)));
            tc.verifyTrue( isnan(r.n_datetime(4)));
            tc.verifyFalse(isnan(r.n_datetime(1)));
            tc.verifyEqual(r.n_datetime(1), dt(1), 'AbsTol', 1.0);
        end

        function testReturnTypes(tc)
            % Verify all column types returned correctly for existing data
            r = tc.Client.query([ ...
                "SELECT id, d, d32, dt, lc_str, n_int32, n_uint64" ...
                " FROM ch_matlab_test.date_types_test WHERE id = 1"]);
            tc.verifyClass(r.id,       'int32');
            tc.verifyClass(r.d,        'double');
            tc.verifyClass(r.d32,      'double');
            tc.verifyClass(r.dt,       'double');
            tc.verifyClass(r.lc_str,   'string');
            tc.verifyClass(r.n_int32,  'double');
            tc.verifyClass(r.n_uint64, 'double');
        end

        function testEmptyResultSchema(tc)
            % Empty result must return correctly-typed columns
            r = tc.Client.query([ ...
                "SELECT id, d, d32, dt, lc_str, n_int32, n_uint64, n_date, n_datetime" ...
                " FROM ch_matlab_test.date_types_test WHERE id = -9999"]);
            tc.verifyEqual(height(r), 0);
            tc.verifyClass(r.id,         'int32');
            tc.verifyClass(r.d,          'double');
            tc.verifyClass(r.d32,        'double');
            tc.verifyClass(r.dt,         'double');
            tc.verifyClass(r.lc_str,     'string');
            tc.verifyClass(r.n_int32,    'double');
            tc.verifyClass(r.n_uint64,   'double');
            tc.verifyClass(r.n_date,     'double');
            tc.verifyClass(r.n_datetime, 'double');
        end

        function testNullableAllNull(tc)
            % Insert row with all nullable columns NULL
            id = int32([101]);
            base_day = 19737;
            d = double(base_day) * 86400;
            d32 = d; dt = d; dt_tz = dt;
            lc_str = "null_row";
            n_int32 = NaN; n_uint64 = NaN; n_int8 = NaN;
            n_date = NaN; n_datetime = NaN;

            tc.Client.insert("ch_matlab_test.date_types_test", table( ...
                id, d, d32, dt, dt_tz, lc_str, ...
                n_int32, n_uint64, n_int8, n_date, n_datetime));

            r = tc.Client.query([ ...
                "SELECT n_int32, n_uint64, n_int8, n_date, n_datetime" ...
                " FROM ch_matlab_test.date_types_test WHERE id = 101"]);
            tc.verifyTrue(isnan(r.n_int32));
            tc.verifyTrue(isnan(r.n_uint64));
            tc.verifyTrue(isnan(r.n_int8));
            tc.verifyTrue(isnan(r.n_date));
            tc.verifyTrue(isnan(r.n_datetime));
        end

        function testDateMinMax(tc)
            % Test boundary dates: Unix epoch and a future date
            id = int32([201; 202]);
            d   = [0.0; double(365*50) * 86400];  % 1970-01-01 and ~2020
            d32 = d; dt = d; dt_tz = dt;
            lc_str = ["epoch"; "future"];
            n_int32 = [0.0; 0.0]; n_uint64 = [0.0; 0.0]; n_int8 = [0.0; 0.0];
            n_date = d; n_datetime = dt;

            tc.Client.insert("ch_matlab_test.date_types_test", table( ...
                id, d, d32, dt, dt_tz, lc_str, ...
                n_int32, n_uint64, n_int8, n_date, n_datetime));

            r = tc.Client.query([ ...
                "SELECT d, d32, dt" ...
                " FROM ch_matlab_test.date_types_test" ...
                " WHERE id IN (201, 202) ORDER BY id"]);
            tc.verifyEqual(height(r), 2);
            tc.verifyEqual(r.d(1), 0.0, 'AbsTol', 86400.0);
            tc.verifyEqual(r.dt(2), d(2), 'AbsTol', 1.0);
        end

    end
end
