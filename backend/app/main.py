"""FastAPI 進入點：建 app、掛 middleware、掛 router。

這個檔案要保持很短。任何「做事」的程式碼都屬於 routers/services/repositories
其中一層，不屬於這裡。
"""

import ipaddress

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from . import config
from .routers import api, hook

app = FastAPI(title="session-remote")

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 聽的是 0.0.0.0（手機從 Tailscale 進來），所以只放行本機與 tailnet 的位址
_ALLOWED = [ipaddress.ip_network(n) for n in ("127.0.0.0/8", "::1/128", "100.64.0.0/10", "fd7a:115c:a1e0::/48")]


@app.middleware("http")
async def only_local_and_tailnet(request: Request, call_next):
    host = request.client.host if request.client else ""
    try:
        ok = any(ipaddress.ip_address(host) in n for n in _ALLOWED)
    except ValueError:
        ok = False
    if not ok:
        return JSONResponse({"detail": "只接受本機與 Tailscale 連線"}, status_code=403)
    return await call_next(request)


@app.get("/health")
def health():
    from .repositories import apns, iterm
    return {"ok": True, "iterm": iterm.is_running(), "push": apns.configured(), "token_set": bool(config.TOKEN)}


app.include_router(hook.router)
app.include_router(api.router)

if config.FAKE:
    from .routers import fake
    app.include_router(fake.router)
