% test/TestInsertRecovery.m
% Regression test for the inserting_ stuck-state bug in clickhouse-cpp.
%
% Scenario: client->Insert() sets inserting_=true before sending the query to
% the server. If the server returns an exception (e.g. table not found), the
% client throws before calling EndInsert(), leaving inserting_=true forever.
% Without the ResetConnection() fix in cmd_insert, every subsequent insert on
% the same client would fail with:
%   "cannot execute query while inserting, use SendInsertData instead"
%
% This suite verifies that the connection recovers automatically.
classdef TestInsertRecovery < matlab.unittest.TestCase

    properties
        Client
    end

    methods (TestClassSetup)
        function setupClass(tc)
            tc.Client = ClickHouseClient("localhost", 9000, "default", "");
            tc.Client.query("CREATE DATABASE IF NOT EXISTS ch_matlab_test");
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.recovery_test");
            tc.Client.query([ ...
                "CREATE TABLE ch_matlab_test.recovery_test (" ...
                "  id    Int32," ...
                "  value Float64" ...
                ") ENGINE = MergeTree() ORDER BY id"]);
        end
    end

    methods (TestClassTeardown)
        function teardownClass(tc)
            tc.Client.query("DROP TABLE IF EXISTS ch_matlab_test.recovery_test");
            delete(tc.Client);
        end
    end

    methods (Test)
        function testRecoveryAfterFailedInsertIntoNonExistentTable(tc)
            % Step 1: insert into a table that does not exist.
            % The server returns an exception packet after Insert() has already
            % set inserting_=true, leaving the client in a stuck state unless
            % ResetConnection() is called in the error path.
            bad_data = table(int32([1; 2]), [1.0; 2.0], ...
                'VariableNames', {'id', 'value'});

            tc.verifyError( ...
                @() tc.Client.insert("ch_matlab_test.does_not_exist", bad_data), ...
                'ClickHouse:insertError');

            % Step 2: insert valid data into the real table.
            % Without the fix this throws "cannot execute query while inserting".
            good_data = table(int32([10; 20; 30]), [1.1; 2.2; 3.3], ...
                'VariableNames', {'id', 'value'});

            tc.verifyWarningFree( ...
                @() tc.Client.insert("ch_matlab_test.recovery_test", good_data));

            % Step 3: verify the data actually landed.
            r = tc.Client.query([ ...
                "SELECT id, value FROM ch_matlab_test.recovery_test " ...
                "ORDER BY id"]);

            tc.verifyEqual(height(r), 3);
            tc.verifyEqual(r.id,    int32([10; 20; 30]));
            tc.verifyEqual(r.value, [1.1; 2.2; 3.3], 'AbsTol', 1e-9);
        end

        function testRecoveryAfterMultipleConsecutiveFailures(tc)
            % Repeated failures must not permanently corrupt the connection.
            bad_data = table(int32([1]), [1.0], 'VariableNames', {'id', 'value'});

            for i = 1:3
                tc.verifyError( ...
                    @() tc.Client.insert("ch_matlab_test.does_not_exist", bad_data), ...
                    'ClickHouse:insertError');
            end

            % Connection must still be usable after multiple failures.
            good_data = table(int32([40; 50]), [4.4; 5.5], ...
                'VariableNames', {'id', 'value'});

            tc.verifyWarningFree( ...
                @() tc.Client.insert("ch_matlab_test.recovery_test", good_data));

            r = tc.Client.query([ ...
                "SELECT id FROM ch_matlab_test.recovery_test " ...
                "WHERE id IN (40, 50) ORDER BY id"]);
            tc.verifyEqual(r.id, int32([40; 50]));
        end

        function testNormalInsertUnaffected(tc)
            % Sanity check: a normal insert with no prior failure works fine.
            data = table(int32([100; 200]), [10.0; 20.0], ...
                'VariableNames', {'id', 'value'});

            tc.Client.insert("ch_matlab_test.recovery_test", data);

            r = tc.Client.query([ ...
                "SELECT id, value FROM ch_matlab_test.recovery_test " ...
                "WHERE id IN (100, 200) ORDER BY id"]);

            tc.verifyEqual(r.id,    int32([100; 200]));
            tc.verifyEqual(r.value, [10.0; 20.0], 'AbsTol', 1e-9);
        end
    end
end
