% test/TestRetry.m
% Tests for the automatic retry mechanism in ClickHouseClient.
%
% Tests are grouped into three categories:
%
%   1. Sanity  — normal operations unaffected by retry wrapping (always run)
%   2. Exhaustion — permanent errors propagate after all retries fail (always run)
%   3. Socket-kill — recovery via retry + reconnect after live connection is
%      dropped (requires CAP_NET_ADMIN for ss -K; skipped automatically if not
%      available)
%
% Socket-kill tests use:
%   ss -K dst 127.0.0.1 dport = 9000
% On Linux this requires CAP_NET_ADMIN (root or a process with that capability).
% Tests in this category call requireSsKill() which skips via assumeTrue if the
% capability is absent.
classdef TestRetry < matlab.unittest.TestCase

    properties
        Client  % default client: localhost:9000, maxRetries=3
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient('localhost', 9000, 'default', '');
            tc.Client.query('CREATE DATABASE IF NOT EXISTS ch_matlab_test');
            tc.Client.query('DROP TABLE IF EXISTS ch_matlab_test.retry_test');
            tc.Client.query([ ...
                'CREATE TABLE ch_matlab_test.retry_test (' ...
                '  id  Int32,' ...
                '  val Float64' ...
                ') ENGINE = MergeTree() ORDER BY id']);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query('DROP TABLE IF EXISTS ch_matlab_test.retry_test');
            delete(tc.Client);
        end
    end

    methods (TestMethodSetup)
        function truncate(tc)
            tc.Client.query('TRUNCATE TABLE ch_matlab_test.retry_test');
        end
    end

    % ── private helpers ───────────────────────────────────────────────────────
    methods (Access = private)
        function requireSsKill(tc)
            % Skip the calling test if ss -K cannot actually destroy sockets.
            % ss -K is silent when no sockets match its filter, so probing an
            % unused port can't detect missing CAP_NET_ADMIN — the "Operation
            % not permitted" message is only emitted per matched socket. In
            % practice CAP_NET_ADMIN means root.
            [~, uid] = system('id -u');
            tc.assumeTrue(strtrim(uid) == "0", ...
                'ss -K requires CAP_NET_ADMIN (root); skipping socket-kill test');
        end

        function killSocket(tc) %#ok<MANU>
            % Send RST to all established TCP connections to port 9000.
            % No destination address filter: localhost may resolve to ::1
            % (IPv6) or 127.0.0.1 (IPv4) depending on the host configuration.
            system('ss -K dport = 9000 2>/dev/null');
            pause(0.1);  % allow RST to propagate before the next MEX call
        end
    end

    % ── tests ─────────────────────────────────────────────────────────────────
    methods (Test)

        % ── 1. Sanity: retry wrapping must not affect the happy path ──────────

        function testNormalQueryUnaffected(tc)
            r = tc.Client.query('SELECT 99 AS n');
            tc.verifyEqual(r.n, uint8(99));
        end

        function testNormalInsertUnaffected(tc)
            data = table(int32([1;2;3]), [1.1;2.2;3.3], ...
                'VariableNames', {'id','val'});
            tc.Client.insert('ch_matlab_test.retry_test', data);
            r = tc.Client.query('SELECT count() AS n FROM ch_matlab_test.retry_test');
            tc.verifyEqual(r.n, uint64(3));
        end

        % ── 2. Exhaustion: permanent errors surface after all retries fail ────

        function testQueryExhaustsRetriesOnServerError(tc)
            % A server-side error (unknown table) is retried maxRetries times
            % then rethrown — the error id must be correct.
            tc.verifyError( ...
                @() tc.Client.query( ...
                    'SELECT * FROM ch_matlab_test.nonexistent_retry_xyz'), ...
                'ClickHouse:queryError');
        end

        function testInsertExhaustsRetriesOnServerError(tc)
            % Insert into a non-existent table is retried maxRetries times
            % then rethrown.
            bad = table(int32([1]), [1.0], 'VariableNames', {'id','val'});
            tc.verifyError( ...
                @() tc.Client.insert( ...
                    'ch_matlab_test.nonexistent_retry_xyz', bad), ...
                'ClickHouse:insertError');
        end

        function testClientUsableAfterQueryRetryExhaustion(tc)
            % After all query retries are exhausted the client must still work.
            try
                tc.Client.query('SELECT * FROM ch_matlab_test.nonexistent_retry_xyz');
            catch
            end
            r = tc.Client.query('SELECT 42 AS n');
            tc.verifyEqual(r.n, uint8(42));
        end

        function testClientUsableAfterInsertRetryExhaustion(tc)
            % After all insert retries are exhausted the client must still work.
            bad = table(int32([1]), [1.0], 'VariableNames', {'id','val'});
            try
                tc.Client.insert('ch_matlab_test.nonexistent_retry_xyz', bad);
            catch
            end
            good = table(int32([10;20]), [1.0;2.0], 'VariableNames', {'id','val'});
            tc.Client.insert('ch_matlab_test.retry_test', good);
            r = tc.Client.query('SELECT count() AS n FROM ch_matlab_test.retry_test');
            tc.verifyEqual(r.n, uint64(2));
        end

        function testMaxRetriesZeroStillPropagatesError(tc)
            % maxRetries=0 means single attempt only; errors still surface.
            opts.maxRetries = 0;
            c = ClickHouseClient('localhost', 9000, 'default', '', opts);
            tc.verifyError( ...
                @() c.query( ...
                    'SELECT * FROM ch_matlab_test.nonexistent_retry_xyz'), ...
                'ClickHouse:queryError');
            delete(c);
        end

        % ── 3. Socket-kill: connection loss → reconnect → retry succeeds ──────

        function testQueryRecoversAfterSocketReset(tc)
            % After the TCP socket is killed, the first query attempt fails,
            % reconnect fires, and the retry returns the correct result.
            tc.requireSsKill();

            r = tc.Client.query('SELECT 1 AS n');
            tc.verifyEqual(r.n, uint8(1));

            tc.killSocket();

            r = tc.Client.query('SELECT 42 AS n');
            tc.verifyEqual(r.n, uint8(42));
        end

        function testInsertRecoversAfterSocketReset(tc)
            % After the TCP socket is killed, insert retries and the rows land.
            tc.requireSsKill();

            r = tc.Client.query('SELECT 1 AS n');
            tc.verifyEqual(r.n, uint8(1));

            tc.killSocket();

            data = table(int32([10;20]), [1.0;2.0], 'VariableNames', {'id','val'});
            tc.Client.insert('ch_matlab_test.retry_test', data);

            r = tc.Client.query('SELECT count() AS n FROM ch_matlab_test.retry_test');
            tc.verifyEqual(r.n, uint64(2));
        end

        function testQueryFailsWithZeroRetriesAfterSocketReset(tc)
            % With maxRetries=0 a killed socket is not retried — the error
            % propagates. Contrasts with testQueryRecoversAfterSocketReset.
            tc.requireSsKill();

            opts.maxRetries = 0;
            c = ClickHouseClient('localhost', 9000, 'default', '', opts);

            r = c.query('SELECT 1 AS n');
            tc.verifyEqual(r.n, uint8(1));

            % Kill all TCP connections to port 9000 and capture output.
            % ss -K prints one row per killed socket; only a header means
            % no connections were killed (e.g. loopback kill not supported).
            [~, killOut] = system('ss -K dport = 9000 2>&1');
            lines = strtrim(strsplit(strtrim(killOut), newline));
            lines = lines(~cellfun(@isempty, lines));
            tc.assumeTrue(numel(lines) > 1, ...
                'ss -K killed 0 connections (loopback may not be supported); skipping');

            tc.verifyError(@() c.query('SELECT 42 AS n'), 'ClickHouse:queryError');
            delete(c);
        end

    end
end
