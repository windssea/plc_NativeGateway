"""Generate constant-index IEC SHA rounds for the measured eCLR hot path.

The template owns lifecycle, padding, bounded block copies and deadlines.
Expanded rounds avoid ROR_DWORD calls and repeated bounds checks. Native
hash/ownership tests remain required; this generator never operates a PLC.
"""
from pathlib import Path
import argparse
ROOT=Path(__file__).resolve().parents[1]
K=(1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221, 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580, 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986, 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895, 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037, 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344, 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779, 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298)

def generate(reader='fast'):
    template=(ROOT/'tools/templates/NG_StringSHA256.st.in').read_text(encoding='utf-8')
    words=[]
    for i in range(16):
        values=[f'TO_DWORD(TO_BYTE(GET_CHAR(Payload,TO_INT(Offset)+{4*i+j+1})))' for j in range(4)]
        words.append(f'        W[{i}]:=SHL({values[0]},24) OR SHL({values[1]},16) OR SHL({values[2]},8) OR {values[3]};')
    if reader=='fast':
        words=['''        CopyStatus:=MEMORY_COPY(Payload,Offset+UDINT#4,W,UDINT#0,UDINT#64);
        IF CopyStatus<>0 THEN Error:=TRUE; Busy:=FALSE; RETURN; END_IF;
        IF NativeLittleEndian THEN''']
        for i in range(16):
            words.append(f'            W[{i}]:=SHR(W[{i}],24) OR (SHR(W[{i}],8) AND DWORD#16#0000FF00) OR (SHL(W[{i}],8) AND DWORD#16#00FF0000) OR SHL(W[{i}],24);')
        words.append('        END_IF;')
    else:
        assert reader=='direct'
    schedule=[]
    for i in range(16,64):
        schedule.append(f'''    (* W{i} *)
        s0 := (SHR(W[{i-15}],7) OR SHL(W[{i-15}],25)) XOR (SHR(W[{i-15}],18) OR SHL(W[{i-15}],14)) XOR SHR(W[{i-15}],3);
        s1 := (SHR(W[{i-2}],17) OR SHL(W[{i-2}],15)) XOR (SHR(W[{i-2}],19) OR SHL(W[{i-2}],13)) XOR SHR(W[{i-2}],10);
        W[{i}] := TO_DWORD(TO_UDINT(W[{i-16}])+TO_UDINT(s0)+TO_UDINT(W[{i-7}])+TO_UDINT(s1));''')
    registers=list('abcdefgh'); rounds=[]
    def rotate(name,n):return f'(SHR({name},{n}) OR SHL({name},{32-n}))'
    for i,k in enumerate(K):
        a,b,c,d,e,f,g,h=registers
        rounds.append(f'''    (* Round {i}: rotated register names remove seven copy assignments. *)
    s1:={rotate(e,6)} XOR {rotate(e,11)} XOR {rotate(e,25)};
    t1:=TO_DWORD(TO_UDINT({h})+TO_UDINT(s1)+TO_UDINT(({e} AND {f}) XOR ((NOT {e}) AND {g}))+UDINT#{k}+TO_UDINT(W[{i}]));
    s0:={rotate(a,2)} XOR {rotate(a,13)} XOR {rotate(a,22)};
    t2:=TO_DWORD(TO_UDINT(s0)+TO_UDINT(({a} AND {b}) XOR ({a} AND {c}) XOR ({b} AND {c})));
    {d}:=TO_DWORD(TO_UDINT({d})+TO_UDINT(t1)); {h}:=TO_DWORD(TO_UDINT(t1)+TO_UDINT(t2));''')
        registers=[h,a,b,c,d,e,f,g]
    assert registers==list('abcdefgh')
    return template.replace('@@WORD_LOAD@@','\n'.join(words)).replace('@@SCHEDULE@@','\n'.join(schedule)).replace('@@ROUNDS@@','\n'.join(rounds))

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--write',action='store_true')
    args=ap.parse_args(); target=ROOT/'src/NG_StringSHA256.st'; result=generate()
    if args.write:target.write_text(result,encoding='utf-8')
    elif target.read_text(encoding='utf-8')!=result:raise SystemExit('Generated SHA differs; run --write and repeat native regression.')
    print('Generated SHA source is current.')
