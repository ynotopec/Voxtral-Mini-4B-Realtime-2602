import asyncio
import json
from typing import Optional, Union
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import os
from dotenv import load_dotenv
import websockets
import uvicorn
import uuid

load_dotenv()

app = FastAPI(
    title="Voxtral Realtime API",
    description="API compatible OpenAI Realtime pour Voxtral-Mini-4B-Realtime-2602",
    version="1.0.0"
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

    async def connect(self, websocket: WebSocket):
        session_id = f"session_{uuid.uuid4()}"
        await websocket.accept()
        self.active_connections[session_id] = websocket
        self.connection_sessions[websocket] = session_id
        return session_id

    def disconnect(self, websocket: WebSocket):
        session_id = self.connection_sessions.get(websocket)
        if session_id and session_id in self.active_connections:
            del self.active_connections[session_id]
        self.connection_sessions.pop(websocket, None)

    async def send_to_session(self, session_id: str, message: dict):
        session_id = str(session_id)
        if session_id in self.active_connections:
            connection = self.active_connections[session_id]
            await connection.send_json(message)

    async def send_to_connection(self, websocket: WebSocket, message: dict):
        await websocket.send_json(message)

    async def broadcast(self, message: dict):
        for connection in self.active_connections.values():
            await connection.send_json(message)


manager = WebsocketConnectionManager()


@app.get("/")
async def root():
    return {
        "message": "Voxtral Realtime API",
        "version": "1.0.0",
        "endpoints": {
            "realtime": "/v1/realtime"
        }
    }


@app.websocket("/v1/realtime")
async def realtime_endpoint(websocket: WebSocket):
    """
    Endpoint WebSocket pour l'API Realtime compatible OpenAI
    """
    session_id = None

    try:
        session_id = await manager.connect(websocket)
        await websocket.send_json({
            "type": "session.created",
            "session": {
                "id": session_id,
            }
        })

        while True:
            data = await websocket.receive_json()
            message_type = data.get("type")

            if message_type == "session.created":
                continue

            elif message_type == "input_audio_buffer.append":
                await handle_input_audio(websocket, data)

            elif message_type == "response.create":
                await handle_response_create(websocket, data, session_id)

            elif message_type == "conversation.item.create":
                await manager.send_to_session(session_id, data)

            elif message_type == "conversation.item.delete":
                await manager.send_to_session(session_id, data)

            elif message_type == "session.updated":
                await manager.send_to_session(session_id, data)

            elif message_type == "response.stop":
                await manager.send_to_session(session_id, data)

            elif message_type == "disconnect":
                break

    except WebSocketDisconnect:
        print(f"Client {session_id} disconnected")
    except Exception as e:
        print(f"Error: {e}")
        await websocket.send_json({
            "type": "error",
            "error": {
                "type": "internal_server_error",
                "message": str(e)
            }
        })
    finally:
        if session_id:
            manager.disconnect(websocket)


async def handle_input_audio(websocket: WebSocket, data: dict):
    """Gère l'ajout de l'audio en entrée"""
    audio_inputs = data.get("audio", [])

    await websocket.send_json({
        "type": "input_audio_buffer.speech_started"
    })

    try:
        conn = f"ws://localhost:{os.getenv('REALTIME_PORT', '9000')}"

        async with websockets.connect(conn) as ws:
            await ws.send(json.dumps({
                "type": "input_audio_buffer.append",
                "audio": audio_inputs
            }))

            response = await ws.recv()
            response_data = json.loads(response)

            if response_data.get("type") == "response.output_audio.done":
                await websocket.send_json({
                    "type": "response.audio_transcript.delta",
                    "transcript": data.get("audio_transcript", ""),
                    "audio_transcript": data.get("audio_transcript", "")
                })

    except Exception as e:
        print(f"Audio processing error: {e}")


async def handle_response_create(websocket: WebSocket, data: dict):
    """Gère la création de réponse"""
    instructions = data.get("modalities", ["audio"])
    model = data.get("model", "Voxtral-Mini-4B-Realtime-2602")
    input = data.get("input", "")

    response_data = {
        "type": "response.created",
        "response_id": f"resp_{id(websocket)}",
        "status": "in_progress",
        "created_at": "now",
        "user_id": id(websocket),
        "model": model,
        "instructions": instructions
    }

    await websocket.send_json(response_data)

    conn = f"ws://localhost:{os.getenv('REALTIME_PORT', '9000')}"

    try:
        async with websockets.connect(conn) as ws:
            await ws.send(json.dumps({
                "type": "response.create",
                "modalities": instructions,
                "input": input
            }))

            while True:
                response = await ws.recv()
                response_data = json.loads(response)

                if response_data.get("type") == "response.audio_transcript.delta":
                    await websocket.send_json({
                        "type": "conversation.item.input_audio_transcription.completed",
                        "item": {
                            "id": f"item_{id(websocket)}",
                            "input_audio_transcription": {
                                "type": "transcript",
                                "transcript": response_data.get("transcript", "")
                            }
                        }
                    })

                elif response_data.get("type") == "response.audio.done":
                    response_data["type"] = "response.audio.done"
                    response_data["event_id"] = "event_1"
                    await websocket.send_json(response_data)

    except Exception as e:
        print(f"Response creation error: {e}")
        await websocket.send_json({
            "type": "error",
            "error": {
                "type": "api_error",
                "message": str(e)
            }
        })


@app.get("/v1/models")
async def list_models():
    """Liste les modèles disponibles"""
    return {
        "object": "list",
        "data": [
            {
                "id": "Voxtral-Mini-4B-Realtime-2602",
                "object": "model",
                "created": int(asyncio.get_event_loop().time()),
                "owned_by": "mistralai"
            }
        ]
    }


@app.post("/v1/chat/completions")
async def chat_completions(data: dict):
    """Endpoint backward compatible pour chat completions"""
    model = data.get("model", "Voxtral-Mini-4B-Realtime-2602")
    messages = data.get("messages", [])
    messages_text = "\n".join([f"{msg['role']}: {msg['content']}" for msg in messages])

    try:
        conn = f"ws://localhost:{os.getenv('REALTIME_PORT', '9000')}"

        async with websockets.connect(conn) as ws:
            await ws.send(json.dumps({
                "type": "response.create",
                "modalities": ["text"],
                "input": messages_text
            }))

            response = await ws.recv()
            response_data = json.loads(response)

            if response_data.get("type") == "response.content.delta":
                return JSONResponse({
                    "id": f"chatcmpl_{id(data)}",
                    "object": "chat.completion",
                    "created": int(asyncio.get_event_loop().time()),
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "message": {
                                "role": "assistant",
                                "content": response_data.get("delta", {}).get("content", "")
                            },
                            "finish_reason": "stop"
                        }
                    ]
                })

            return JSONResponse({
                "error": "No response received"
            })

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    host = os.getenv("HOST", "0.0.0.0")

    print(f"Starting Voxtral Realtime API on {host}:{port}")
    print(f"Model: {os.getenv('MODEL_ID', 'mistralai/Voxtral-Mini-4B-Realtime-2602')}")
    print(f"Device: {os.getenv('DEVICE', 'cuda:0')}")

    uvicorn.run(
        app,
        host=host,
        port=port
    )