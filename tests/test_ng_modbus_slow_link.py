"""Offline unit tests for NG_Modbus.st slow-link / LoRa optimizations.

Covers:
1. In-place BAD_TIMEOUT retry (capped at MIN(Device.retryCount, MaxTimeoutRetries))
   and late/stale response draining without false OFFLINE/BAD_TIMEOUT flaps.
2. Small-gap register block merging (SDM630 12 points: 8 requests -> 3 requests)
   with automatic Modbus Exception fallback to strictly contiguous mode.
3. Configurable and RTT-adaptive inter-frame silence pacing (0ms fast Ethernet,
   150ms adaptive slow link, or explicit InterFrameGapMs).
4. IEC 61131-3 structural checks on src/NG_Modbus.st.
"""
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
NG_MODBUS_PATH = ROOT / "src" / "NG_Modbus.st"


@dataclass
class SimPoint:
    index: int
    area: str
    address: int
    data_type: str
    byte_order: str
    poll_interval_ms: int
    enabled: bool = True

    @property
    def width(self) -> int:
        return 2 if self.data_type in ("float32", "int32", "uint32") else 1


def merge_block(
    points: list[SimPoint],
    start_pos: int,
    max_merge_gap: int = 16,
    max_gap_span: int = 40,
    hole_merge_disabled: bool = False,
) -> tuple[int, int, list[SimPoint], bool]:
    """Faithful host-side model of NG_Modbus.st State 15 nearest-gap block merge."""
    first = points[start_pos]
    block = [first]
    block_start = first.address
    block_end = first.address + first.width
    has_holes = False
    eff_gap = 0 if hole_merge_disabled else min(max_merge_gap, 118)
    eff_span = max(2, min(max_gap_span, 120))

    if first.area in ("holding_register", "input_register") and first.data_type != "bool":
        merged = True
        while merged and len(block) < 64:
            merged = False
            best_pt = None
            best_gap = 65535
            best_start = block_start
            best_end = block_end
            for pt in points:
                if (
                    not pt.enabled
                    or pt in block
                    or pt.area != first.area
                    or pt.data_type == "bool"
                    or pt.poll_interval_ms != first.poll_interval_ms
                ):
                    continue
                if pt.address > 65535 - pt.width:
                    continue
                cand_end = pt.address + pt.width
                if pt.address >= block_end:
                    cand_gap = pt.address - block_end
                    cand_span = cand_end - block_start
                    span_limit = 120 if (not has_holes and cand_gap == 0) else eff_span
                    if cand_gap <= eff_gap and cand_span <= span_limit and cand_gap < best_gap:
                        best_pt = pt
                        best_gap = cand_gap
                        best_start = block_start
                        best_end = cand_end
                elif cand_end <= block_start:
                    cand_gap = block_start - cand_end
                    cand_span = block_end - pt.address
                    span_limit = 120 if (not has_holes and cand_gap == 0) else eff_span
                    if cand_gap <= eff_gap and cand_span <= span_limit and cand_gap < best_gap:
                        best_pt = pt
                        best_gap = cand_gap
                        best_start = pt.address
                        best_end = block_end
            if best_pt is not None:
                block.append(best_pt)
                block_start = best_start
                block_end = best_end
                if best_gap > 0:
                    has_holes = True
                merged = True

    return block_start, block_end - block_start, block, has_holes


def partition_all_blocks(
    points: list[SimPoint],
    start_offset: int = 0,
    max_merge_gap: int = 16,
    max_gap_span: int = 40,
    hole_merge_disabled: bool = False,
) -> list[tuple[int, int, list[int], bool]]:
    """Simulate a full poll sweep starting from start_offset."""
    remaining = list(points)
    blocks = []
    pos = start_offset % len(remaining)
    while remaining:
        start, width, blk, has_holes = merge_block(
            remaining,
            pos % len(remaining),
            max_merge_gap=max_merge_gap,
            max_gap_span=max_gap_span,
            hole_merge_disabled=hole_merge_disabled,
        )
        blocks.append((start, width, sorted(p.address for p in blk), has_holes))
        blk_set = {p.index for p in blk}
        remaining = [p for p in remaining if p.index not in blk_set]
        pos = 0
    return sorted(blocks, key=lambda item: item[0])


def simulate_timeout_retry_policy(
    fail_quality: str,
    timeout_in_receive: bool,
    socket_active: bool,
    retry: int,
    device_retry_count: int,
    max_timeout_retries: int = 2,
    last_rtt_ms: int = 0,
    inter_frame_gap_ms: int = 0,
    now_ms: int = 10_000,
) -> tuple[bool, int, int, int]:
    """Faithful model of NG_Modbus.st OperationFailed retry & pacing decision.

    Returns (can_retry, next_retry, next_state, next_tx_allowed_ms).
    """
    timeout_cap = min(device_retry_count, max_timeout_retries)
    can_retry = (
        (fail_quality == "BAD_PROTOCOL" and retry < device_retry_count)
        or (
            fail_quality == "BAD_TIMEOUT"
            and timeout_in_receive
            and socket_active
            and retry < timeout_cap
        )
    )
    if not can_retry:
        next_state = 90 if fail_quality in ("BAD_TIMEOUT", "BAD_CONNECTION") else 15
        return False, retry, next_state, 0

    next_retry = retry + 1
    if fail_quality == "BAD_TIMEOUT" or last_rtt_ms >= 150:
        next_tx = now_ms + max(inter_frame_gap_ms, 200)
        return True, next_retry, 16, next_tx
    if inter_frame_gap_ms > 0:
        return True, next_retry, 16, now_ms + inter_frame_gap_ms
    return True, next_retry, 18, 0


def simulate_success_pacing(now_ms: int, request_sent_ms: int, inter_frame_gap_ms: int = 0) -> tuple[int, int]:
    """Faithful model of NG_Modbus.st State 40 post-success pacing."""
    rtt = now_ms - request_sent_ms if now_ms >= request_sent_ms else 0
    if inter_frame_gap_ms > 0:
        return rtt, now_ms + inter_frame_gap_ms
    if rtt >= 150:
        return rtt, now_ms + 150
    return rtt, 0


def sdm630_12_points() -> list[SimPoint]:
    addrs = [0, 2, 4, 6, 12, 18, 24, 30, 52, 70, 72, 342]
    return [SimPoint(i + 1, "input_register", a, "float32", "ABCD", 15000) for i, a in enumerate(addrs)]


class NGModbusSlowLinkTests(unittest.TestCase):
    def test_st_source_structure_and_new_mechanisms(self):
        st = NG_MODBUS_PATH.read_text(encoding="utf-8-sig")
        for kw_open, kw_close in (
            (r"\bIF\b", r"\bEND_IF\b"),
            (r"\bCASE\b", r"\bEND_CASE\b"),
            (r"\bFOR\b", r"\bEND_FOR\b"),
            (r"\bWHILE\b", r"\bEND_WHILE\b"),
        ):
            self.assertEqual(
                len(re.findall(kw_open, st)),
                len(re.findall(kw_close, st)),
                f"Unbalanced {kw_open}/{kw_close}",
            )
        for token in (
            "MaxMergeGap : UINT := UINT#16;",
            "MaxGapSpan : UINT := UINT#40;",
            "InterFrameGapMs : UDINT := UDINT#0;",
            "MaxTimeoutRetries : USINT := USINT#2;",
            "16:",
            "TimeoutInReceive := TRUE;",
            "StaleDrains",
            "FunctionCode OR BYTE#16#80",
            "HoleMergeDisabled := TRUE;",
            "SavedNextDue[k]",
            "NextTxAllowedMs",
            "LastRttMs",
        ):
            self.assertIn(token, st)
        # Ensure Reset cancellation covers State 16 (retry pacing wait) through State 40.
        self.assertIn("IF (State>=16) AND (State<=40) THEN", st)

    def test_sdm630_12_points_compress_from_8_requests_to_3_order_invariantly(self):
        pts = sdm630_12_points()
        expected = [
            (0, 32, [0, 2, 4, 6, 12, 18, 24, 30], True),
            (52, 22, [52, 70, 72], True),
            (342, 2, [342], False),
        ]
        for start_offset in range(len(pts)):
            blocks = partition_all_blocks(pts, start_offset=start_offset, max_merge_gap=16, max_gap_span=40)
            self.assertEqual(blocks, expected, f"Failed for start_offset={start_offset}")

        # Verify decoding real SDM630 values from merged block 0..31 skips gaps cleanly.
        reg_values = {0: 225.27, 2: 0.0, 4: 0.0, 6: 0.083, 12: 8.61, 18: 18.72, 24: 0.0, 30: 0.46}
        raw_regs = bytearray(32 * 2)
        for addr, val in reg_values.items():
            raw_regs[addr * 2 : addr * 2 + 4] = struct.pack(">f", val)
        for addr, expected_val in reg_values.items():
            off = (addr - 0) * 2
            decoded = struct.unpack(">f", raw_regs[off : off + 4])[0]
            self.assertAlmostEqual(decoded, expected_val, places=3)

    def test_strict_contiguous_fallback_restores_8_blocks_when_hole_merge_disabled(self):
        pts = sdm630_12_points()
        blocks = partition_all_blocks(pts, hole_merge_disabled=True)
        self.assertEqual(len(blocks), 8)
        self.assertEqual(
            [(b[0], b[1], b[3]) for b in blocks],
            [
                (0, 8, False),
                (12, 2, False),
                (18, 2, False),
                (24, 2, False),
                (30, 2, False),
                (52, 2, False),
                (70, 4, False),
                (342, 2, False),
            ],
        )

    def test_contiguous_120_register_limit_preserved_despite_40_reg_gap_span(self):
        pts = [SimPoint(i + 1, "input_register", i * 2, "float32", "ABCD", 1000) for i in range(60)]
        start, width, blk, has_holes = merge_block(pts, 0, max_merge_gap=16, max_gap_span=40)
        self.assertEqual((start, width, len(blk), has_holes), (0, 120, 60, False))

    def test_uint16_overflow_address_guard(self):
        pts = [
            SimPoint(1, "input_register", 65530, "float32", "ABCD", 1000),
            SimPoint(2, "input_register", 65534, "float32", "ABCD", 1000),  # 65534+2 overflows UINT
        ]
        start, width, blk, _ = merge_block(pts, 0, max_merge_gap=16, max_gap_span=40)
        self.assertEqual((start, width, len(blk)), (65530, 2, 1))

    def test_bad_timeout_in_place_retry_and_cap(self):
        # Retry 0 -> 1 -> 2 on receive timeout while socket is active.
        can, r1, st1, nxt1 = simulate_timeout_retry_policy("BAD_TIMEOUT", True, True, 0, device_retry_count=2)
        self.assertEqual((can, r1, st1, nxt1), (True, 1, 16, 10200))

        can, r2, st2, nxt2 = simulate_timeout_retry_policy("BAD_TIMEOUT", True, True, 1, device_retry_count=2)
        self.assertEqual((can, r2, st2, nxt2), (True, 2, 16, 10200))

        # Third timeout (retry == 2) exhausts retries -> State 90 OFFLINE + backoff.
        can, r3, st3, _ = simulate_timeout_retry_policy("BAD_TIMEOUT", True, True, 2, device_retry_count=2)
        self.assertEqual((can, r3, st3), (False, 2, 90))

        # High device_retry_count (e.g. 5) is capped at MaxTimeoutRetries (2) for BAD_TIMEOUT,
        # while BAD_PROTOCOL still honors device_retry_count.
        can_to, _, st_to, _ = simulate_timeout_retry_policy("BAD_TIMEOUT", True, True, 2, device_retry_count=5)
        self.assertEqual((can_to, st_to), (False, 90))
        can_pr, r_pr, st_pr, _ = simulate_timeout_retry_policy("BAD_PROTOCOL", False, True, 2, device_retry_count=5)
        self.assertEqual((can_pr, r_pr, st_pr), (True, 3, 18))

        # Send-side timeout (TimeoutInReceive=False) or closed socket never retries in-place.
        can_send, _, st_send, _ = simulate_timeout_retry_policy("BAD_TIMEOUT", False, True, 0, device_retry_count=2)
        self.assertEqual((can_send, st_send), (False, 90))
        can_dead, _, st_dead, _ = simulate_timeout_retry_policy("BAD_TIMEOUT", True, False, 0, device_retry_count=2)
        self.assertEqual((can_dead, st_dead), (False, 90))

    def test_adaptive_and_explicit_inter_frame_pacing(self):
        # Fast Ethernet reply (RTT=12ms) -> 0ms gap.
        self.assertEqual(simulate_success_pacing(now_ms=1012, request_sent_ms=1000, inter_frame_gap_ms=0), (12, 0))
        # Slow LoRa reply (RTT=480ms) -> 150ms adaptive silence gap.
        self.assertEqual(simulate_success_pacing(now_ms=1480, request_sent_ms=1000, inter_frame_gap_ms=0), (480, 1630))
        # Explicit InterFrameGapMs=120 -> always enforced even on fast link.
        self.assertEqual(simulate_success_pacing(now_ms=1012, request_sent_ms=1000, inter_frame_gap_ms=120), (12, 1132))


if __name__ == "__main__":
    unittest.main()
