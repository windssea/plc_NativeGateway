from pathlib import Path
from xml.etree import ElementTree as E
root=E.fromstring(Path('reference/NativeGateway.DataList.dl').read_bytes())
for row in root.findall('.//Datum'):
    if any(n.text=='GW_Load' for n in row.findall('./Role/Name')):print(E.tostring(row,encoding='unicode'))
