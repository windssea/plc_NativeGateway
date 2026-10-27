"""Call the installed PLCnext MCP through a fresh stdio session.

Uses public MCP tools only. Requests/results are explicit local JSON files;
no RSC implementation, private server API, or approval-file editing lives here.
"""
import argparse
import asyncio
from datetime import timedelta
import json
import os
from pathlib import Path
import sys

from mcp import ClientSession,StdioServerParameters
from mcp.client.stdio import stdio_client


def result_data(result):
    if result.structuredContent is not None:return result.structuredContent
    message='\n'.join(c.text for c in result.content if c.type=='text')
    try:return json.loads(message)
    except (ValueError,TypeError):return dict(error=message)


async def main(args):
    request=json.loads(args.request.read_text(encoding='utf-8-sig'))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    environment=dict(os.environ,PLCNEXT_MCP_WORKSPACE='D:/PLCnext-MCP-Workspace',
        PLCNEXT_ENGINEER_DIRECTORY='D:/Program Files/PHOENIX CONTACT/PLCnext Engineer 2026.0')
    parameters=StdioServerParameters(command=sys.executable,args=['-I','-m','plcnext_mcp.server'],env=environment)
    with args.output.with_suffix('.stderr.log').open('w',encoding='utf-8') as log:
        async with stdio_client(parameters,errlog=log) as (reader,writer):
            async with ClientSession(reader,writer,read_timeout_seconds=timedelta(seconds=600)) as client:
                await client.initialize()
                if request['tool']=='list_tools':
                    result=await client.list_tools()
                    data=dict(tools=[dict(name=t.name,description=t.description,inputSchema=t.inputSchema) for t in result.tools])
                    error=False
                else:
                    result=await client.call_tool(request['tool'],request.get('arguments',{}))
                    error=bool(result.isError)
                    data=result_data(result)
                    if request['tool'] in ('project_start_recovery_job','project_start_controller_control_job','project_start_instrumented_fault_job') and not error:
                        # Workers live in this MCP host. Closing stdio after
                        # "queued" would terminate the host and lose execution.
                        started=dict(data);previous=None
                        while data.get('status') in ('queued','running'):
                            await asyncio.sleep(2)
                            state=await client.call_tool('project_controller_operation_status',dict(
                                project_id=started['project_id'],operation_id=started['operation_id'],
                                expected_review_sha256=started['review_sha256'],include_result=True))
                            data=result_data(state)
                            error=bool(state.isError)
                            phase=(data.get('status'),data.get('phase'))
                            if phase!=previous:
                                print(json.dumps(dict(operationId=started['operation_id'],status=phase[0],phase=phase[1])),flush=True)
                                previous=phase
                            if error:break
                        data=dict(data,started_job=started)
                envelope=dict(transport='MCP stdio fresh session',tool=request['tool'],isError=error,result=data)
                args.output.write_text(json.dumps(envelope,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
                summary={k:v for k,v in data.items() if k in ('status','compiled','project_id','project_sha256','project_path','revision','job_id','package_job_id','review_id','review_sha256','plan_id','plan_sha256','operation_id','report_path','error','message')}
                if request['tool']=='list_tools':summary=dict(count=len(data['tools']),names=[t['name'] for t in data['tools']])
                print(json.dumps(dict(output=str(args.output),isError=error,summary=summary),ensure_ascii=False),flush=True)
    return 2 if error else 0


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    raise SystemExit(asyncio.run(main(parser.parse_args())))
