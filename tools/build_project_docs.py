"""Offline project documentation. Does not connect to or mutate the PLC/broker."""
from pathlib import Path
from copy import deepcopy
from datetime import datetime
from html import escape
import json
import re
import math

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'
EXAMPLES = DOCS / 'examples'
OUT = ROOT / 'output/pdf'
TMP = ROOT / 'tmp/pdfs'
for directory in (EXAMPLES, OUT, TMP, DOCS / 'assets'):
    directory.mkdir(parents=True, exist_ok=True)


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def examples():
    real = json.loads((ROOT / 'tests/config-soak-104.json').read_text(encoding='utf-8-sig'))
    device = deepcopy(real['config']['devices'][0])
    device.update(deviceId='meter-01', name='Demo Meter 01')
    device['points'] = device['points'][:2]
    timestamp = 1792719125000
    common = dict(schemaVersion=1, gatewayId='PLC-DEMO-01', timestamp=timestamp)
    full = dict(**common, messageId='demo-set-1', configVersion=1,
                config=dict(enabled=True, report=dict(batchIntervalMs=1000, maxBatchPoints=32), devices=[device]))
    devices2 = deepcopy(device)
    devices2.update(deviceId='meter-02', name='Demo Meter 02')
    devices2['connection']['unitId'] = 2
    replacement = deepcopy(device)
    for point in replacement['points']:
        point.update(pollIntervalMs=1000, reportIntervalMs=1000)
    point_remove = deepcopy(replacement)
    point_remove['points'] = point_remove['points'][:1]

    def patch(version, message, base_message, operation, gateway=None):
        value = dict(**common, messageId=message, configVersion=version,
                     baseConfigVersion=version-1, baseMessageId=base_message, operations=operation)
        if gateway is not None:
            value['gateway'] = gateway
        return value

    fixtures = {
        'config-set-demo': ('configSet', full),
        'config-patch-add-demo': ('configPatch', patch(2, 'demo-add-2', 'demo-set-1',
              [dict(op='add', deviceId='meter-02', device=devices2)])),
        'config-patch-replace-demo': ('configPatch', patch(3, 'demo-replace-3', 'demo-add-2',
              [dict(op='replace', deviceId='meter-01', device=replacement)])),
        'config-patch-remove-demo': ('configPatch', patch(4, 'demo-remove-4', 'demo-replace-3',
              [dict(op='remove', deviceId='meter-02')])),
        'config-patch-remove-point-demo': ('configPatch', patch(5, 'demo-point-remove-5', 'demo-remove-4',
              [dict(op='replace', deviceId='meter-01', device=point_remove)])),
        'config-patch-gateway-demo': ('configPatch', patch(6, 'demo-gateway-6', 'demo-point-remove-5', [],
              dict(enabled=True, report=dict(batchIntervalMs=500, maxBatchPoints=16)))),
        'config-ack-demo': ('configAck', dict(**common, messageId='demo-set-1', configVersion=1,
              activeConfigVersion=1, status='APPLIED', errors=[])),
        'config-patch-ack-demo': ('configPatchAck', dict(**common, messageId='demo-remove-4', configVersion=4,
              activeConfigVersion=4, appliedConfigVersion=4, activeMessageId='demo-remove-4', status='APPLIED', errors=[])),
        'config-get-demo': ('configGet', dict(**common, messageId='demo-get-1', activeConfigVersion=6,
              sessionId='demo-session-1', activeMessageId='demo-gateway-6', configCapabilities=['devicePatchV1'])),
        'data-demo': ('data', dict(**common, messageId='demo-data-1', bootId='demo-boot-1', sequence=1,
              configVersion=1, values=[dict(deviceId='meter-01', pointId=p, value=v, quality='GOOD', timestamp=timestamp)
                                     for p, v in [('voltage', 230.1), ('current', 12.4)]])),
        'data-ack-demo': ('dataAck', dict(**common, messageId='demo-data-1', status='STORED', errors=[])),
    }
    for name, (_, value) in fixtures.items():
        dump(EXAMPLES / (name + '.json'), value)
    dump(EXAMPLES / 'manifest.json', {name + '.json': kind for name, (kind, _) in fixtures.items()})
    (EXAMPLES / 'README.txt').write_text('''NativeGateway 离线通信样例
全部使用隔离 gatewayId PLC-DEMO-01，不会自动发布，也不会修改 PLC-ENG-01。
JSON 时间戳是固定示例；实际发新命令需使用当前版本基线、新 messageId 和时间戳。
幂等重试应重发原始字节，不能更改 timestamp 后复用 messageId。

Topic 前缀：iot/v1/gateway/PLC-DEMO-01/
全量 config-set-demo.json -> config/set，QoS1，可 Retain。
增量以下依次 -> config/patch，QoS1，不 Retain；须等上一条 APPLIED：
 v2 config-patch-add-demo.json           新增 meter-02
 v3 config-patch-replace-demo.json       meter-01 两点周期改为 1000ms
 v4 config-patch-remove-demo.json        删除 meter-02 及其全部点位
 v5 config-patch-remove-point-demo.json  replace meter-01 完整点表，仅保留 voltage
 v6 config-patch-gateway-demo.json       修改网关组批参数
各版本 baseConfigVersion/baseMessageId 必须匹配实际活动状态。
增量 add/replace 携带完整设备对象，不是 JSON Merge Patch。

config-ack-demo.json / config-patch-ack-demo.json 为设备回执示例；
data-demo.json 为上行数据，data-ack-demo.json 为平台 STORED 回执。
config-get-demo.json 为设备请求平台同步当前配置的消息。
manifest.json 指定每个示例对应的参考协议校验类型。
validation.json 是离线 schema/语义校验结果，不是设备实测结果。
''', encoding='utf-8')
    return fixtures


def architecture():
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (1800, 1230), '#f5f8fc')
    draw = ImageDraw.Draw(image)
    fontpath = 'C:/Windows/Fonts/simhei.ttf'
    def font(size):
        return ImageFont.truetype(fontpath, size)
    def label(x, y, text, size=28, color='#20334a'):
        draw.multiline_text((x, y), text, font=font(size), fill=color, spacing=12)
    def box(rect, title, lines, color='#ffffff', border='#b9cad9', title_size=30):
        draw.rounded_rectangle(rect, radius=18, fill=color, outline=border, width=3)
        x, y, _, _ = rect
        label(x+24, y+22, title, title_size)
        label(x+24, y+78, lines, 25)
    def arrow(a, b, text='', xy=None, color='#2976aa'):
        draw.line([a, b], fill=color, width=5)
        angle = math.atan2(b[1]-a[1], b[0]-a[0])
        draw.polygon([b, (b[0]-19*math.cos(angle-.48), b[1]-19*math.sin(angle-.48)),
                           (b[0]-19*math.cos(angle+.48), b[1]-19*math.sin(angle+.48))], fill=color)
        if text and xy:
            label(*xy, text, 23, color)
    label(50, 32, 'NativeGateway | 原生 IEC/ST + Web HMI', 45)
    label(52, 98, '控制器：AXC F 2152  192.168.0.8  /  程序：native-0.2.0', 27)
    box((50, 180, 510, 365), '远程平台 / MQTT 客户端', '配置全量、增删改、周期下发\n接收点值、幂等入库、业务 ACK')
    box((660, 180, 1120, 365), 'Docker MQTT broker', 'PC 192.168.0.5:1883\n转发消息与 retained 配置')
    box((1270, 180, 1750, 365), '浏览器 Web HMI', '设备 / 点位分页及增删改\n草稿、版本冲突、应用持久化')
    arrow((510, 270), (660, 270), 'MQTT', (545, 224))
    draw.rounded_rectangle((50, 465, 1750, 940), radius=22, fill='#e5f0f9', outline='#5e8fb4', width=4)
    label(75, 486, '2152 控制器：Main / 20 ms 周期任务，全部运行在 IEC/ST', 32)
    box((85, 565, 595, 735), 'NG_Mqtt + 配置事务', '解析 / 校验 / 版本及回放\nNG_Command / NG_CheckConfig')
    box((650, 565, 1155, 735), 'NG_HmiEdit / NG_Store', 'HMI 草稿 → 校验 → 双槽写入\n回读 SHA256 → 切换活动配置')
    box((1210, 565, 1715, 735), 'NG_Modbus × 50', '每设备 TCP 连接 / 台内逐点读\n解码、倍率、调度、质量码')
    box((85, 790, 900, 905), '点位到期 → 跨设备组批 → 16 批 RAM 队列', '最多 32 点/包；STORED 移除，未确认可重发', title_size=28)
    box((950, 790, 1715, 905), '本地双槽配置文件 /opt/plcnext/', 'v2-A.bin / v2-B.bin；含配置与 bootstrap', title_size=28)
    arrow((880, 365), (880, 465), 'MQTT QoS1 + JSON / config、data、ACK', (230, 402))
    arrow((1510, 365), (1510, 465), 'HTTPS :443 / HMI 标签', (1210, 402))
    arrow((595, 650), (650, 650))
    arrow((1155, 650), (1210, 650))
    box((50, 1030, 770, 1190), '局域网电表 / 本次 mock', '192.168.0.5:11502；Unit 1～50，各 5 点\nModbus TCP：只读 FC01 / 02 / 03 / 04')
    box((850, 1030, 1750, 1190), 'PC 独立测试与监测（不是 PLC 运行依赖）', 'wire 报文 / schema / 预期值 / STORED 模拟\nRSC CPU、内存每 10 秒；Web 探测每 15 秒')
    arrow((480, 940), (480, 1030), 'Modbus TCP', (540, 965))
    image.save(DOCS / 'assets/nativegateway-architecture.png')
    (DOCS / 'architecture.mmd').write_text('''flowchart TB
    Platform[远程平台：配置管理 / 数据入库 / ACK] <-->|MQTT QoS1 JSON| Broker[Docker broker 192.168.0.5:1883]
    Browser[浏览器 Web HMI] -->|HTTPS 443 / HMI 标签| Edit
    subgraph PLC[AXC F 2152 / 原生 IEC-ST / Main 20ms]
      Mqtt[NG_Mqtt] --> Parse[JSON / NG_Command / 校验与版本]
      Parse --> Store[NG_Store 双槽写入与 SHA256 回读]
      Edit[NG_HmiEdit 草稿与冲突检查] --> Store
      Store --> Active[活动配置：50设备 / 共享320点池]
      Active --> Modbus[NG_Modbus × 50 / 独立TCP / 台内逐点读取]
      Modbus --> Sample[数值 / 时间 / 质量 / 采集与上报调度]
      Sample --> Queue[跨设备组批 ≤32点 / 16批RAM队列]
      Queue --> Mqtt
      Mqtt -->|STORED移除 / 超时重发| Queue
    end
    Broker <-->|config / patch / data / ACK / heartbeat| Mqtt
    Modbus <-->|Modbus TCP FC1-4| Meters[电表 / mock 192.168.0.5:11502]
    PC[PC测试：报文与值校验 / RSC资源 / Web可用性] -.只读观测及业务ACK模拟.-> Broker
    PC -.资源采样.-> PLC
''', encoding='utf-8')


def update_markdown(fixtures):
    path = DOCS / 'NativeGateway-项目说明.md'
    text = path.read_text(encoding='utf-8')
    keys = {'CONFIG_SET_EXAMPLE': 'config-set-demo', 'CONFIG_REMOVE_EXAMPLE': 'config-patch-remove-demo',
            'CONFIG_ACK_EXAMPLE': 'config-ack-demo', 'DATA_EXAMPLE': 'data-demo', 'DATA_ACK_EXAMPLE': 'data-ack-demo'}
    for key, fixture in keys.items():
        value = json.dumps(fixtures[fixture][1], ensure_ascii=False, indent=2)
        text = text.replace('{{' + key + '}}', '```json\n' + value + '\n```')
    snapshot = json.loads((ROOT / 'tests/soak/summary.json').read_text(encoding='utf-8-sig'))
    when = datetime.fromtimestamp(snapshot['updatedAt']).strftime('%Y-%m-%d %H:%M:%S')
    a, c = snapshot['aggregate'], snapshot['counters']
    current = (f"快照时间：{when}（Asia/Shanghai），已运行约 {snapshot['elapsedSeconds']/60:.1f} 分钟，"
               f"记录器状态 {snapshot['mode']}。覆盖 {snapshot['coveredPoints']}/{snapshot['expectedPoints']} 点，"
               f"最近 20 秒更新 {snapshot['pointsSeenLast20s']} 点，累计 {c.get('uniqueBatches',0)} 个唯一批次、"
               f"{c.get('values',0)} 个点值，其中 GOOD 为 {c.get('quality_GOOD',0)}；"
               f"schemaErrors={c.get('schemaErrors',0)}、incorrectValues={c.get('incorrectValues',0)}。\n\n"
               f"该测试窗口 CPU 为 {a.get('cpuPercentMin')}%～{a.get('cpuPercentMax')}%，实际内存 "
               f"{a.get('actualMemoryPercentMin')}%～{a.get('actualMemoryPercentMax')}%，"
               f"IEC 程序内存 {a.get('iecProgramPercentMin')}%～{a.get('iecProgramPercentMax')}%，"
               f"IEC 数据内存 {a.get('iecDataPercentMin')}%～{a.get('iecDataPercentMax')}%；"
               f"队列峰值 {a.get('maxQueueBatches')} 批，丢弃峰值 {a.get('maxDroppedBatches')}，"
               f"最大点更新间隔 {a.get('maxPointGapSeconds',0):.3f} 秒。"
               "这是中途观察，不能作为完整 8 小时通过结论。")
    text = re.sub(r'<!-- SNAPSHOT_START -->.*?<!-- SNAPSHOT_END -->',
                  '<!-- SNAPSHOT_START -->\n' + current + '\n<!-- SNAPSHOT_END -->', text, flags=re.S)
    if '{{' in text:
        raise ValueError('Unresolved documentation placeholder')
    path.write_text(text, encoding='utf-8')
    return text, when


def pdf(text, when):
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak,
                                    Table, TableStyle, Image, Preformatted, CondPageBreak)
    from reportlab.platypus.tableofcontents import TableOfContents
    pdfmetrics.registerFont(TTFont('CN', 'C:/Windows/Fonts/simhei.ttf'))
    pdfmetrics.registerFont(TTFont('Mono', 'C:/Windows/Fonts/consola.ttf'))
    pdfmetrics.registerFontFamily('CN', normal='CN', bold='CN', italic='CN', boldItalic='CN')
    width, height = A4
    usable = width - 40*mm
    body = ParagraphStyle('Body', fontName='CN', fontSize=10, leading=16.8, spaceAfter=8,
                          textColor=colors.HexColor('#23354a'), wordWrap='CJK')
    styles = {
        'body': body,
        'h1': ParagraphStyle('H1', parent=body, fontSize=18, leading=25, spaceBefore=20, spaceAfter=12, keepWithNext=True, textColor=colors.HexColor('#124b70')),
        'h2': ParagraphStyle('H2', parent=body, fontSize=12.5, leading=19, spaceBefore=14, spaceAfter=7, keepWithNext=True, textColor=colors.HexColor('#186080')),
        'cell': ParagraphStyle('Cell', parent=body, fontSize=8.8, leading=13.5, spaceAfter=0),
        'th': ParagraphStyle('TH', parent=body, fontSize=9, leading=14, spaceAfter=0, textColor=colors.white),
        'code': ParagraphStyle('Code', fontName='Mono', fontSize=8, leading=10.5, spaceAfter=0, textColor=colors.HexColor('#20364b')),
        'caption': ParagraphStyle('Caption', parent=body, fontSize=8.5, leading=13, textColor=colors.HexColor('#607288')),
    }
    def markup(s):
        s = escape(s)
        s = re.sub(r'`([^`]+)`', r'<font color="#126789">\1</font>', s)
        s = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', s)
        return s
    def p(s, style='body'):
        return Paragraph(markup(s), styles[style])

    class Manual(BaseDocTemplate):
        def afterFlowable(self, flowable):
            if isinstance(flowable, Paragraph) and flowable.style.name == 'H1':
                title = flowable.getPlainText()
                key = 'section-' + title.split('.')[0]
                self.canv.bookmarkPage(key)
                self.canv.addOutlineEntry(title, key, 0, False)
                self.notify('TOCEntry', (0, title, self.page, key))

    def page(canvas, doc):
        canvas.saveState()
        if doc.page > 1:
            canvas.setStrokeColor(colors.HexColor('#d5e0ea'))
            canvas.line(20*mm, height-16*mm, width-20*mm, height-16*mm)
            canvas.setFont('CN', 8)
            canvas.setFillColor(colors.HexColor('#607288'))
            canvas.drawString(20*mm, height-13*mm, 'NativeGateway / 项目说明 v1.0')
        canvas.setFont('CN', 8)
        canvas.setFillColor(colors.HexColor('#607288'))
        canvas.drawString(20*mm, 12*mm, 'native-0.2.0  |  2026-10-23  |  工程与协议维护手册')
        canvas.drawRightString(width-20*mm, 12*mm, str(doc.page))
        canvas.restoreState()

    output = OUT / 'NativeGateway-项目说明.pdf'
    doc = Manual(str(output), pagesize=A4, leftMargin=20*mm, rightMargin=20*mm,
                 topMargin=23*mm, bottomMargin=22*mm, title='NativeGateway 项目说明', author='NativeGateway 工程文档')
    doc.addPageTemplates([PageTemplate(id='normal', frames=[Frame(20*mm, 22*mm, usable, height-45*mm,
                         leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)], onPage=page)])
    story = [Spacer(1, 25*mm), Paragraph('NativeGateway', ParagraphStyle('Cover', parent=body,
              fontSize=37, leading=46, textColor=colors.HexColor('#124b70'))),
              Paragraph('项目说明', ParagraphStyle('CoverCN', parent=body, fontSize=29, leading=40)),
              Spacer(1, 8*mm), p('原生 IEC/ST + PLCnext Engineer Web HMI'),
              p('Modbus TCP 采集 · MQTT 配置与上报 · 双槽持久化'), Spacer(1, 15*mm),
              p('AXC F 2152 / 192.168.0.8'), p('文档 v1.0  ·  程序 native-0.2.0  ·  配置 v104'),
              p('文档日期：2026-10-23'), Spacer(1, 17*mm),
              p('阅读范围'), p('架构、容量、HMI 操作、Modbus 与 MQTT 协议、增删配置样例、构建部署、恢复、联调证据与运行维护。'),
              Spacer(1, 8*mm), p('测试状态说明'),
              p('50 台 × 5 点的 8 小时测试正在进行。本文包含 ' + when + ' 的中途快照；HMI 短暂不可用事件已保留，尚无完整 8 小时通过结论。'),
              PageBreak(), Paragraph('目录', ParagraphStyle('Contents', parent=styles['h1']))]
    toc = TableOfContents()
    toc.levelStyles = [ParagraphStyle('TOC', parent=body, fontSize=10, leading=21, spaceAfter=3)]
    story.extend([toc, PageBreak()])
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.startswith('<!--'):
            i += 1
            continue
        if line.startswith('# '):
            # Cover metadata is already shown before the contents.
            while i < len(lines) and not lines[i].startswith('## '):
                i += 1
            continue
        if line.startswith('## '):
            story.extend([CondPageBreak(130), p(line[3:], 'h1')])
            i += 1
            continue
        if line.startswith('### '):
            story.append(p(line[4:], 'h2'))
            i += 1
            continue
        if line.startswith('!['):
            image_path = DOCS / re.search(r'\]\((.*?)\)', line).group(1)
            from PIL import Image as PILImage
            w, h = PILImage.open(image_path).size
            story.extend([Image(str(image_path), width=usable, height=usable*h/w),
                          p('图 1  系统职责与主要通信关系。可编辑源：docs/architecture.mmd', 'caption')])
            i += 1
            continue
        if line.startswith('```'):
            i += 1
            code = []
            while i < len(lines) and not lines[i].startswith('```'):
                raw = lines[i]
                chunk = ''
                for char in raw:
                    if pdfmetrics.stringWidth(chunk+char, 'Mono', 8) > usable-20:
                        code.append(chunk)
                        chunk = '    ' + char
                    else:
                        chunk += char
                code.append(chunk)
                i += 1
            # Split code only between lines, never create an unbreakable tall table.
            story.append(Spacer(1, 4))
            for raw in code:
                # CN supports the few Chinese comments / directory annotations.
                cs = styles['code']
                if any(ord(c) > 127 for c in raw):
                    cs = ParagraphStyle('CodeCN', parent=cs, fontName='CN')
                story.append(Preformatted(raw or ' ', cs))
            story.append(Spacer(1, 11))
            i += 1
            continue
        if line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                cells = [x.strip() for x in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-+:?', cell) for cell in cells):
                    rows.append(cells)
                i += 1
            n = len(rows[0])
            proportions = {2: [.31, .69], 3: [.27, .30, .43], 4: [.19, .31, .23, .27],
                           5: [.20, .17, .12, .17, .34]}.get(n, [1/n]*n)
            table = Table([[p(cell, 'th' if r == 0 else 'cell') for cell in row] for r, row in enumerate(rows)],
                          colWidths=[usable*x for x in proportions], repeatRows=1, hAlign='LEFT')
            table.setStyle(TableStyle([('BACKGROUND', (0,0), (-1,0), colors.HexColor('#1b587b')),
                           ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.HexColor('#f0f5f9'), colors.white]),
                           ('VALIGN', (0,0), (-1,-1), 'TOP'), ('LEFTPADDING',(0,0),(-1,-1),7),
                           ('RIGHTPADDING',(0,0),(-1,-1),7), ('TOPPADDING',(0,0),(-1,-1),6),
                           ('BOTTOMPADDING',(0,0),(-1,-1),6),
                           ('LINEBELOW',(0,0),(-1,0),.6,colors.HexColor('#1b587b')),
                           ('LINEBELOW',(0,1),(-1,-1),.3,colors.HexColor('#d7e2ec'))]))
            story.extend([table, Spacer(1, 10)])
            continue
        paragraph = line
        i += 1
        while i < len(lines) and lines[i].strip() and not lines[i].startswith(('#', '|', '```', '<!--', '![')):
            if re.match(r'^\d+\. ', lines[i]):
                break
            paragraph += ' ' + lines[i]
            i += 1
        story.append(p(paragraph))
    doc.multiBuild(story)
    return output


if __name__ == '__main__':
    fixtures = examples()
    architecture()
    content, snapshot_time = update_markdown(fixtures)
    output = pdf(content, snapshot_time)
    print(json.dumps({'markdown': str(DOCS / 'NativeGateway-项目说明.md'), 'pdf': str(output),
                      'examples': len(fixtures), 'snapshotTime': snapshot_time}, ensure_ascii=False))
