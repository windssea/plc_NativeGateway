import zipfile,re,collections
for path in ['reference/IIoT_5_3_EXA.pcwex','reference/NativeGateway.before-implementation.pcwex']:
    z=zipfile.ZipFile(path);c=collections.Counter()
    for n in z.namelist():
        if not n.endswith('.hmipagedef'):continue
        s=z.read(n).decode('utf-8',errors='ignore')
        c.update(re.findall(r'xsi:type="([^"]*Dynamic)"',s))
        for m in re.finditer(r'<Dynamic[^>]*(?:Visible|Visibility)[\s\S]*?</Dynamic>',s):print(n,m.group()[:2000])
    print(path,c)
