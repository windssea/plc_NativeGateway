"""Start only the existing Hub dev service, keeping credentials out of logs/arguments."""
from pathlib import Path
import os
import re
import subprocess
import json
import time
import socket

root=Path(__file__).resolve().parents[1]
hub=root.parent/'PLCnext-Hub-Backend'
out=root/'tests/hub-runtime'; out.mkdir(exist_ok=True)
try:
    with socket.create_connection(('127.0.0.1',8080),timeout=1):
        print('Port 8080 already listening; inspect existing service before starting another.')
        raise SystemExit(0)
except OSError:
    pass
skill=(hub/'.agents/skills/hub-dev-test/SKILL.md').read_text(encoding='utf-8')
env=os.environ.copy()
env['SPRING_DATASOURCE_PASSWORD']=re.search(r'User/password: `postgres` / `([^`]+)`',skill).group(1)
env['SPRING_DATA_REDIS_PASSWORD']=re.search(r'Redis is configured[^\n]*password `([^`]+)`',skill).group(1)
env['SPRING_DATASOURCE_URL']='jdbc:postgresql://69.230.197.241:6001/hub'
env['SPRING_DATASOURCE_USERNAME']='postgres'
env['SPRING_DATA_REDIS_HOST']='127.0.0.1'; env['SPRING_DATA_REDIS_PORT']='5001'
java=Path.home()/'.jdks/ms-21.0.12.1/bin/java.exe'
command=[str(java),'-jar',str(hub/'hub-admin/target/hub-admin-1.0.0-SNAPSHOT.jar'),'--spring.profiles.active=dev','--server.port=8080',
         '--mybatis-plus.configuration.log-impl=org.apache.ibatis.logging.nologging.NoLoggingImpl',
         '--plcnext.iot.diagnostics.enabled=true']
with (out/'backend.log').open('ab') as stream:
    process=subprocess.Popen(command,cwd=hub,env=env,stdout=stream,stderr=subprocess.STDOUT,
                             creationflags=subprocess.CREATE_NO_WINDOW|subprocess.CREATE_BREAKAWAY_FROM_JOB)
result={'pid':process.pid,'startedAt':time.time(),'port':8080,'profile':'dev','database':'shared development; test operations via isolated gateway identity only'}
(out/'backend-process.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
