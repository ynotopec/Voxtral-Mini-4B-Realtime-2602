#!/usr/bin/env python3
"""
Client d'exemple pour l'API Voxtral Realtime
"""
import asyncio
import json
import websockets
import base64
import numpy as np


async def example_text_mode():
    """Exemple de communication en mode texte"""
    uri = "ws://localhost:8000/v1/realtime"
    model_id = "Voxtral-Mini-4B-Realtime-2602"

    print("📡 Connexion WebSocket au serveur Voxtral Realtime...")

    async with websockets.connect(uri) as ws:
        while True:
            try:
                response = await ws.recv()
                data = json.loads(response)

                print(f"\n📩 Réponse: {json.dumps(data, indent=2, ensure_ascii=False)}")

                if data.get("type") == "session.created":
                    print("\n✅ Session créée!")
                    print("\n📤 Envoi d'une requête de transcription...")

                    ws.send(json.dumps({
                        "type": "response.create",
                        "model": model_id,
                        "input": "Bonjour, comment allez-vous aujourd'hui?",
                        "modalities": ["text"]
                    }))

                elif data.get("type") == "response.output_audio_done":
                    print("\n✅ Réponse terminée!")
                    ws.send(json.dumps({
                        "type": "response.stop"
                    }))

                elif data.get("type") == "error":
                    print(f"\n❌ Erreur: {data.get('error', {}).get('message')}")

                elif data.get("type") == "disconnect":
                    print("\n🔚 Déconnexion...")
                    break

            except websockets.exceptions.ConnectionClosed:
                print("\n🔌 Connexion fermée")
                break
            except Exception as e:
                print(f"\n❌ Erreur: {e}")
                break


async def example_audio_mode():
    """Exemple de communication en mode audio"""
    uri = "ws://localhost:8000/v1/realtime"
    model_id = "Voxtral-Mini-4B-Realtime-2602"

    print("📡 Connexion WebSocket pour le mode audio...")

    async with websockets.connect(uri) as ws:
        while True:
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=5.0)
                data = json.loads(response)

                print(f"\n📩 Session: {data.get('type')}")

                if data.get("type") == "session.created":
                    print("✅ Session audio créée!")

                    sample_rate = 16000
                    duration = 3.0
                    n_samples = int(sample_rate * duration)

                    t = np.linspace(0, duration, n_samples, endpoint=False)
                    audio_data = np.sin(2 * np.pi * 440 * t) * 0.5

                    audio_bytes = bytearray(audio_data, dtype=np.int16)
                    audio_base64 = base64.b64encode(audio_bytes).decode('utf-8')

                    print("📤 Envoi d'audio de test...")
                    ws.send(json.dumps({
                        "type": "input_audio_buffer.append",
                        "audio": audio_base64
                    }))

                    ws.send(json.dumps({
                        "type": "response.create",
                        "model": model_id,
                        "input": "",
                        "modalities": ["audio"]
                    }))
                    break

            except asyncio.TimeoutError:
                print("\n⏱️ Timeout: Vérifiez si le serveur est démarré")
                break
            except Exception as e:
                print(f"\n❌ Erreur: {e}")
                break

        while True:
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=10.0)
                data = json.loads(response)

                print(f"\n📩 Event: {data.get('type')}")
                print(json.dumps(data, indent=2, ensure_ascii=False))

                if data.get("type") in ["response.audio_done", "response.stop"]:
                    print("\n✅ Session audio terminée")
                    break

            except asyncio.TimeoutError:
                print("\n⏱️ Timeout")
                break
            except Exception as e:
                print(f"\n❌ Erreur: {e}")
                break


async def example_streaming_audio():
    """Exemple de streaming audio en temps réel"""
    uri = "ws://localhost:8000/v1/realtime"
    model_id = "Voxtral-Mini-4B-Realtime-2602"

    print("📡 Connexion WebSocket pour streaming audio...")

    async with websockets.connect(uri) as ws:
        while True:
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=3.0)
                data = json.loads(response)

                if data.get("type") == "session.created":
                    print("✅ Session prête pour le streaming!")
                    break

            except asyncio.TimeoutError:
                print("🔴 Attente de session...")
                continue

        print("\n🎵 Démarrage du streaming audio (appuyez sur Ctrl+C pour arrêter)...\n")

        sample_rate = 16000
        frequency = 440
        duration = 0.1
        chunk_size = int(sample_rate * duration) // 4

        try:
            for i in range(10):
                print(f"🔊 Envoi segment {i+1}/10...")

                t = np.linspace(0, duration, chunk_size, endpoint=False)
                audio_data = np.sin(2 * np.pi * frequency * t) * 0.5
                audio_bytes = bytearray(audio_data, dtype=np.int16)
                audio_base64 = base64.b64encode(audio_bytes).decode('utf-8')

                ws.send(json.dumps({
                    "type": "input_audio_buffer.append",
                    "audio": audio_base64
                }))

                await asyncio.sleep(0.5)

                try:
                    response = await asyncio.wait_for(ws.recv(), timeout=1.0)
                    data = json.loads(response)
                    print(f"📩 Réception: {data.get('type')}")
                except asyncio.TimeoutError:
                    pass

            print("\n✅ Streaming terminé!")
            ws.send(json.dumps({
                "type": "response.stop"
            }))

        except KeyboardInterrupt:
            print("\n🔇 Arrêt du streaming...")
            ws.send(json.dumps({
                "type": "disconnect"
            }))


async def main():
    print("""
╔══════════════════════════════════════════════════════════╗
║       Voxtral Realtime API - Client d'Exemple           ║
╚═════════════════════════════════════════════════════════╝

Options:
1. Mode texte
2. Mode audio
3. Streaming audio en continu
4. Quitter

""")
    while True:
        choice = input("\n🔍 Choisissez une option [1-4]: ").strip()
        if choice == "1":
            print("\n▶️ Démarrage en mode texte...\n")
            await example_text_mode()
        elif choice == "2":
            print("\n▶️ Démarrage en mode audio...\n")
            await example_audio_mode()
        elif choice == "3":
            print("\n▶️ Démarrage du streaming audio...\n")
            await example_streaming_audio()
        elif choice == "4":
            print("\n👋 Au revoir!")
            break
        else:
            print("❌ Option invalide, essayez encore.")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🔚 Exemple terminé")