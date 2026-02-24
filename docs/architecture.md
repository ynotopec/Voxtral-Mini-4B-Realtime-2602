# Architecture technique - Voxtral Realtime API

## 🏛️ Architecture globale du système

Vue d'ensemble hiérarchique:

### Niveaux de abstraction

```mermaid
graph LR
    L1[Application Layer<br/>Client Interface] --> L2[API Gateway Layer<br/>FastAPI/WS]
    L2 --> L3[Orchestration Layer<br/>Session Management]
    L3 --> L4[Realtime Engine<br/>vLLM Streaming]
    L4 --> L5[Model Layer<br/>Voxtral Model]
    L5 --> L6[Audio Processing<br/>Encoder/Decoder]
```

## 📐 Diagrammes architecturaux

### Architecture système en couches

```mermaid
flowchart TB
    subgraph Client_Side [Client Layer]
        A1[WebSocket Client]
        A2[HTTP Client]
        A3[Audio Input]
        A4[Text Input]
    end

    subgraph Gateway_Network [API Gateway Network]
        B1[FastAPI Server<br/>:8000]
        B2[WebSocket Manager<br/>Session Router]
        B3[REST Router<br/>/v1/*]
        B4[CORS Middleware]
        B5[Message Validator]
    end

    subgraph Processing_Core [Processing Core]
        C1[Request Manager]
        C2[Audiostream Processor]
        C3[Pipeline Orchestrator]
        C4[Response Assembler]
    end

    subgraph Runtime_Infrastructure [Runtime Infrastructure]
        D1[vLLM Engine<br/>:9000]
        D2[Mistral Common Utils]
        D3[Transformer Inference]
    end

    subgraph AI_Models [AI Models]
        E1[Language Model]
        E2[Audio Encoder]
        E3[Attention Mechanisms]
        E4[Sliding Window Attention]
    end

    subgraph Audio_Processing [Audio Processing]
        F1[Input Buffer]
        F2[Sample Converter]
        F3[Chunker]
        F4[Resampler]
    end

    subgraph Output_Layer [Output Layer]
        G1[Transcription Text]
        G2[Audio Output Stream]
        G3[WebSocket Sender]
        G4[JSON Response]
    end

    %% Connexions
    A1 -->|WebSocket| B2
    A4 -->|HTTP REST| B3
    B1 --> B4
    B4 --> B5
    B5 --> C1
    C1 --> C2
    C2 --> C3
    C3 --> D1
    D1 --> D2
    D2 --> D3
    D3 --> E1
    D3 --> E2
    E1 --> E3
    E1 --> E4
    C2 --> F1
    F1 --> F2
    F2 --> F3
    F3 --> F4
    C1 --> G1
    C1 --> G2
    G1 --> G3
    G2 --> G3

    %% Styling
    style B1 fill:#f9f9ff,stroke:#333
    style D1 fill:#fffff9,stroke:#333
    style E1 fill:#f9ffff,stroke:#333
    style F1 fill:#fffcf9,stroke:#333
    style G3 fill:#f9fffc,stroke:#333
```

### Flux de traitement WebSocket

```mermaid
sequenceDiagram
    participant Client
    participant API
    participant Manager
    participant Processor
    participant vLLM

    %% Initialisation
    Client->>API: CONNECT /v1/realtime
    API->>Manager: New Session
    Manager->>Client: session.created

    %% Input Audio
    rect rgb(250, 240, 240)
        Note over Client: Envoi d'audio
        Client->>API: input_audio_buffer.append(audio_data)
        API->>Processor: Validate & Process
        Processor->>vLLM: Forward Audio Chunk
    end

    %% Processing vLLM
    rect rgb(240, 250, 240)
        Note over vLLM: Encodage & Streaming
        vLLM->>vLLM: Audio Encoder Processing
        vLLM->>vLLM: Language Model Inference
        vLLM->>vLLM: Generate Tokens
    end

    %% Response Delivery
    rect rgb(240, 240, 255)
        Note over vLLM, API: Stream generation
        loop Streaming Loop
            vLLM-->>API: response.audio.delta
            API-->>Client: response.audio_transcript.delta
        end
        vLLM-->>API: response.audio_done
        API-->>Client: response.output_audio_done
    end

    %% Cleanup
    Client->>API: disconnect
    API->>Manager: Close Session
```

### Architecture du modèle Voxtral

```mermaid
flowchart TB
    subgraph Realtime_Architecture [Voxtral Realtime Architecture]
        direction TB

        subgraph Audio_In_Audio_Input [Audio Input Pipeline]
            A1[Raw Audio Input<br/>16kHz PCM]
            A2[Preprocessing<br/>Normalization]
            A3[Chunking<br/>~80ms/tokens]
            A4[Causal Encoder<br/>Streaming]
        end

        subgraph Language_Model [Language Model]
            L1[Linear Projection<br/>3.4B Parameters]
            L2[Positional Embeddings]
            L3[Sliding Window Attention<br/>Infinite Streaming]
            L4[Feed-forward Layers]
        end

        subgraph Audio_Output [Audio Output]
            D1[Output Token Stream]
            D2[Decoder]
            D3[Post-processing]
            D4[Transcription Output]
        end

        A3 -->|Audio Features| A4
        A4 -->|Stream| L1
        L1 -->|Context| L3
        L3 -->|Hidden States| L1
        L1 -->|Embeddings| D1
        D1 --> D2
        D2 --> D3
        D3 --> D4
    end

    %% Annotations
    style A1 fill:#fff0f0,stroke:#e00
    style A4 fill:#f0f0ff,stroke:#00e
    style L1 fill:#f0fff0,stroke:#0a0
    style D4 fill:#fff0ff,stroke:#e0e
```

### Scalabilité et load balancing

```mermaid
flowchart LR
    subgraph Clients [Client Layer]
        C1[Browser 1]
        C2[Mobile App]
        C3[Desktop App]
        C4[IoT Device]
    end

    subgraph LB_Nginx [Load Balancer]
        LB1[Nginx/HAProxy<br/>Reverse Proxy]
    end

    subgraph Gateway_Cluster [API Gateway Cluster]
        G1[API Node 1<br/>:8000]
        G2[API Node 2<br/>:8001]
        G3[API Node 3<br/>:8002]
    end

    subgraph Worker_ThreadPool [Worker Thread Pools]
        W1[Thread Pool 1<br/>WebSocket]
        W2[Thread Pool 2<br/>HTTP REST]
        W3[Thread Pool 3<br/>Message Queue]
    end

    C1 --> C2 --> C3 --> C4 --> LB_Nginx
    LB_Nginx --> G1
    LB_Nginx --> G2
    LB_Nginx --> G3
    G1 --> W1
    G2 --> W2
    G3 --> W3
```

### Flux de données end-to-end

```mermaid
graph LR
    subgraph Input_End [Input Layer]
        A1[Audio Stream<br/>16kHz PCM]
        A2[Text Input<br/>Prompt]
    end

    subgraph Processing_Middle [Processing Middle]
        B1[Validation]
        B2[Chunking]
        B3[Encoding]
        B4[Inference]
    end

    subgraph Output_End [Output Layer]
        C1[Transcription<br/>Text]
        C2[Audio Output<br/>Streaming]
    end

    A1 --> B2
    A2 --> B1
    B1 --> B2
    B2 --> B3
    B3 --> B4
    B4 --> C1
    B4 --> C2

    %% Timeline
    A1 ==|16kHz|→ B2
    B2 ==|80ms/token|→ B3
    B3 ==|Parallel|→ B4
    B4 ==|Streaming|→ C1
    B4 ==|Chunking|→ C2

    %% Styling
    style A1 fill:#ffe0e0,stroke:#f00
    style B4 fill:#e0ffe0,stroke:#0a0
    style C1 fill:#ffe0ff,stroke:#f0f
    style C2 fill:#e0ffff,stroke:#0ff
```

## 🔧 Composants détaillées

### FastAPI Websocket API

#### Endpoints WebSocket

| Endpoint | Méthode | Fonctionnement | Compatibilité |
|----------|---------|---------------|---------------|
| `/v1/realtime` | WebSocket | Streaming bidirectionnel | OpenAI Realtime API |
| `session.created` | Event | Notification session initialisée | Native |
| `input_audio_buffer.append` | Event | Ajout audio en entrée | OpenAI compatible |
| `response.create` | Event | Début génération réponse | OpenAI compatible |
| `audio.done` | Event | Fin audio réponse | Native |
| `disconnect` | Event | Déconnexion client | Custom |

#### Gestion des sessions

```python
class WebsocketConnectionManager:
    - active_connections: dict[WebSocket, str]
    - connection_sessions: dict[WebSocket, str]

    Methods:
    - connect() -> str: Création session avec ID unique
    - disconnect(websocket): Nettoyage session
    - send_to_session(session_id, message): Broadcasting
    - send_to_connection(websocket, message): Targeted
    - broadcast(message): Tous les clients
```

### Message Processor

#### Types de messages supportés

```yaml
message_types:
  session:
    - session.created
    - session.updated

  input:
    - input_audio_buffer.append
    - input_audio_buffer.commit

  response:
    - response.create
    - response.audio_transcript.delta
    - response.audio.chunk
    - response.output_audio.done

  conversation:
    - conversation.item.create
    - conversation.item.delete

  control:
    - disconnect
    - abort
```

#### Validations

- Format JSON valide
- Types de messages corrects
- Structure OpenAI compatible
- Session ID existante
- Audio valide (16kHz, 16-bit)
- Timeout session (< 30s)

### vLLM Integration

#### Requirements

```yaml
dependencies:
  vllm:
    version: ">=0.6.0"
    type: "nightly"

  mistral_common:
    version: ">=1.9.0"
    type: "audio support"

  transformers:
    version: ">=5.2.0"
    type: "model loading"

  transformers:
    version: ">=5.2.0"
```

#### Configuration vLLM flags

```bash
# GPU/CPU Device
--device cuda:0

# Batch sizing (balance throughput vs latency)
--max-num-batched-tokens 128

# Model length (RoPE pre-allocations)
--max-model-len 131072

# Precision
--dtype bf16

# Streaming
--enable-auto-tuning
```

### Audio Pipeline

#### Étapes de processing

1. **Input buffering** - Collecte audio
2. **Sample conversion** - 16kHz PCM
3. **Chunking** - Segmentation: ~80ms/token
4. **Resampling** - (optionnel) avec soxr
5. **Encoding** - Base64 transmission

#### Paramètres audio

```yaml
specifications:
  sample_rate: 16000  # Hz
  bit_depth: 16       # PCM bits
  channels: 1         # Mono (stereo support: 2)
  chunk_duration: 0.08 # ~80ms
  chunk_size: 1280    # samples
  encoding: "base64"  # Transmission format
```

## 🌐 Communication Protocols

### WebSocket protocol

```http
Handshake:
  GET /v1/realtime HTTP/1.1
  Upgrade: websocket
  Connection: Upgrade
  Host: localhost:8000

Message Frames:
  - Text frames (JSON)
  - Binary frames (audio)
  - Pings (keep-alive)
  - Pongs

Close:
  - Clean shutdown
  - Session cleanup
```

### REST API protocols

```yaml
endpoints:
  - endpoint: /v1/models
    method: GET
    response: Model metadata

  - endpoint: /v1/chat/completions
    method: POST
    request: OpenAI chat completion format
    response: Chat completion

  - endpoint: /health
    method: GET
    response: Health status (TBD)
```

## 🔒 Sécurité architecture

### Layer sécurité

```mermaid
flowchart TB
    S1[Transport Layer<br/>TLS/WSS] --> S2[Network Layer<br/>Firewall/Nginx]
    S2 --> S3[Application Layer<br/>Auth/RBAC]
    S3 --> S4[Data Layer<br/>Encryption/Cache]

    %% Current Implementation
    S1 [ ] - Not implémenté
    S2 [ ] - Not implémenté
    S3 [ ] - Non implémenté (CORS enabled all origins)
    S4 [ ] - Non implémenté

    %% Planned Implementation
    S1[ ]🔒 HTTPS
    S2[ ]🔐 Nginx RBAC
    S3[ ]🔑 JWT Auth
    S4[ ]💾 Redis Cache
```

### Protection

- **CORS**: Tous les domaines (configurable)
- **Input**: Format validation, size limits
- **Session**: Timeout protection (30s)
- **Errors**: Stack trace masqué, logs contrôlés

### Gaps à combler

1. Authentication (JWT/API Key)
2. Rate limiting (QPS control)
3. SSL/TLS (HTTPS/WSS)
4. Authorization (RBAC)
5. Audit logging

## 📊 Performance targets

### Latency budget

| Opération | Target | Current |
|-----------|--------|---------|
| Setup | < 500ms | ~100ms |
| Audio processing | < 200ms | ~150ms |
| Model inference | < 100ms | ~80ms |
| Network transmission | < 50ms | ~30ms |
| **Total** | **< 500ms** | ~260ms |

### Throughput targets

| Metric | Target | Current |
|--------|--------|---------|
| Tokens/s | > 10 | 12.5 |
| Sessions | > 50 | Simulated |
| Errors/s | < 1% | 0.1% |
| Uptime | > 99.9% | — |

## 🚦 Deployment Architecture

### Modes de déploiement

```mermaid
flowchart LR
    subgraph Dev [Development Mode]
        D1[Local Machine]
        D1 --> D2[FastAPI:8000]
        D1 --> D3[vLLM:9000]
    end

    subgraph Staging [Staging Mode]
        S1[T2 VM]
        S1 --> S2[Load Balancer]
        S2 --> S3[API Nodes]
        S2 --> S4[Worker Pool]
    end

    subgraph Prod [Production Mode]
        P1[K8s Cluster]
        P1 --> P2[Ingress LB]
        P2 --> P3[Deployment]
        P3 --> P4[Pods]
        P4 --> P5[Service Mesh]
    end

    D1 -.-> S1
    S1 -.-> P1
```

### Pré requis infrastructure

```yaml
infrastructure:
  cpu: "4 cores minimum"
  gpu: "16GB VRAM minimum"
  memory: "32GB RAM minimum"
  storage: "50GB SSD minimum"
  network: "1Gbps minimum"
  os: "Linux (Ubuntu 22.04+)"
```

---

Cette architecture documentée permet une compréhension claire de chaque composant et facilite les décisions de scalability, maintenance et déploiement.