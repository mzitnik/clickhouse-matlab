% test/run_perf.m
function run_perf(output_dir, sample_size)
    % run_perf  Run TestInsertPerf + TestQueryPerf and write one CSV per run.
    %
    %   run_perf()                          % writes to <repo>/bench_results/
    %   run_perf(output_dir)
    %   run_perf(output_dir, sample_size)   % default sample_size = 30
    %
    % Uses matlab.perftest.TimeExperiment.withFixedSampleSize so every
    % measurement gets the same number of samples — tighter, more comparable
    % medians than runperf's adaptive sampling.
    %
    % The CSV filename is the UTC timestamp of the run (yyyyMMddTHHmmssZ.csv).
    % One row per measurement (i.e. per parameterized test name).
    arguments
        output_dir  (1,1) string = fullfile(pwd, 'bench_results')
        sample_size (1,1) double {mustBePositive, mustBeInteger} = 30
    end

    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    op_ts  = datetime('now', 'TimeZone', 'UTC');
    fname  = string(op_ts, "yyyyMMdd'T'HHmmss'Z'") + ".csv";
    ts_iso = string(op_ts, "yyyy-MM-dd'T'HH:mm:ss'Z'");

    suites = {'TestInsertPerf', 'TestQueryPerf'};
    rows = table();
    experiment = matlab.perftest.TimeExperiment.withFixedSampleSize(sample_size);
    for i = 1:numel(suites)
        fprintf('\n=== %s (%d samples per measurement) ===\n', ...
            suites{i}, sample_size);
        suite = matlab.unittest.TestSuite.fromClass( ...
            meta.class.fromName(suites{i}));
        r = experiment.run(suite);
        s = sampleSummary(r);

        % Name looks like "TestInsertPerf/insertMixed(NumRows=rows_1k)".
        names     = string(s.Name);
        suite_col = strings(height(s), 1);
        test_col  = strings(height(s), 1);
        param_col = strings(height(s), 1);
        for k = 1:height(s)
            parts = split(names(k), ["/", "(", ")"]);
            if numel(parts) >= 3
                suite_col(k) = parts(1);
                test_col(k)  = parts(2);
                param_col(k) = parts(3);
            else
                suite_col(k) = string(suites{i});
                test_col(k)  = names(k);
            end
        end

        chunk = table( ...
            repmat(ts_iso, height(s), 1), ...
            suite_col, test_col, param_col, ...
            s.SampleSize, s.Mean, s.StandardDeviation, ...
            s.Min, s.Median, s.Max, ...
            'VariableNames', {'timestamp','suite','test_name','parameter', ...
                              'sample_size','mean_sec','std_sec', ...
                              'min_sec','median_sec','max_sec'});
        rows = [rows; chunk]; %#ok<AGROW>
    end

    csv_path = fullfile(output_dir, fname);
    writetable(rows, csv_path);
    fprintf('\nWrote %s (%d rows)\n', csv_path, height(rows));
end
