# Four-version dnsperf memory observation

Run across 2026-10-26/27 on `mos-test`, Linux x86_64, 4 CPUs, approximately
3.8 GiB RAM, no swap. Production was not contacted. No product code changed,
no deployment, push or merge was performed.

## Method

- Four official release-profile binaries, built with Rust 1.95.0. Every recorded
  build input matches the corresponding Git revision: 245 inputs for main,
  247 for each later version. Existing verified artifacts were reused.
- Same private frozen Oct25 configuration, original provider counts (including
  three domestic suppliers), audit enabled with capacity 100,000. All suppliers
  mapped to deterministic offline CoreDNS answers. This is not a WAN replay.
- Separate fresh process and configuration copy for each version. Empty cache
  dumps; original learner state retained. The unchanged user file contains
  10,000 A questions; SHA256
  `d06f23fdd051be9ebbeb336e41ccb265fc77f3f7f2f7416723e971465e34befd`.
- Three consecutive bursts per process, each followed by 15 seconds idle.
  The first burst starts cold; later bursts reuse that process and caches.
  Every measured burst ended with 100,000 retained audit records.
- Debian dnsperf 2.14.0-5 and its additional library were privately extracted,
  without changing installed packages. Actual command inside a loopback-only
  network namespace, with no external interface or default route:

  ```sh
  dnsperf -s 127.0.0.1 -p 40053 -d <private-query-clean.txt> -c 50 -T 2 -l 10
  ```

- SUT pinned to CPU0, CoreDNS/proxy CPU2, sender CPUs1,3. Each configured
  supplier passed a protocol/content readiness probe before SUT startup.
  Expected initial readiness retries remain in the raw logs.
- Initial RSS measured 3 seconds after API readiness. Startup VmHWM retained
  separately. Kernel VmHWM reset before each burst; `/proc/PID/status` sampled
  every 50 ms until dnsperf exited (198–200 samples per burst). Load peak is
  the maximum of sampled VmHWM and the final sender-completion VmHWM. It does
  not include the earlier startup peak. These are process RSS measurements,
  not requested heap, cgroup memory or whole-machine RAM.

## Results

MiB = KiB / 1024. QPS is the median of the three dnsperf summaries.

| Version | Initial RSS MiB | Startup peak MiB | Load peak MiB | Last idle RSS MiB | Median QPS | Completed / lost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| main `90997571` | 36.8 | 86.5 | 87.9 | 86.9 | 32,288 | 919,286 / 0 |
| Memory milestone `99934eea` | 20.2 | 86.2 | 71.0 | 70.3 | 30,659 | 948,283 / 0 |
| Managed concurrency `f2fc0016` | 20.4 | 85.9 | 73.1 | 71.9 | 37,145 | 1,087,934 / 0 |
| Distinct domains `3687d269` | 20.4 | 86.6 | 70.6 | 69.7 | 34,077 | 1,025,127 / 0 |

All three per-version observations are retained below. Memory columns are
exact KiB; QPS rounded for display.

| Version | Burst | Peak KiB | Idle RSS KiB | Completed | QPS |
| --- | ---: | ---: | ---: | ---: | ---: |
| main | 1 | 86104 | 85976 | 265531 | 26548 |
| main | 2 | 86008 | 85976 | 322960 | 32288 |
| main | 3 | 90056 | 88948 | 330795 | 33053 |
| 99934eea | 1 | 69156 | 69084 | 306603 | 30659 |
| 99934eea | 2 | 69136 | 69096 | 341815 | 34173 |
| 99934eea | 3 | 72696 | 71948 | 299865 | 29981 |
| f2fc0016 | 1 | 70688 | 70688 | 310927 | 31087 |
| f2fc0016 | 2 | 70700 | 70680 | 371521 | 37145 |
| f2fc0016 | 3 | 74892 | 73656 | 405486 | 40542 |
| 3687d269 | 1 | 68612 | 68568 | 344690 | 34463 |
| 3687d269 | 2 | 68568 | 68568 | 339483 | 33939 |
| 3687d269 | 3 | 72264 | 71408 | 340954 | 34077 |

Latest versus main: load peak RSS decreased 19.76%, final idle RSS decreased
19.72%, initial RSS decreased 44.68%. Startup peaks are effectively unchanged.
Including startup, the highest observed process peak is 88,688 KiB latest
versus 90,056 KiB main (only 1.52% lower). The later two patches show no clear
DNS-load memory regression relative to the memory milestone in this run.

## Limits and cleanup

3,980,630 completed queries, zero lost. Replies include approximately 0.13%
NXDOMAIN in every burst; no SERVFAIL was reported by dnsperf. Completion does
not certify DNS correctness, routing equality or matched answer content across
versions. No formal correctness gate was run.

The fixed version order and unconstrained offered rate give different query
totals; this is a short operational observation, not a paired equal-rate CPU
or throughput acceptance benchmark. Each ring filled, but final ring contents
need not be identical. All versions' third idle RSS was about 3 MiB above the
first; this short test cannot establish or exclude a leak. DNS-only load does
not exercise the distinct-domain rank endpoint or the UI's polling allocations.
No long soak, UI memory test or real upstream latency simulation is claimed.

All four owned process/namespace cleanup receipts and original-service identity
guards passed. The original test service and upstream process remained alive.
New binaries, dependencies, configurations and runtime directories were removed
from the VM after verifying the private archive (775 members). Older evidence
and existing test installations were preserved.

Private build manifests, fixture/configuration, corpus, harness, raw dnsperf
logs, 12 RSS traces, reports and cleanup receipts are retained locally under
`/tmp/rtdns-dnsperf-evidence-20261026/`; raw private inputs are excluded from Git.
