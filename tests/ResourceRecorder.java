import com.phoenixcontact.plcnext.rsc.*;
import java.nio.file.*;
import java.time.Instant;
import com.phoenixcontact.plcnext.rsc.Arp.Device.Interface.Services.IDeviceStatusService;
public class ResourceRecorder {
 public static void main(String[] args) throws Exception {
  Path root=Path.of(args.length>0?args[0]:"D:/work/code/PLCnext-Engineer/tests/soak");
  Files.createDirectories(root);
  while(true) {
   try(Device d=new Device("192.168.0.8",41100,5000,true,null)) {
    d.connect();
    while(true) {
     DeviceStatus s=d.getDeviceStatus();
     if(s.getCpuLoad()==null || s.getMemoryUsage()==null)throw new java.io.IOException("Controller status unavailable; reconnecting");
     var actualVariant=new IDeviceStatusService(d.getRscClient()).getItem("Status.Memory.Usage.Percent.Actual");
     Object actual=actualVariant.isVoid()?null:actualVariant.getValue();
     String line=String.format(java.util.Locale.ROOT,"{\"receivedAt\":%.3f,\"source\":\"IDeviceStatusService\",\"cpuPercent\":%s,\"memoryUsagePercent\":%s,\"actualMemoryPercent\":%s,\"iecProgramPercent\":%s,\"iecDataPercent\":%s,\"temperatureC\":%s}",System.currentTimeMillis()/1000.0,s.getCpuLoad(),s.getMemoryUsage(),actual,s.getProgramMemoryUsage(),s.getDataMemoryUsage(),s.getBoardTemperature());
     Files.writeString(root.resolve("controller-resources.jsonl"),line+"\n",StandardOpenOption.CREATE,StandardOpenOption.APPEND);
     Files.writeString(root.resolve("controller-resources.tmp"),line);
     Files.move(root.resolve("controller-resources.tmp"),root.resolve("controller-resources.json"),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
     Thread.sleep(10000);
    }
   } catch(Exception e) {
    Files.writeString(root.resolve("resource-errors.log"),Instant.now()+" "+e.getClass().getSimpleName()+": "+e.getMessage()+"\n",StandardOpenOption.CREATE,StandardOpenOption.APPEND);
    Thread.sleep(10000);
   }
  }
 }
}
