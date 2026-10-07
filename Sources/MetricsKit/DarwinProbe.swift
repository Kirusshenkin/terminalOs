/// The macOS counterpart of `ProcProbe`: same record tags, different sources.
///
/// macOS has no `/proc`, so every figure comes from `sysctl`, `vm_stat`,
/// `netstat`, `df`, `ioreg` and `iostat`. The output keeps the Linux record
/// format, so `SnapshotParser` and the Monitor stay unaware of which system
/// they are looking at.
///
/// One limit is honest rather than hidden: a shell cannot read per-core
/// counters on macOS. `iostat` gives total CPU usage over the interval, which
/// is accumulated into a single `cpu0` so usage stays a difference between
/// snapshots, exactly as on Linux.
public enum DarwinProbe {
    public static let once = """
        echo "K $(sw_vers -productVersion 2>/dev/null || uname -r)"; \
        echo "P $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
        """

    /// `iostat -w` both measures CPU and waits out the interval, so there is
    /// no separate `sleep`.
    public static func loop(interval: Int = 2) -> String {
        """
        u=0; s=0; i=0; while :; do \
        echo "T $(date +%s)"; \
        sysctl -n vm.loadavg | awk -v p="$(ps -A -o stat= | awk '$1 ~ /^R/ {r++} END {print r + 0 "/" NR}')" \
            '{print "L", $2, $3, $4, p}'; \
        echo "U $(( $(date +%s) - $(sysctl -n kern.boottime | awk '{gsub(",", "", $4); print $4}') ))"; \
        echo "M MemTotal: $(( $(sysctl -n hw.memsize) / 1024 ))"; \
        vm_stat | awk '/page size of/ {size = $8} \
            /^Pages (free|inactive|speculative|purgeable):/ {gsub("\\\\.", "", $NF); pages += $NF} \
            END {printf "M MemAvailable: %.0f\\n", pages * size / 1024}'; \
        sysctl -n vm.swapusage | awk '{printf "M SwapTotal: %.0f\\nM SwapFree: %.0f\\n", \
            kb($3), kb($9)} function kb(v) {return (v ~ /G$/ ? v * 1048576 : v * 1024)}'; \
        df -kP 2>/dev/null | awk 'NR > 1 && $1 ~ /^\\/dev\\// \
            && ($6 == "/" || $6 == "/System/Volumes/Data" || $6 ~ /^\\/Volumes\\//) \
            {printf "D %s %.0f %.0f %.0f\\n", $6, $2 * 1024, $3 * 1024, $4 * 1024}'; \
        netstat -ibn | awk '$1 ~ /^en[0-9]+$/ && $3 ~ /^<Link/ \
            {r = NF >= 11 ? $7 : $6; t = NF >= 11 ? $10 : $9; if (r + t > 0) print "N", $1, r, t}'; \
        ioreg -r -c IOBlockStorageDriver -w 0 | awk -F'"Bytes \\\\((Read|Write)\\\\)"=' \
            '/"Statistics"/ {split($2, r, ","); split($3, w, ","); \
            if (r[1] + w[1] > 0) printf "B disk%d %.0f %.0f\\n", n++, r[1] / 512, w[1] / 512}'; \
        echo "F $(sysctl -n kern.num_files)"; \
        ps -Ao pid=,pcpu=,pmem=,ucomm= -r | head -6 | awk '{print "S", $1, $2, $3, $4}'; \
        set -- $(iostat -n 0 -w \(interval) -c 2 | tail -1); \
        u=$((u + $1)); s=$((s + $2)); i=$((i + $3)); \
        echo "C cpu0 $u 0 $s $i 0 0 0 0"; \
        echo "---"; done
        """
    }
}

/// The pair of commands for one system: asked once, then streamed.
public struct MetricsProbe: Sendable {
    public let once: String
    public let loop: String

    public init(darwin: Bool, interval: Int = 2) {
        once = darwin ? DarwinProbe.once : ProcProbe.once
        loop = darwin ? DarwinProbe.loop(interval: interval) : ProcProbe.loop(interval: interval)
    }
}
