# clickhouse-matlab

ClickHouse driver for MATLAB. Speaks the native TCP protocol (not HTTP) via a MEX binding around [clickhouse-cpp](https://github.com/ClickHouse/clickhouse-cpp).

## Features

- Native TCP protocol with optional TLS
- Auto-reconnect and protocol-level retry, tunable via `maxRetries`
- Bidirectional conversion: `query` returns a MATLAB `table`; `insert` accepts a `table` or scalar struct of arrays
- Broad ClickHouse type coverage (see [Supported types](#supported-types))
- `NaN` ↔ `NULL` for numerics, `missing` ↔ `NULL` for strings

## Requirements

- **MATLAB**: R2024b or newer (older releases likely work but are untested)
- **CMake**: ≥ 3.20
- **C++ compiler**: g++-9 recommended — avoids GLIBCXX mismatches with MATLAB's bundled libstdc++. Override with `-DCMAKE_CXX_COMPILER=...` for a different compiler.
- **Platform**: Linux, macOS, Windows. MEX outputs are `.mexa64` / `.mexmaca64` / `.mexw64` respectively.

## Build

The repository uses a git submodule for clickhouse-cpp. Clone with submodules:

```bash
git clone --recurse-submodules <repo-url>
# or, if already cloned:
git submodule update --init --recursive
```

From MATLAB:

```matlab
build
```

From a shell:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DMatlab_ROOT_DIR=$(matlabroot)
cmake --build build --config Release
cp build/clickhouse_mex.mex* src/
```

Add `src/` to your MATLAB path before use:

```matlab
addpath(fullfile(pwd, 'src'))
```

## Quick start

```matlab
% Connect
c = ClickHouseClient('localhost', 9000, 'default', '');

% Query — returns a MATLAB table
t = c.query('SELECT number, toString(number) AS s FROM numbers(10)');

% Create a table and insert rows from a MATLAB table
c.query(['CREATE TABLE IF NOT EXISTS demo (' ...
         '  id Int32, val Float64' ...
         ') ENGINE = MergeTree() ORDER BY id']);

data = table(int32([1;2;3]), [1.1;2.2;3.3], 'VariableNames', {'id','val'});
c.insert('demo', data);

% Cleanup
delete(c);
```

## Connection options

`ClickHouseClient(host, port, user, password, options)` accepts an `options` struct:

| Field | Type | Default | Notes |
|---|---|---|---|
| `tls.enabled` | logical | `false` | Enable TLS. Typically used with port `9440`. |
| `tls.skip_verification` | logical | `false` | Disable certificate verification (dev only). |
| `tls.ca_file` | string | `""` | Path to CA bundle for verification. |
| `maxRetries` | integer | `3` | Retry attempts on query/insert failure. `0` = fail-fast (no ping-before-query, no protocol-level retry, no MATLAB-level retry). |
| `settings` | containers.Map | — | Parsed but **not** applied — clickhouse-cpp's `ClientOptions` does not expose per-connection settings. |
| `useragent` | string | — | Parsed but **not** applied — `ClientOptions` does not expose `SetClientName`. |

## Supported types

| ClickHouse | MATLAB |
|---|---|
| `Int8`–`Int64`, `UInt8`–`UInt64` | matching native integer class |
| `Float32` / `Float64` | `single` / `double` |
| `String` | `string` (query) / `string` or `cellstr` (insert) |
| `FixedString(N)` | `string` / `cellstr` |
| `Date`, `Date32`, `DateTime` | `double` (POSIX seconds) |
| `DateTime64(p)` | `double` (POSIX seconds with sub-second precision) |
| `Decimal32(S)`, `Decimal64(S)`, `Decimal128(S)`, `Decimal(P,S)` | `double` |
| `Enum8`, `Enum16` | `string` |
| `IPv4`, `IPv6` | `string` |
| `LowCardinality(T)` | mapping of inner type `T` |
| `Nullable(T)` | inner-type mapping with `NaN` or `missing` for nulls |
| `Array(T)` | cell array of inner-type vectors |

## Testing

```bash
./test/run_tests.sh           # default: ClickHouse 25.3
./test/run_tests.sh 25.8      # pin a version
./test/run_tests.sh latest    # latest stable
```

The script builds the MEX, spins up a ClickHouse container in Docker, and runs `run_all_tests` in MATLAB batch mode.

A small set of socket-recovery tests in `TestRetry` require `CAP_NET_ADMIN` (root) to issue `ss -K`; they auto-skip when not run as root.

CI runs the test suite on every push to `main` and on pull requests across a matrix of ClickHouse versions (see `.github/workflows/ci.yml`).

## Limitations

- `options.settings` and `options.useragent` are silently ignored — see above.
- `query` accumulates the entire result set in MEX memory before producing the MATLAB `table`. Peak memory ≈ 2× result size. For very large results, paginate with `LIMIT … OFFSET …` or `SAMPLE`.
- `insert` issues one `DESCRIBE TABLE` round-trip per call to infer column types. Batch many rows into a single `insert` rather than looping with small batches.

## License

Apache 2.0. See [LICENSE](LICENSE).
