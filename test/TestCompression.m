% test/TestCompression.m
classdef TestCompression < matlab.unittest.TestCase
    % TestCompression  Tests for the native-protocol compression option.
    %
    %   Offline: the Compression enum's int8 values mirror clickhouse-cpp.

    methods (Test)
        % --- Offline: enum values mirror clickhouse-cpp CompressionMethod ---
        function testEnumUnderlyingValues(tc)
            % Must match clickhouse-cpp's CompressionMethod enum
            % (contrib/clickhouse-cpp/clickhouse/client.h): None=-1, LZ4=1, ZSTD=2.
            tc.verifyEqual(int8(Compression.None), int8(-1), ...
                "Compression.None underlying value must be -1 (CompressionMethod::None)");
            tc.verifyEqual(int8(Compression.LZ4),  int8(1), ...
                "Compression.LZ4 underlying value must be 1 (CompressionMethod::LZ4)");
            tc.verifyEqual(int8(Compression.ZSTD), int8(2), ...
                "Compression.ZSTD underlying value must be 2 (CompressionMethod::ZSTD)");
        end

        % --- Offline: a non-Compression value is rejected before connecting ---
        function testBadCompressionThrows(tc)
            opts = struct('compression', "gzip");   % string, not a Compression
            tc.verifyError( ...
                @() ClickHouseClient("localhost", 9000, "default", "", opts), ...
                'ClickHouse:badOption');
        end

        % --- Integration: each method round-trips data unchanged ---
        function testRoundtripPerMethod(tc)
            methodsToTest = [Compression.None, Compression.LZ4, Compression.ZSTD];
            % c_float64 uses n + 0.5: exactly representable in IEEE 754 for these
            % small integers, so verifyEqual can compare without a tolerance.
            expected = table( ...
                int64((1:1000)'), ...
                (1:1000)' + 0.5, ...
                repmat("row_text", 1000, 1), ...
                'VariableNames', {'c_int64', 'c_float64', 'c_string'});

            for m = methodsToTest
                label = "compression=" + int8(m);   % string() on int8 enum -> number
                opts = struct('compression', m, 'maxRetries', 0);
                client = ClickHouseClient("localhost", 9000, "default", "", opts);
                % delete the client even if an assertion or query throws mid-loop,
                % so one method's failure can't leak a connection or skip the rest.
                cleanup = onCleanup(@() delete(client)); %#ok<NASGU>
                client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
                client.query("DROP TABLE IF EXISTS ch_matlab_test.compression_rt");
                client.query([ ...
                    "CREATE TABLE ch_matlab_test.compression_rt (" ...
                    "  c_int64 Int64, c_float64 Float64, c_string String" ...
                    ") ENGINE = Memory"]);
                client.insert("ch_matlab_test.compression_rt", expected);
                got = client.query( ...
                    "SELECT c_int64, c_float64, c_string FROM " + ...
                    "ch_matlab_test.compression_rt ORDER BY c_int64");
                tc.verifyEqual(got.c_int64,   expected.c_int64, ...
                    "c_int64 mismatch (" + label + ")");
                tc.verifyEqual(got.c_float64, expected.c_float64, ...
                    "c_float64 mismatch (" + label + ")");
                tc.verifyEqual(got.c_string,  expected.c_string, ...
                    "c_string mismatch (" + label + ")");
                client.query("DROP TABLE IF EXISTS ch_matlab_test.compression_rt");
            end
        end

        % --- Integration: the default (no compression field) is usable ---
        function testDefaultRoundtrips(tc)
            % Constructing without a compression field exercises the LZ4 default
            % injected by ClickHouseClient. A data round-trip (not just ping)
            % proves the default codec actually compresses/decompresses blocks.
            client = ClickHouseClient("localhost", 9000, "default", "");
            cleanup = onCleanup(@() delete(client)); %#ok<NASGU>
            client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            client.query("DROP TABLE IF EXISTS ch_matlab_test.compression_default");
            client.query([ ...
                "CREATE TABLE ch_matlab_test.compression_default (" ...
                "  c_int64 Int64, c_string String" ...
                ") ENGINE = Memory"]);
            expected = table( ...
                int64((1:1000)'), ...
                repmat("row_text", 1000, 1), ...
                'VariableNames', {'c_int64', 'c_string'});
            client.insert("ch_matlab_test.compression_default", expected);
            got = client.query( ...
                "SELECT c_int64, c_string FROM " + ...
                "ch_matlab_test.compression_default ORDER BY c_int64");
            tc.verifyEqual(got.c_int64, expected.c_int64, "default c_int64 mismatch");
            tc.verifyEqual(got.c_string, expected.c_string, "default c_string mismatch");
            client.query("DROP TABLE IF EXISTS ch_matlab_test.compression_default");
        end
    end
end
