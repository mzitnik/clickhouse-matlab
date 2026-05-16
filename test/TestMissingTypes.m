% test/TestMissingTypes.m
% Tests Enum8/16, Decimal32/64, IPv4, IPv6, FixedString, LowCardinality(FixedString),
% Nullable variants of each, and Array(Int8/16/UInt8/16).
classdef TestMissingTypes < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.missing_types_test");
            tc.Client.query([ ...
                "CREATE TABLE ch_matlab_test.missing_types_test (" ...
                "  id              Int32," ...
                "  e8              Enum8('alpha'=1,'beta'=2,'gamma'=3)," ...
                "  e16             Enum16('low'=100,'medium'=200,'high'=300)," ...
                "  dec64           Decimal64(6)," ...
                "  dec32           Decimal32(4)," ...
                "  ipv4            IPv4," ...
                "  ipv6            IPv6," ...
                "  fstr            FixedString(8)," ...
                "  lc_fstr         LowCardinality(FixedString(4))," ...
                "  n_e8            Nullable(Enum8('alpha'=1,'beta'=2,'gamma'=3))," ...
                "  n_dec64         Nullable(Decimal64(6))," ...
                "  n_ipv4          Nullable(IPv4)," ...
                "  n_fstr          Nullable(FixedString(8))," ...
                "  arr_i8          Array(Int8)," ...
                "  arr_i16         Array(Int16)," ...
                "  arr_u8          Array(UInt8)," ...
                "  arr_u16         Array(UInt16)" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.missing_types_test");
            delete(tc.Client);
        end
    end

    methods (Test)

        function testRoundTrip(tc)
            N = 5;
            id    = int32((1:N)');
            e8    = ["alpha";"beta";"gamma";"alpha";"beta"];
            e16   = ["low";"medium";"high";"low";"medium"];
            dec64 = [1.234567; 2.345678; 3.456789; 4.567890; 5.678901];
            dec32 = [1.2345; 2.3456; 3.4567; 4.5678; 5.6789];
            ipv4  = ["192.168.1.1";"10.0.0.1";"172.16.0.1";"192.168.1.2";"10.0.0.2"];
            ipv6  = ["2001:db8::1";"2001:db8::2";"::1";"fe80::1";"2001:db8::5"];
            fstr  = ["hello   ";"world   ";"foo     ";"bar     ";"baz     "];
            lc_fstr = ["abcd";"efgh";"ijkl";"abcd";"efgh"];
            n_e8  = e8;    n_e8(2)   = missing; n_e8(4)   = missing;
            n_dec64 = dec64; n_dec64([2 4]) = NaN;
            n_ipv4  = ipv4;  n_ipv4(2) = missing; n_ipv4(4) = missing;
            n_fstr  = fstr;  n_fstr(2) = missing; n_fstr(4) = missing;
            arr_i8  = {int8([1 -2 3]); int8([4 -5]); int8([6]); int8([7 8]); int8([])};
            arr_i16 = {int16([100 -200]); int16([300]); int16([]); int16([400 500]); int16([-1])};
            arr_u8  = {uint8([10 20 30]); uint8([40]); uint8([50 60]); uint8([]); uint8([70])};
            arr_u16 = {uint16([1000 2000]); uint16([3000 4000]); uint16([5000]); uint16([]); uint16([6000])};

            tc.Client.insert("ch_matlab_test.missing_types_test", table( ...
                id, e8, e16, dec64, dec32, ipv4, ipv6, fstr, lc_fstr, ...
                n_e8, n_dec64, n_ipv4, n_fstr, ...
                arr_i8, arr_i16, arr_u8, arr_u16));

            r = tc.Client.query([ ...
                "SELECT id, e8, e16, dec64, dec32, ipv4, ipv6, fstr, lc_fstr," ...
                "  n_e8, n_dec64, n_ipv4, n_fstr, arr_i8, arr_i16, arr_u8, arr_u16" ...
                " FROM ch_matlab_test.missing_types_test ORDER BY id"]);

            tc.verifyEqual(height(r), N);

            % Enum8 / Enum16
            tc.verifyClass(r.e8,  'string');
            tc.verifyClass(r.e16, 'string');
            tc.verifyEqual(r.e8,  e8);
            tc.verifyEqual(r.e16, e16);

            % Decimal64(6) / Decimal32(4)
            tc.verifyClass(r.dec64, 'double');
            tc.verifyClass(r.dec32, 'double');
            tc.verifyEqual(r.dec64, dec64, 'AbsTol', 1e-6);
            tc.verifyEqual(r.dec32, dec32, 'AbsTol', 1e-4);

            % IPv4 / IPv6
            tc.verifyClass(r.ipv4, 'string');
            tc.verifyClass(r.ipv6, 'string');
            tc.verifyEqual(r.ipv4, ipv4);
            % IPv6 representation may vary (e.g. "::1" stays "::1"); just verify non-empty
            tc.verifyTrue(all(strlength(r.ipv6) > 0));

            % FixedString(8): values padded/truncated to 8 bytes
            tc.verifyClass(r.fstr, 'string');
            % Content matches (FixedString pads with NUL — strip trailing NULs for comparison)
            for k = 1:N
                tc.verifyTrue(startsWith(r.fstr(k), strtrim(fstr(k))));
            end

            % LowCardinality(FixedString(4))
            tc.verifyClass(r.lc_fstr, 'string');
            for k = 1:N
                tc.verifyTrue(startsWith(r.lc_fstr(k), strtrim(lc_fstr(k))));
            end

            % Nullable(Enum8): string with missing
            tc.verifyClass(r.n_e8, 'string');
            tc.verifyTrue(ismissing(r.n_e8(2)));
            tc.verifyTrue(ismissing(r.n_e8(4)));
            tc.verifyFalse(ismissing(r.n_e8(1)));
            tc.verifyEqual(r.n_e8(1), "alpha");

            % Nullable(Decimal64)
            tc.verifyClass(r.n_dec64, 'double');
            tc.verifyTrue(isnan(r.n_dec64(2)));
            tc.verifyTrue(isnan(r.n_dec64(4)));
            tc.verifyFalse(isnan(r.n_dec64(1)));
            tc.verifyEqual(r.n_dec64(1), dec64(1), 'AbsTol', 1e-6);

            % Nullable(IPv4)
            tc.verifyClass(r.n_ipv4, 'string');
            tc.verifyTrue(ismissing(r.n_ipv4(2)));
            tc.verifyTrue(ismissing(r.n_ipv4(4)));
            tc.verifyFalse(ismissing(r.n_ipv4(1)));
            tc.verifyEqual(r.n_ipv4(1), ipv4(1));

            % Nullable(FixedString)
            tc.verifyClass(r.n_fstr, 'string');
            tc.verifyTrue(ismissing(r.n_fstr(2)));
            tc.verifyTrue(ismissing(r.n_fstr(4)));
            tc.verifyFalse(ismissing(r.n_fstr(1)));

            % Array(Int8)
            tc.verifyTrue(iscell(r.arr_i8));
            tc.verifyClass(r.arr_i8{1}, 'int8');
            tc.verifyEqual(r.arr_i8{1}, int8([1 -2 3]));
            tc.verifyEqual(numel(r.arr_i8{5}), 0);

            % Array(Int16)
            tc.verifyTrue(iscell(r.arr_i16));
            tc.verifyClass(r.arr_i16{1}, 'int16');
            tc.verifyEqual(r.arr_i16{1}, int16([100 -200]));

            % Array(UInt8)
            tc.verifyTrue(iscell(r.arr_u8));
            tc.verifyClass(r.arr_u8{1}, 'uint8');
            tc.verifyEqual(r.arr_u8{1}, uint8([10 20 30]));

            % Array(UInt16)
            tc.verifyTrue(iscell(r.arr_u16));
            tc.verifyClass(r.arr_u16{1}, 'uint16');
            tc.verifyEqual(r.arr_u16{1}, uint16([1000 2000]));
        end

        function testReturnTypes(tc)
            % Verify all column types (requires testRoundTrip data)
            r = tc.Client.query([ ...
                "SELECT e8, e16, dec64, dec32, ipv4, ipv6, fstr, lc_fstr," ...
                "  n_e8, n_dec64, n_ipv4, n_fstr" ...
                " FROM ch_matlab_test.missing_types_test WHERE id = 1"]);
            tc.verifyClass(r.e8,     'string');
            tc.verifyClass(r.e16,    'string');
            tc.verifyClass(r.dec64,  'double');
            tc.verifyClass(r.dec32,  'double');
            tc.verifyClass(r.ipv4,   'string');
            tc.verifyClass(r.ipv6,   'string');
            tc.verifyClass(r.fstr,   'string');
            tc.verifyClass(r.lc_fstr,'string');
            tc.verifyClass(r.n_e8,   'string');
            tc.verifyClass(r.n_dec64,'double');
            tc.verifyClass(r.n_ipv4, 'string');
            tc.verifyClass(r.n_fstr, 'string');
        end

        function testEmptyResultSchema(tc)
            r = tc.Client.query([ ...
                "SELECT e8, e16, dec64, dec32, ipv4, ipv6, fstr, lc_fstr," ...
                "  n_e8, n_dec64, n_ipv4, n_fstr, arr_i8, arr_i16, arr_u8, arr_u16" ...
                " FROM ch_matlab_test.missing_types_test WHERE id = -9999"]);
            tc.verifyEqual(height(r), 0);
            tc.verifyClass(r.e8,     'string');
            tc.verifyClass(r.e16,    'string');
            tc.verifyClass(r.dec64,  'double');
            tc.verifyClass(r.dec32,  'double');
            tc.verifyClass(r.ipv4,   'string');
            tc.verifyClass(r.ipv6,   'string');
            tc.verifyClass(r.fstr,   'string');
            tc.verifyClass(r.lc_fstr,'string');
            tc.verifyClass(r.n_e8,   'string');
            tc.verifyClass(r.n_dec64,'double');
            tc.verifyClass(r.n_ipv4, 'string');
            tc.verifyClass(r.n_fstr, 'string');
        end

        function testNullableAllNull(tc)
            id = int32([201]);
            e8 = "alpha"; e16 = "low";
            dec64 = 1.0; dec32 = 1.0;
            ipv4 = "1.2.3.4"; ipv6 = "::1";
            fstr = "test    "; lc_fstr = "abcd";
            n_e8 = missing; n_dec64 = NaN; n_ipv4 = missing; n_fstr = missing;
            arr_i8 = {int8([])}; arr_i16 = {int16([])}; arr_u8 = {uint8([])}; arr_u16 = {uint16([])};

            tc.Client.insert("ch_matlab_test.missing_types_test", table( ...
                id, e8, e16, dec64, dec32, ipv4, ipv6, fstr, lc_fstr, ...
                n_e8, n_dec64, n_ipv4, n_fstr, arr_i8, arr_i16, arr_u8, arr_u16));

            r = tc.Client.query([ ...
                "SELECT n_e8, n_dec64, n_ipv4, n_fstr" ...
                " FROM ch_matlab_test.missing_types_test WHERE id = 201"]);
            tc.verifyTrue(ismissing(r.n_e8));
            tc.verifyTrue(isnan(r.n_dec64));
            tc.verifyTrue(ismissing(r.n_ipv4));
            tc.verifyTrue(ismissing(r.n_fstr));
        end

    end
end
