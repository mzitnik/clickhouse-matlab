% build.m
function build()
    root      = fileparts(mfilename('fullpath'));
    build_dir = fullfile(root, 'build');
    cmake = getenv('CMAKE');
    if isempty(cmake)
        [ret, cmake] = system('which cmake 2>/dev/null');
        cmake = strtrim(cmake);
        if ret ~= 0 || isempty(cmake)
            candidates = {'/usr/local/bin/cmake', '/usr/bin/cmake', ...
                          '/opt/homebrew/bin/cmake', '/snap/bin/cmake'};
            cmake = '';
            for i = 1:numel(candidates)
                if exist(candidates{i}, 'file')
                    cmake = candidates{i}; break;
                end
            end
        end
        if isempty(cmake)
            error('build:cmakeNotFound', 'cmake not found. Set CMAKE=/path/to/cmake');
        end
        fprintf('Found CMake: %s\n', cmake);
    end
    cmake_flags = getenv('CMAKE_FLAGS');

    matlab_root = matlabroot();

    % Strip MATLAB's LD_LIBRARY_PATH so cmake uses system libraries
    env_prefix = 'env -u LD_PRELOAD LD_LIBRARY_PATH= ';

    fprintf('Configuring...\n');
    ret = system(sprintf('%s"%s" -S "%s" -B "%s" -DCMAKE_BUILD_TYPE=Release -DMatlab_ROOT_DIR="%s" %s', ...
        env_prefix, cmake, root, build_dir, matlab_root, cmake_flags));
    if ret ~= 0, error('CMake configure failed.'); end

    fprintf('Building...\n');
    ret = system(sprintf('%s"%s" --build "%s" --config Release', env_prefix, cmake, build_dir));
    if ret ~= 0, error('CMake build failed.'); end

    % Copy MEX file to src/ so addpath works
    search_dirs = {build_dir, fullfile(build_dir, 'Release')};
    mex_files = [];
    for d = search_dirs
        mex_files = [mex_files; dir(fullfile(d{1}, 'clickhouse_mex.*mex*'))];
    end
    if isempty(mex_files)
        error('build:mexNotFound', 'MEX file not found after build. Check cmake output above.');
    end
    for i = 1:numel(mex_files)
        copyfile(fullfile(mex_files(i).folder, mex_files(i).name), fullfile(root, 'src'));
    end
    fprintf('Build complete. Run: addpath(fullfile(pwd,''src''))\n');
end
