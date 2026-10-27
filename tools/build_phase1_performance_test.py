"""Package pure IEC per-cycle pipeline timing; fixture ACKs, no network/DB."""
from pathlib import Path
import argparse
from build_phase1_capture_test import ROOT,build
from build_phase1_pipeline_test import KEEP

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output',type=Path)
    keep=(set(KEEP)-{'NG_Add4'})|{'NG_DeliveryParallel','NG_Diagnostics','NG_AuditDrain'}
    build(ap.parse_args().output.resolve(),ROOT/'tests/phase1_performance_test.st',keep)
