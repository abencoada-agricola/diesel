package br.com.abencoada.diesel;
import android.content.Context;
import androidx.annotation.NonNull;
import androidx.work.*;
import org.json.*;
import java.net.*;
import java.io.*;
import java.util.*;
public class OfflineSyncWorker extends Worker {
 public OfflineSyncWorker(@NonNull Context context,@NonNull WorkerParameters params){super(context,params);}
 @NonNull @Override public Result doWork(){synchronized(OfflineStore.LOCK){try{
  JSONObject state=OfflineStore.read(getApplicationContext());JSONArray queue=state.optJSONArray("queue");if(queue==null||queue.length()==0)return Result.success();
  if(!state.optString("url").equals("https://pqsbcwmtemlwvcpkcyum.supabase.co")||state.optString("token").isEmpty())return Result.failure();
  JSONArray remaining=new JSONArray(),acks=state.optJSONArray("acks"),errors=new JSONArray();if(acks==null)acks=new JSONArray();Set<String> blocked=new HashSet<>();boolean retry=false;
  for(int i=0;i<queue.length();i++){JSONObject record=queue.getJSONObject(i);String dependency=record.optString("mode").equals("recorder")?"local:"+record.optString("localCode")+":"+record.optString("materialCode"):"fleet:"+record.optString("fleet");if(record.has("error")||blocked.contains(dependency)){remaining.put(record);blocked.add(dependency);continue;}
   try{
    HttpURLConnection connection=(HttpURLConnection)new URL(state.getString("url")+"/rest/v1/rpc/diesel_device_submit").openConnection();connection.setRequestMethod("POST");connection.setConnectTimeout(15000);connection.setReadTimeout(15000);connection.setRequestProperty("Content-Type","application/json");connection.setRequestProperty("apikey",state.getString("apikey"));connection.setDoOutput(true);byte[] body=new JSONObject().put("device_token",state.getString("token")).put("payload",record).toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);connection.setFixedLengthStreamingMode(body.length);try(OutputStream out=connection.getOutputStream()){out.write(body);}int status=connection.getResponseCode();if(status>=500||status==429)throw new IOException("Retry");if(status!=200)throw new IOException("HTTP "+status);String response;try(InputStream in=connection.getInputStream()){ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[4096];int length;while((length=in.read(buffer))!=-1)bytes.write(buffer,0,length);response=bytes.toString("UTF-8");}finally{connection.disconnect();}JSONObject receipt=new JSONObject(response);
    if(receipt.has("error")){remaining.put(record);blocked.add(dependency);errors.put(new JSONObject().put("id",record.getString("id")).put("message",receipt.getString("error")).put("data",receipt).put("record",record.toString()));}
    else if(record.getString("id").equals(receipt.optString("id"))){acks.put(new JSONObject().put("id",record.getString("id")).put("userId",state.getString("userId")));}
    else throw new IOException("Unconfirmed receipt");
   }catch(Exception e){remaining.put(record);blocked.add(dependency);retry=true;}
  }
  state.put("queue",remaining);state.put("acks",acks);state.put("errors",errors);OfflineStore.write(getApplicationContext(),state);return retry?Result.retry():Result.success();
 }catch(Exception e){return Result.retry();}}}
}
