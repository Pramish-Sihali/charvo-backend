from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.routes import auth as auth_routes
from app.routes import orders as orders_routes
from app.routes import products as products_routes

settings = get_settings()

app = FastAPI(title="CharcoalX API", version="0.1.0")

origins = [o.strip() for o in settings.ALLOWED_ORIGINS.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", tags=["meta"])
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth_routes.router)
app.include_router(products_routes.router)
app.include_router(orders_routes.router)
