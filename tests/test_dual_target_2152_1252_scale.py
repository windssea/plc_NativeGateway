"""Offline verification for BOTH AXC F 2152 and AXC F 1252 scale enhancements (zero PLC access)."""
from dataclasses import dataclass
from pathlib import Path
import re
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import build_dual_scale_candidates  # noqa: E402
import verify_project_catalog  # noqa: E402


@dataclass(frozen=True)
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


def simulate_ng_modbus_block_merge(points: list[SimPoint], start_pos: int = 0) -> tuple[int, int, list[SimPoint]]:
    """Faithful host-side reference of NG_Modbus.st State 15 contiguous register merge."""
    first = points[start_pos]
    block = [first]
    start_addr = first.address
    end_addr = first.address + first.width
    if first.area in ("holding_register", "input_register"):
        merged = True
        while merged and len(block) < 64:
            merged = False
            for pt in points:
                if (
                    not pt.enabled
                    or pt in block
                    or pt.area != first.area
                    or pt.poll_interval_ms != first.poll_interval_ms
                    or len(block) >= 64
                ):
                    continue
                cand_end = pt.address + pt.width
                if pt.address == end_addr and (cand_end - start_addr) <= 120:
                    block.append(pt)
                    end_addr = cand_end
                    merged = True
                elif cand_end == start_addr and (end_addr - pt.address) <= 120:
                    block.append(pt)
                    start_addr = pt.address
                    merged = True
    return start_addr, end_addr - start_addr, block


def simulate_ng_modbus_backoff_ms(level: int, unit_id: int) -> int:
    lvl = min(5, max(1, level))
    ms = 1000
    for _ in range(lvl):
        ms = ms * 2 if ms < 15000 else 30000
    return ms + (unit_id % 8) * 125


class DualTarget2152And1252ScaleTests(unittest.TestCase):
    def test_2152_preserves_verified_running_archive_outside_modbus_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = build_dual_scale_candidates.build_2152_candidate(Path(tmp) / '2152.pcwex')
            self.assertEqual(report['baseProjectSha256'],
                             'ac9cfec98d592e6c14f074725176be572831335c39273ef666f468de34236dc0')
            with zipfile.ZipFile(build_dual_scale_candidates.BASE_2152) as original, zipfile.ZipFile(report['output']) as candidate:
                self.assertEqual(set(original.namelist()), set(candidate.namelist()))
                changed = {name for name in original.namelist() if original.read(name) != candidate.read(name)}
                allowed = {'PROJECT/Logical%20Elements/NG_Modbus.pou/Code.st',
                           'PROJECT/Logical%20Elements/NG_Modbus.pou/Variables.var',
                           'PROJECT/Logical%20Elements/Main.pou/Code.st'}
                self.assertTrue(changed)
                self.assertTrue(changed <= allowed, changed - allowed)

    def test_frozen_project_catalog_and_releases_are_untouched(self):
        result = verify_project_catalog.verify()
        self.assertTrue(result["rootAliasMatches"])
        self.assertFalse(result["plcConnected"])
        self.assertFalse(result["plcDownloaded"])

    def test_ng_modbus_st_structural_integrity_and_interface_compatibility(self):
        st = (ROOT / "src" / "NG_Modbus.st").read_text(encoding="utf-8-sig")
        self.assertIn("FUNCTION_BLOCK NG_Modbus", st)
        self.assertIn("END_FUNCTION_BLOCK", st)
        self.assertIn("BlockStartAddr", st)
        self.assertIn("BackoffLevel", st)
        self.assertEqual(len(re.findall(r"\bCASE\b", st)), len(re.findall(r"\bEND_CASE\b", st)))
        self.assertEqual(len(re.findall(r"\bFOR\b", st)), len(re.findall(r"\bEND_FOR\b", st)))
        self.assertEqual(len(re.findall(r"\bWHILE\b", st)), len(re.findall(r"\bEND_WHILE\b", st)))
        # Verify VAR_INPUT / VAR_IN_OUT / VAR_OUTPUT signatures stay backward-compatible.
        for required_port in (
            "Device : NG_Device;",
            "Points : ARRAY[1..320] OF NG_Point;",
            "Samples : ARRAY[1..320] OF NG_Sample;",
            "Buffer : NG_Buffer;",
            "StateText : STRING[16];",
            "LastGoodTimestamp : ULINT;",
        ):
            self.assertIn(required_port, st)
        # Verify BUF_TO_REAL (ToFloat) resets REQ:=FALSE immediately before REQ:=TRUE
        # inside the merged-block FOR decode loop so every float32 point in a multi-point block
        # gets a clean rising edge instead of reusing k=1's FloatValue.
        decode_loops = [
            m.group(1)
            for m in re.finditer(r"FOR k := 1 TO BlockCount DO(.*?)END_FOR;", st, re.DOTALL)
            if "Point.dataType = 'float32'" in m.group(1)
        ]
        self.assertEqual(len(decode_loops), 1, "Expected exactly one float32 decode FOR loop")
        loop_body = decode_loops[0]
        idx_false = loop_body.find("ToFloat(REQ := FALSE,")
        idx_true = loop_body.find("ToFloat(REQ := TRUE,")
        self.assertGreater(idx_false, -1, "ToFloat(REQ := FALSE) must be called inside FOR k := 1 TO BlockCount")
        self.assertGreater(idx_true, idx_false, "ToFloat(REQ := FALSE) must precede ToFloat(REQ := TRUE) inside the loop")

    def test_dual_target_offline_build_covers_both_axcf2152_and_axcf1252(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            rep_2152 = build_dual_scale_candidates.build_2152_candidate(out_dir / "gw-2152.pcwex")
            rep_1252 = build_dual_scale_candidates.build_1252_candidate(out_dir / "gw-1252.pcwex")

            for rep, expected_target, expected_gw_id in (
                (rep_2152, "AXCF2152", "NG-HUB-2152-01"),
                (rep_1252, "AXCF1252", "NG-HUB-1252-01"),
            ):
                self.assertEqual(rep["target"], expected_target)
                self.assertEqual(rep["pouCount"], 66)
                self.assertTrue(rep["durableLayoutUnchanged"])
                self.assertTrue(rep["hardwareHmiTasksUnchanged"])
                self.assertFalse(rep["controllerAccess"])
                self.assertFalse(rep["downloaded"])
                self.assertIn('-dev.', rep['version'])
                with zipfile.ZipFile(rep["output"]) as zf:
                    modbus_code = zf.read("PROJECT/Logical%20Elements/NG_Modbus.pou/Code.st").decode("utf-8")
                    main_code = zf.read("PROJECT/Logical%20Elements/Main.pou/Code.st").decode("utf-8")
                    self.assertIn("BlockStartAddr", modbus_code)
                    self.assertIn("BackoffLevel", modbus_code)
                    self.assertIn(expected_gw_id, main_code)
                    self.assertIn(rep['version'], main_code)

    def test_12_point_float32_fc04_meter_merges_into_single_transaction_without_holes(self):
        # Mirrors the AXCF 1252 12-point FC04 Float32 ABCD meter (addresses 0,2,4,...,22).
        points = [
            SimPoint(i + 1, "input_register", i * 2, "float32", "ABCD", 1000)
            for i in range(12)
        ]
        start, width, block = simulate_ng_modbus_block_merge(points)
        self.assertEqual(start, 0)
        self.assertEqual(width, 24)  # 48 payload bytes + 9 header = 57B <= 260B
        self.assertEqual(len(block), 12)  # 12 round trips -> 1 single round trip!

        # Verify an unconfigured register hole (address 30) is NEVER bridged!
        with_hole = points + [SimPoint(13, "input_register", 30, "float32", "ABCD", 1000)]
        start2, width2, block2 = simulate_ng_modbus_block_merge(with_hole)
        self.assertEqual(start2, 0)
        self.assertEqual(width2, 24)
        self.assertEqual(len(block2), 12)

        # Verify decoding a merged FC04 payload preserves Float32 ABCD values and isolates NaN to BAD_DECODE.
        values = [220.5 + i for i in range(11)] + [float("nan")]
        payload = b"".join(struct.pack(">f", v) for v in values)
        self.assertEqual(len(payload), width * 2)
        decoded = []
        for pt in block:
            off = (pt.address - start) * 2
            raw = payload[off : off + 4]
            uint32 = int.from_bytes(raw, "big")
            is_bad = (uint32 & 0x7F800000) == 0x7F800000
            decoded.append("BAD_DECODE" if is_bad else round(struct.unpack(">f", raw)[0], 2))
        self.assertEqual(decoded[:11], [round(220.5 + i, 2) for i in range(11)])
        self.assertEqual(decoded[11], "BAD_DECODE")

    def test_exponential_backoff_caps_at_30s_with_unit_stagger(self):
        seq = [simulate_ng_modbus_backoff_ms(lvl, unit_id=0) for lvl in range(1, 7)]
        self.assertEqual(seq, [2000, 4000, 8000, 16000, 30000, 30000])
        staggered = {simulate_ng_modbus_backoff_ms(2, unit_id=u) for u in range(8)}
        self.assertEqual(len(staggered), 8)


if __name__ == "__main__":
    unittest.main()
