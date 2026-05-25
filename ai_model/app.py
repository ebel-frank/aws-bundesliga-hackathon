from __future__ import annotations

import json

from ai_core.lambda_handler import handler


try:
    from fastapi import FastAPI
    from fastapi.responses import JSONResponse
except Exception:  # FastAPI is optional so the core can run in Lambda or notebooks.
    FastAPI = None


if FastAPI:
    app = FastAPI(title="Live Prediction Arena AI")

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "live-prediction-arena-ai"}

    @app.post("/ai")
    def ai_endpoint(payload: dict):
        response = handler(payload)
        return JSONResponse(status_code=response["statusCode"], content=json.loads(response["body"]))

    @app.post("/ai/prediction-rounds")
    def generate_prediction_round(payload: dict):
        response = handler({"action": "generate_prediction_round", **payload})
        return JSONResponse(status_code=response["statusCode"], content=json.loads(response["body"]))

    @app.post("/ai/trivia-rounds")
    def generate_trivia_round(payload: dict):
        response = handler({"action": "generate_prediction_round", **payload})
        return JSONResponse(status_code=response["statusCode"], content=json.loads(response["body"]))

    @app.post("/ai/var-rounds")
    def generate_var_prediction_round(payload: dict):
        response = handler({"action": "generate_var_prediction_round", **payload})
        return JSONResponse(status_code=response["statusCode"], content=json.loads(response["body"]))

    @app.post("/ai/events/normalize")
    def normalize_event(payload: dict):
        response = handler({"action": "normalize_event", **payload})
        return JSONResponse(status_code=response["statusCode"], content=json.loads(response["body"]))

    @app.post("/ai/score-rounds")
    def score_round(payload: dict):
        response = handler({"action": "score_round", **payload})
        return JSONResponse(status_code=response["statusCode"], content=json.loads(response["body"]))
