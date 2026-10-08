import QRCode from 'qrcode';
import {fleetQr} from '../mobile/fleet-qr.js';
export const makeFleetQr=fleet=>QRCode.toDataURL(fleetQr(fleet),{width:480,margin:4,errorCorrectionLevel:'M',color:{dark:'#000000',light:'#ffffff'}});

export {defaultMeters,meterLabels} from '../mobile/fleet-qr.js';
