# Derived Keys benchmarks

These release benchmarks measure the work involved in forming keys and reusing a synthetic calculation. Use them to inspect a workload on a particular compiler and machine; the results do not establish a universal speedup. The [generic release sample](Results.md) and [size-facade release sample](Size-Results.md) record timings, computation counts, and memory limits from one machine.

## Run the suite

From the repository root on macOS, with the package's Swift 6.4 toolchain selected:

```sh
Benchmarks/run.sh
```

The runner builds `DerivedKeysBenchmarks` in release mode and starts each case in a separate process under `/usr/bin/time -l`. It writes JSON Lines measurements, per-case resource reports, and compiler, hardware, OS, arguments, and source SHA-256 digests to a temporary directory. The directory is printed before the measurements.

Use the same arguments for comparisons:

```sh
Benchmarks/run.sh --iterations 5000 --payload-bytes 8192 --capacity 128
```

Defaults are 1,000 measured operations, a 4,096-byte payload, and a capacity of 128 entries. The large-payload case uses at least 262,144 bytes. Arguments must be positive integers; iteration and capacity limits are 1,000,000, and the payload limit is 16,777,216 bytes. To choose the output directory, set `BENCHMARK_OUTPUT_DIR` to a new directory for each run. Keep generated results outside the repository when comparing candidates. Set `BENCHMARK_SCRATCH_PATH` to use an isolated SwiftPM build directory.

For one case, run the executable through SwiftPM:

```sh
swift run -c release DerivedKeysBenchmarks --case warm-hit --iterations 5000
```

Repeat runs under comparable system load and power conditions. Compare distributions across runs, not a single short timing. Each JSON row reports the mean time per operation within that timed loop, with no subtraction of timer or loop overhead.

## Workload and cases

The input is one immutable byte array, a relevant integer format, and an irrelevant integer UI field. The calculation reads only the bytes and format: four passes of wrapping integer mixing over the payload produce a `UInt64`. It is a synthetic CPU workload rather than an exporter or UI measurement. The format changes the result; the UI field does not.

The concrete key is a `RequestKey` containing a `DerivedKey` and a `KeyPair` of labeled content and format leaves. Its context and version are fixed at zero. Payload arrays share one copy-on-write buffer within a case; generating a new format does not copy the bytes. A separate runtime-graph case measures `KeySource` and `DependencySnapshot`.

| Case | Timed work | Cache behavior |
| --- | --- | --- |
| `typed-projection` | Form a typed key and assign it into a preallocated 64-slot observation array. Hash the final array after timing. | No cache or calculation. Includes observation-array assignment. |
| `typed-hash` | Hash preconstructed typed keys, cycling through 64 formats. | No cache or calculation; projection is outside timing. |
| `direct` | Calculate every result, cycling through `min(capacity, 64)` formats. | No key construction or cache. |
| `cold-miss` | Project, look up, calculate, and insert a new format each time. | Effective capacity equals iterations, so every request misses without eviction. |
| `warm-hit` | Project and look up, cycling through `min(capacity, 64)` formats. | That working set is populated before timing; measured calculations must be zero. |
| `relevant-change` | Project, look up, calculate, and insert a previously unseen format each time. | Uses the requested bounded capacity; after filling, insertions evict. |
| `irrelevant-change` | Change only the omitted UI field, then project and look up. | One entry is populated before timing; measured calculations must be zero. |
| `large-payload` | Project and look up one format with a payload of at least 256 KiB. | One warmed entry; hashing still reads payload elements. |
| `shared-source` | Three rows: snapshot formation with observation-array assignment; hashing preconstructed snapshots; then warmed snapshot formation and cache lookup. | The graph has two branches sharing the content leaf. The cache phase changes only the omitted UI field. |
| `eviction` | Project, look up, calculate, and insert while cycling through `capacity + 1` formats. | Every request misses, including initial filling; later requests revisit evicted keys. |

The runtime graph is built before timing. Its left branch contains content and format; its right branch reuses the same content source. Snapshot capture can reuse that shared source within one request. Snapshot hashing still inspects both structural occurrences. This case uses a local cache for one operation, keyed directly by its dependency snapshots.

Projection-only timings include the observation array's assignment and reference-counting costs. Hash-only timings include reading a preconstructed key and accumulating its hash. These rows identify separate sources of cost; subtracting their timings from an end-to-end row does not isolate an exact cache overhead.

## Size-facade workload and cases

The five `size-` cases exercise `DerivedKeysUI.SizeCache` synchronously on the main actor with plain Swift value roots. They do not measure UIKit text fitting. Two child caches select a byte payload, integer variant, and floating-point scale through heterogeneous key paths. The parent selects spacing and orientation, and maps both child descriptions through its nested roots. Child snapshots contribute to the parent key; the parent recipe explicitly requests child sizes on a parent miss.

Each child calculation performs the same four passes of wrapping byte mixing as the generic calculation, then produces a bounded `CGSize` using its scale and a fixed 320-by-240 proposal. The parent combines both sizes with spacing. Both children share one payload buffer; each uses a different integer variant. Input assembly occurs inside the measured loops. Payload generation, graph construction, observation-array allocation, and warmup occur before timing.

| Case | Timed work | Expected measured calculations: parent / left / right |
| --- | --- | --- |
| `size-snapshot` | Capture the composed snapshot into a preallocated 64-slot array while changing both child variants. Hash the retained snapshots after timing. | 0 / 0 / 0 |
| `size-warm-parent` | Repeatedly request one complete parent key warmed before timing. Each request still captures and hashes its dependencies. | 0 / 0 / 0 |
| `size-parent-miss` | Warm both children, then change only parent spacing each iteration. Child inputs and their effective proposals stay equal. | iterations / 0 / 0 |
| `size-cold` | Change both child variants each iteration, capturing, looking up, measuring, and inserting at every level. | iterations / iterations / iterations |
| `size-direct` | Assemble the same inputs as `size-cold` and perform the same child and parent math directly. No snapshots or cache lookups occur inside timing. | iterations / iterations / iterations |

All three caches use the requested capacity. `size-cold` and `size-parent-miss` evict after filling when iterations exceed capacity; their names do not imply unbounded storage. Use capacity at least equal to iterations for a comparison without those evictions. The direct and snapshot cases construct the same graph before timing but leave result storage empty.

Every returned size contributes to a printed integer checksum. After timing, each result-producing case checks that checksum against direct calculation over the same inputs. The cold and direct cases must therefore produce the same checksum. These validation calculations are outside the timed loop. Runtime preconditions also check the individual parent and child calculation counts. Snapshot checksums use process-local hashes and can differ between processes.

## Read the output

`elapsedNanoseconds` covers the named loop; `nanosecondsPerOperation` divides it by `iterations`. Payload generation, cache warmup, graph construction, observation-array allocation, and JSON encoding are outside the named loops. Per-iteration input assembly remains inside timing. The shared-source process has three consecutive loops, each reported separately.

`computationCount` counts calls inside the measured loop, and `warmupComputationCount` reports calculation calls before it. Expected hit and miss counts are checked at runtime. The calculation has an inline barrier, and every returned value contributes to the printed checksum. Projection-only keys are kept in the observation array and hashed after timing. Hash rows accumulate process-local Swift hashes, so their checksums can differ across processes. Checksums provide observable output, not stable identifiers or cryptographic verification.

The generic cases retain their original JSON schema. Their memory fields describe the cache at the end of the loop:

| Field | Meaning |
| --- | --- |
| `cacheCapacity`, `entryCount` | Effective entry limit and retained entry count. `cold-miss` overrides the requested limit. Phases without a cache report zero. |
| `requestedCapacity` | The command-line limit, including for phases whose working set depends on it. |
| `logicalPayloadBytesAcrossEntries` | Entry count multiplied by payload length. Counts the same shared content once per semantic key. |
| `uniquePayloadBytesReferencedByEntries` | Payload length when entries exist, otherwise zero. All entries in a case reference one byte-array buffer. |
| `resultValueBytesAcrossEntries` | Entry count multiplied by `MemoryLayout<UInt64>.stride`. |

These fields account for payload content and result values. They exclude array headers, spare allocation capacity, dictionaries, cache slots, labels, erased graph nodes, allocator overhead, and executable/runtime memory. The input also owns the shared payload, so its bytes are not exclusively attributable to the cache. The fields are not a heap census or an estimate of total retained key bytes.

The size cases use a separate schema. Each `caches` entry names the parent, left child, or right child and reports `cacheCapacity`, `entryCount`, `computationCount`, and `warmupComputationCount`. `requestedCapacityPerCache` is the command-line capacity; `payloadBytesPerChild` is the payload length selected by each child. `storedResultValueBytesAcrossCaches` sums final entry counts multiplied by `MemoryLayout<CGSize>.stride`. It excludes snapshots, cache storage, closures, headers, and allocator overhead. Total retained key bytes and allocation counts are unknown.

The `.time.txt` file records the whole process's high-water resident set size, including startup, setup, warmup, measurement, output, and temporary storage. For `shared-source`, that includes all three phases and its observation array. For size cases it also includes graph setup, snapshot-checksum hashing, and the direct validation pass outside timing. It cannot establish per-phase memory use, live cache retention after clearing, or bytes owned only by keys. Allocation counts remain unknown because the runner does not attach an allocation profiler; resource counters from `time` are not allocation counts.

Keep the metadata and raw measurements with any published numbers. State the case, payload size, capacity, iterations, compiler, hardware, and sampling method. Use application-specific profiling before choosing a projection, revision scheme, or cache size.
