from pathlib import Path
P=Path(__file__).resolve().parents[1]/'src/NG_Store.st'
s=P.read_text()
s=s.replace('    Ready : BOOL;','    Ready : BOOL;\n    NeedsMigration : BOOL;')
s=s.replace('    Stage : INT;','    LegacyRecord : NG1_File;\n    Legacy : BOOL;\n    StateLength : UDINT;\n    d : INT;\n    p : INT;\n    idx : INT;\n    Stage : INT;')
s=s.replace("IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-B.bin'; END_IF;", "IF Legacy THEN\n    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-B.bin'; END_IF;\n    StateLength := SIZEOF(LegacyRecord.State);\nELSE\n    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-v2-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-v2-B.bin'; END_IF;\n    StateLength := SIZEOF(Record.State);\nEND_IF;")
s=s.replace('ReadFile(Execute := (Stage = 20) OR (Stage = 100), Handle := Handle, MaxLength := SIZEOF(Record), Buffer := Record);','IF Legacy THEN\n    ReadFile(Execute := Stage = 20, Handle := Handle, MaxLength := SIZEOF(LegacyRecord), Buffer := LegacyRecord);\nELSE\n    ReadFile(Execute := (Stage = 20) OR (Stage = 100), Handle := Handle, MaxLength := SIZEOF(Record), Buffer := Record);\nEND_IF;')
s=s.replace('CopyBytes(REQ := (Stage = 35) OR (Stage = 50) OR (Stage = 115), BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := SIZEOF(Record.State), BUFFER := Record.State, DST := Bytes);','IF Legacy THEN\n    CopyBytes(REQ := Stage = 35, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := StateLength, BUFFER := LegacyRecord.State, DST := Bytes);\nELSE\n    CopyBytes(REQ := (Stage = 35) OR (Stage = 50) OR (Stage = 115), BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := StateLength, BUFFER := Record.State, DST := Bytes);\nEND_IF;')
s=s.replace('Length := SIZEOF(Record.State), Buffer := Bytes','Length := StateLength, Buffer := Bytes')
s=s.replace('        Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(Record)) AND (Record.Magic = DWORD#16#4E475731) AND (Record.FormatVersion = 1);','        IF Legacy THEN Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(LegacyRecord)) AND (LegacyRecord.Magic = DWORD#16#4E475731) AND (LegacyRecord.FormatVersion = 1);\n        ELSE Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(Record)) AND (Record.Magic = DWORD#16#4E475732) AND (Record.FormatVersion = 2); END_IF;')
fields='deviceId name enabled host port unitId connectTimeoutMs requestTimeoutMs retryCount PointCount'.split()
migrate='''        IF Legacy THEN
            IF (Hash.Digest = LegacyRecord.Digest) AND (LegacyRecord.State.Generation > Active.Generation) THEN
                Active.Generation := LegacyRecord.State.Generation; Active.Bootstrap := LegacyRecord.State.Bootstrap;
                Active.ReplayIndex := LegacyRecord.State.ReplayIndex; Active.Requests := LegacyRecord.State.Requests;
                Active.Config.Version := LegacyRecord.State.Config.Version; Active.Config.MessageId := LegacyRecord.State.Config.MessageId;
                Active.Config.enabled := LegacyRecord.State.Config.enabled; Active.Config.batchIntervalMs := LegacyRecord.State.Config.batchIntervalMs;
                Active.Config.maxBatchPoints := LegacyRecord.State.Config.maxBatchPoints; Active.Config.DeviceCount := LegacyRecord.State.Config.DeviceCount;
                idx := 1;
                FOR d := 1 TO Active.Config.DeviceCount DO
'''
migrate+='\n'.join(f'                    Active.Config.Devices[d].{f} := LegacyRecord.State.Config.Devices[d].{f};' for f in fields)
migrate+='''
                    Active.Config.Devices[d].PointStart := idx;
                    FOR p := 1 TO Active.Config.Devices[d].PointCount DO Active.Config.Points[idx] := LegacyRecord.State.Config.Devices[d].Points[p]; idx := idx+1; END_FOR;
                END_FOR;
                Active.Config.PointCount := idx-1; NeedsMigration := TRUE;
            END_IF;
        ELSIF (Hash.Digest = Record.Digest) AND (Record.State.Generation > Active.Generation) THEN Active := Record.State; ActiveSlot := Slot; END_IF;'''
s=s.replace('        IF (Hash.Digest = Record.Digest) AND (Record.State.Generation > Active.Generation) THEN Active := Record.State; ActiveSlot := Slot; END_IF;',migrate)
s=s.replace('    ELSE Ready := TRUE; Busy := FALSE; Stage := 200; END_IF;','    ELSIF (Active.Generation = 0) AND NOT Legacy THEN Legacy := TRUE; Slot := 1; Stage := 10;\n    ELSE Ready := TRUE; Busy := FALSE; Stage := 200; END_IF;')
s=s.replace('(Record.FormatVersion = 1)','(Record.FormatVersion = 2)')
s=s.replace('Active := Record.State; ActiveSlot := Slot; Done := TRUE;','Active := Record.State; ActiveSlot := Slot; Done := TRUE; NeedsMigration := FALSE;')
s=s.replace('        Record.Magic := DWORD#16#4E475731; Record.FormatVersion := 1;','        Legacy := FALSE;\n        Record.Magic := DWORD#16#4E475732; Record.FormatVersion := 2;')
P.write_text(s,encoding='utf-8')
print('Store v2 + read-only v1 migration generated.')
