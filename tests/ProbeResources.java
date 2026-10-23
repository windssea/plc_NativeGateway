import com.phoenixcontact.plcnext.rsc.*;
public class ProbeResources {
 public static void main(String[] args) throws Exception {
  try(Device d=new Device("192.168.0.8",41100,5000,true,null)) {
   d.connect(); System.out.println(d.getDeviceStatus());
   var f=d.readFile(0,"/proc/meminfo"); System.out.println("FILE:"+f.getError()+"="+new String(f.getStream().getValue()));
  }
 }
}
