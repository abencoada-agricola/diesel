import { appShell } from "../../lib/app-shell";
import { access } from "../../lib/access";
export async function GET(request: Request){const user=await access();if(!user)return Response.redirect(new URL("/signin-with-chatgpt?return_to=/admin",request.url),302);if(user.role!=="admin")return Response.redirect(new URL("/campo",request.url),302);return new Response(appShell(),{headers:{"Content-Type":"text/html; charset=utf-8","Cache-Control":"no-store"}})}
