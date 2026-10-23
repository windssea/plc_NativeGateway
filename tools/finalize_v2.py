from pathlib import Path
p=Path(__file__).resolve().parents[1]/'src/Main.st'
s=p.read_text()
for name in ('MemoryValid','CpuValid','ProcessValid'):
    s=s.replace("TO_STRING(Resources."+name+",'')",'NG_Bool(Resources.'+name+')')
s=s.replace('    ELSIF HeartbeatPending THEN\n','    ELSIF HeartbeatPending THEN\n        QueueBytes := 0; FOR q := 1 TO 16 DO IF Outbox[q].MessageId <> \'\' THEN QueueBytes := QueueBytes+Outbox[q].Length; END_IF; END_FOR;\n')
s=s.replace(',"payloadBytes":0,"droppedBatches":',',"payloadBytes":\',TO_STRING(QueueBytes, \'{0:d}\'),\',"droppedBatches":')
p.write_text(s,encoding='utf-8')
print('Finalized resource JSON and queue byte metrics.')
