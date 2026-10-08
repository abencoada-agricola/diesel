export function fleetQr(fleet){return JSON.stringify({app:'abencoada-diesel',v:1,fleet:String(fleet.id),name:String(fleet.name),type:String(fleet.type)})}
export function readFleetQr(text){
 let data;try{data=JSON.parse(String(text))}catch{throw Error('QR Code inválido. Use o código gerado pela administração.')}
 if(data?.app!=='abencoada-diesel'||data.v!==1||typeof data.fleet!=='string'||!/^[A-Za-z0-9_.-]{1,30}$/.test(data.fleet))throw Error('QR Code inválido. Use o código gerado pela administração.');
 return data.fleet.toUpperCase();
}
export const defaultMeters=type=>type==='Caminhão'?{km:true,engine:false,elevator:false}:type==='Colhedora'?{km:false,engine:true,elevator:true}:type==='Trator'?{km:false,engine:true,elevator:false}:{km:true,engine:false,elevator:false};
export const meterLabels={km:'KM',engine:'HORÍMETRO MOTOR',elevator:'HORÍMETRO ELEVADOR'};
