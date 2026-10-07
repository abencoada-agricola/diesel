import { appShell } from "../../lib/app-shell";
export async function GET(){return new Response(appShell(),{headers:{"Content-Type":"text/html; charset=utf-8","Cache-Control":"no-cache"}})}
