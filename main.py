import asyncio
import json
import os
import uuid

import uvicorn
import websockets
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

load_dotenv()

MODEL_ID = "Voxtral-Mini-4B-Realtime-2602"
FORWARD_MESSAGE_TYPES = {
    "conversation.item.create",
    "conversation.item.delete",
    "session.updated",
    "response.stop",
}

app = FastAPI(
    title="Voxtral Realtime API",
    description="API compatible OpenAI Realtime pour Voxtral-Mini-4B-Realtime-2602",
    version="1.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class WebsocketConnectionManager:
    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}
        self.connection_sessions: dict[WebSocket, str] = {}

    async def connect(self, websocket: WebSocket) -> str:
        session_id = f"session_{uuid.uuid4()}"
        await websocket.accept()
        self.active_connections[session_id] = websocket
        self.connection_sessions[websocket] = session_id
        return session_id

    def disconnect(self, websocket: WebSocket) -> None:
        session_id = self.connection_sessions.pop(websocket, None)
        if session_id:
            self.active_connections.pop(session_id, None)

    async def send_to_session(self, session_id: str, message: dict) -> None:
        connection = self.active_connections.get(str(session_id))
        if connection is not None:
            await connection.send_json(message)


manager = WebsocketConnectionManager()


def get_realtime_ws_uri() -> str:
    return f"ws://localhost:{os.getenv('REALTIME_PORT', '9000')}"


@app.get("/")
async def root():
    return {
        "message": "Voxtral Realtime API",
        "version": app.version,
        "endpoints": {"realtime": "/v1/realtime"},
    }


@app.websocket("/v1/realtime")
async def realtime_endpoint(websocket: WebSocket):
    """Endpoint WebSocket pour l'API Realtime compatible OpenAI."""
    session_id = await manager.connect(websocket)

    try:
        await websocket.send_json({"type": "session.created", "session": {"id": session_id}})

        while True:
            data = await websocket.receive_json()
            message_type = data.get("type")

            if message_type == "session.created":
                continue
            if message_type == "input_audio_buffer.append":
                await handle_input_audio(websocket, data)
                continue
            if message_type == "response.create":
                await handle_response_create(websocket, data)
                continue
            if message_type in FORWARD_MESSAGE_TYPES:
                await manager.send_to_session(session_id, data)
                continue
            if message_type == "disconnect":
                break

            await websocket.send_json(
                {
                    "type": "error",
                    "error": {
                        "type": "invalid_request_error",
                        "message": f"Unsupported message type: {message_type}",
                    },
                }
            )

    except WebSocketDisconnect:
        print(f"Client {session_id} disconnected")
    except Exception as exc:  # noqa: BLE001
        print(f"Error: {exc}")
        await websocket.send_json(
            {
                "type": "error",
                "error": {
                    "type": "internal_server_error",
                    "message": str(exc),
                },
            }
        )
    finally:
        manager.disconnect(websocket)


async def handle_input_audio(websocket: WebSocket, data: dict):
    """Gère l'ajout de l'audio en entrée."""
    await websocket.send_json({"type": "input_audio_buffer.speech_started"})

    try:
        async with websockets.connect(get_realtime_ws_uri()) as ws:
            await ws.send(
                json.dumps(
                    {
                        "type": "input_audio_buffer.append",
                        "audio": data.get("audio", []),
                    }
                )
            )
            response_data = json.loads(await ws.recv())

            if response_data.get("type") == "response.output_audio.done":
                transcript = data.get("audio_transcript", "")
                await websocket.send_json(
                    {
                        "type": "response.audio_transcript.delta",
                        "transcript": transcript,
                        "audio_transcript": transcript,
                    }
                )

    except Exception as exc:  # noqa: BLE001
        print(f"Audio processing error: {exc}")


async def handle_response_create(websocket: WebSocket, data: dict):
    """Gère la création de réponse."""
    modalities = data.get("modalities", ["audio"])
    model = data.get("model", MODEL_ID)
    user_input = data.get("input", "")

    await websocket.send_json(
        {
            "type": "response.created",
            "response_id": f"resp_{id(websocket)}",
            "status": "in_progress",
            "created_at": "now",
            "user_id": id(websocket),
            "model": model,
            "instructions": modalities,
        }
    )

    try:
        async with websockets.connect(get_realtime_ws_uri()) as ws:
            await ws.send(
                json.dumps(
                    {
                        "type": "response.create",
                        "modalities": modalities,
                        "input": user_input,
                    }
                )
            )

            while True:
                response_data = json.loads(await ws.recv())
                event_type = response_data.get("type")

                if event_type == "response.audio_transcript.delta":
                    await websocket.send_json(
                        {
                            "type": "conversation.item.input_audio_transcription.completed",
                            "item": {
                                "id": f"item_{id(websocket)}",
                                "input_audio_transcription": {
                                    "type": "transcript",
                                    "transcript": response_data.get("transcript", ""),
                                },
                            },
                        }
                    )
                elif event_type == "response.audio.done":
                    response_data["event_id"] = "event_1"
                    await websocket.send_json(response_data)
                    break

    except Exception as exc:  # noqa: BLE001
        print(f"Response creation error: {exc}")
        await websocket.send_json(
            {
                "type": "error",
                "error": {
                    "type": "api_error",
                    "message": str(exc),
                },
            }
        )


@app.get("/v1/models")
async def list_models():
    """Liste les modèles disponibles."""
    return {
        "object": "list",
        "data": [
            {
                "id": MODEL_ID,
                "object": "model",
                "created": int(asyncio.get_event_loop().time()),
                "owned_by": "mistralai",
            }
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(data: dict):
    """Endpoint backward compatible pour chat completions."""
    model = data.get("model", MODEL_ID)
    messages = data.get("messages", [])
    messages_text = "\n".join([f"{msg['role']}: {msg['content']}" for msg in messages])

    try:
        async with websockets.connect(get_realtime_ws_uri()) as ws:
            await ws.send(
                json.dumps(
                    {
                        "type": "response.create",
                        "modalities": ["text"],
                        "input": messages_text,
                    }
                )
            )

            response_data = json.loads(await ws.recv())

            if response_data.get("type") == "response.content.delta":
                return JSONResponse(
                    {
                        "id": f"chatcmpl_{id(data)}",
                        "object": "chat.completion",
                        "created": int(asyncio.get_event_loop().time()),
                        "model": model,
                        "choices": [
                            {
                                "index": 0,
                                "message": {
                                    "role": "assistant",
                                    "content": response_data.get("delta", {}).get("content", ""),
                                },
                                "finish_reason": "stop",
                            }
                        ],
                    }
                )

            return JSONResponse({"error": "No response received"})

    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc))


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    host = os.getenv("HOST", "0.0.0.0")

    print(f"Starting Voxtral Realtime API on {host}:{port}")
    print(f"Model: {os.getenv('MODEL_ID', 'mistralai/Voxtral-Mini-4B-Realtime-2602')}")
    print(f"Device: {os.getenv('DEVICE', 'cuda:0')}")

    uvicorn.run(app, host=host, port=port)
