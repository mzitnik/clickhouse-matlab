% test/TestConnection.m
classdef TestConnection < matlab.unittest.TestCase

    methods (Test)
        function testPingReturnsTrue(tc)
            client = ClickHouseClient("localhost", 9000, "default", "");
            result = client.ping();
            tc.verifyTrue(result);
            delete(client);
        end

        function testWrongHostThrows(tc)
            tc.verifyError(@() ClickHouseClient("nonexistent.invalid", 9000, "default", ""), ...
                'ClickHouse:connectionError');
        end

        function testWrongPortThrows(tc)
            tc.verifyError(@() ClickHouseClient("localhost", 9999, "default", ""), ...
                'ClickHouse:connectionError');
        end

        function testTLSConnection(tc)
            % Requires ClickHouse listening on port 9440 with TLS
            opts = struct('tls', struct('enabled', true, 'skip_verification', true));
            client = ClickHouseClient("localhost", 9440, "default", "", opts);
            result = client.ping();
            tc.verifyTrue(result);
            delete(client);
        end

        function testCustomSettings(tc)
            opts = struct();
            opts.settings = containers.Map({'max_threads'}, {'2'});
            client = ClickHouseClient("localhost", 9000, "default", "", opts);
            result = client.ping();
            % Note: settings are parsed but not applied (clickhouse-cpp limitation).
            tc.verifyTrue(result);
            delete(client);
        end

        function testUserAgent(tc)
            opts = struct('useragent', 'matlab-test/1.0');
            client = ClickHouseClient("localhost", 9000, "default", "", opts);
            result = client.ping();
            % Note: useragent is parsed but not applied (clickhouse-cpp limitation).
            tc.verifyTrue(result);
            delete(client);
        end
    end
end
