"""Package P05 assertions only. No network, SDK, MQTT or durable store calls."""
from pathlib import Path
import argparse
from build_phase1_capture_test import ROOT,build

KEEP={'Main','NG_Capture','NG_GapLog','NG_SafeAdd','NG_ReportPolicy',
      'NG_AuditCapture','NG_AuditDecision','NG_AuditDrain','NG_AuditAssociation','NG_Diagnostics'}

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output',type=Path)
    build(ap.parse_args().output.resolve(),ROOT/'tests/phase1_diagnostics_test.st',KEEP)
