from fastapi import FastAPI

app = FastAPI(title="FastAPI in CodingBooth")


@app.get("/")
def index():
    return {"message": "Hello from FastAPI in CodingBooth!", "docs": "/docs"}


@app.get("/api/ping")
def ping():
    return {"status": "ok", "message": "pong"}
