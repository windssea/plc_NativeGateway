"""Read controller error evidence; never clear the controller log."""
import json
import probe_hmi_rsc as sdk
from hub_api import OUT
from PyPlcnextRsc.Arp.Services.NotificationLogger.Services import INotificationLoggerService,NotificationFilter,SortOrder
with sdk.Device('192.168.0.8') as device:
    service=INotificationLoggerService(device)
    query=NotificationFilter(StoredIdLowerLimit=0,StoredIdUpperLimit=0,NotificationNameRegExp='',SenderNameRegExp='',
        TimestampBefore='',TimestampAfter='',SeverityLowerLimit='',SeverityUpperLimit='')
    rows=service.QueryStoredNotifications([],query,200,SortOrder.TimestampDesc,'en')
    result=[str(r) for r in rows]
    (OUT/'plc-notifications.txt').write_text('\n'.join(result),encoding='utf8')
    print('\n'.join(result[:8]))

