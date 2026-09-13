#!/usr/bin/env python3
"""Laboratorio reproducible de clonación Qwen/CosyVoice.

Las claves se leen de ~/.btodicta/.env; nunca se imprimen ni se guardan en los
resultados. Los metadatos generados contienen únicamente el voice id, modelo y
request id. Es una herramienta de QA, no se ejecuta desde la app.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import pathlib
import secrets
import urllib.parse
import urllib.error
import urllib.request
import uuid


API_BASES = {
    "intl": "https://dashscope-intl.aliyuncs.com/api/v1",
    "china": "https://dashscope.aliyuncs.com/api/v1",
}
WS_BASES = {
    "intl": "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference",
    "china": "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
}


def api_for(region: str) -> str:
    try:
        return API_BASES[region]
    except KeyError:
        raise SystemExit(f"Región DashScope no permitida: {region}") from None


def load_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if path.exists():
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            values[name.strip()] = value.strip()
    return values


def key_for(args: argparse.Namespace) -> str:
    value = os.environ.get(args.key_name) or load_env(args.env_file).get(args.key_name)
    if not value:
        raise SystemExit(f"Falta {args.key_name} en el entorno o {args.env_file}")
    return value


def post_json(url: str, key: str, payload: dict, extra_headers: dict[str, str] | None = None) -> tuple[bytes, str]:
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Connection": "close",
    }
    headers.update(extra_headers or {})
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return response.read(), response.headers.get_content_type()
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:2000]
        raise SystemExit(f"HTTP {error.code}: {body}") from None
    except urllib.error.URLError as error:
        raise SystemExit(f"Error de red: {error.reason}") from None


def temporary_oss_url(key: str, model: str, audio: pathlib.Path, region: str) -> str:
    api = api_for(region)
    query = urllib.parse.urlencode({"action": "getPolicy", "model": model})
    request = urllib.request.Request(
        f"{api}/uploads?{query}",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "Connection": "close"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            policy = json.loads(response.read()).get("data") or {}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:1200]
        raise SystemExit(f"No pude obtener almacenamiento temporal (HTTP {error.code}): {body}") from None
    except urllib.error.URLError as error:
        raise SystemExit(f"No pude obtener almacenamiento temporal: {error.reason}") from None

    required = ["upload_dir", "upload_host", "oss_access_key_id", "signature", "policy",
                "x_oss_object_acl", "x_oss_forbid_overwrite"]
    missing = [name for name in required if not policy.get(name)]
    if missing:
        raise SystemExit(f"Política de carga incompleta: {', '.join(missing)}")
    upload_host = policy["upload_host"]
    if not upload_host.startswith("https://"):
        raise SystemExit("La carga temporal no ofreció HTTPS; se canceló")

    object_key = f"{policy['upload_dir']}/{audio.name}"
    fields = {
        "OSSAccessKeyId": policy["oss_access_key_id"],
        "Signature": policy["signature"],
        "policy": policy["policy"],
        "x-oss-object-acl": policy["x_oss_object_acl"],
        "x-oss-forbid-overwrite": policy["x_oss_forbid_overwrite"],
        "key": object_key,
        "success_action_status": "200",
    }
    boundary = f"----BtoDicta{secrets.token_hex(12)}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
            str(value).encode(), b"\r\n",
        ])
    chunks.extend([
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{audio.name}"\r\n'.encode(),
        f"Content-Type: {mimetypes.guess_type(audio.name)[0] or 'application/octet-stream'}\r\n\r\n".encode(),
        audio.read_bytes(), b"\r\n", f"--{boundary}--\r\n".encode(),
    ])
    upload = urllib.request.Request(
        upload_host,
        data=b"".join(chunks),
        method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}", "Connection": "close"},
    )
    try:
        with urllib.request.urlopen(upload, timeout=90) as response:
            if response.status != 200:
                raise SystemExit(f"La carga temporal respondió HTTP {response.status}")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:1200]
        raise SystemExit(f"Falló la carga temporal (HTTP {error.code}): {body}") from None
    except urllib.error.URLError as error:
        raise SystemExit(f"Falló la carga temporal: {error.reason}") from None
    print("OK audio subido al almacenamiento temporal privado de DashScope (expira automáticamente)")
    return f"oss://{object_key}"


def write_private(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    with open(tmp, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def write_metadata(path: pathlib.Path, response: dict, family: str, target: str, region: str) -> None:
    output = response.get("output") or {}
    voice = output.get("voice") or output.get("voice_id")
    if not voice:
        raise SystemExit(f"La respuesta no contiene voice id: {json.dumps(response, ensure_ascii=False)[:1200]}")
    safe = {
        "family": family,
        "target_model": target,
        "region": region,
        "voice": voice,
        "request_id": response.get("request_id", ""),
        "fallback_mode": output.get("fallback_mode", False),
        "fallback_reason": output.get("fallback_reason", ""),
    }
    write_private(path, (json.dumps(safe, ensure_ascii=False, indent=2) + "\n").encode())
    print(f"OK family={family} model={target} metadata={path}")


def data_uri(path: pathlib.Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "audio/wav"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"


def enroll_qwen(args: argparse.Namespace) -> None:
    payload = {
        "model": "qwen-voice-enrollment",
        "input": {
            "action": "create",
            "target_model": args.target,
            "preferred_name": args.name,
            "audio": {"data": data_uri(args.audio)},
            "text": args.transcript.read_text(encoding="utf-8").strip(),
            "language": "es",
        },
    }
    customize = f"{api_for(args.region)}/services/audio/tts/customization"
    raw, _ = post_json(customize, key_for(args), payload)
    write_metadata(args.metadata, json.loads(raw), "qwen", args.target, args.region)


def enroll_cosy(args: argparse.Namespace) -> None:
    key = key_for(args)
    if args.temporary_upload:
        url = temporary_oss_url(key, "voice-enrollment", args.audio, args.region)
    else:
        url = data_uri(args.audio) if args.try_data_uri else args.audio_url
    if not url:
        raise SystemExit("CosyVoice exige --audio-url pública; --try-data-uri solo prueba compatibilidad no documentada")
    if not (url.startswith("https://") or url.startswith("oss://") or url.startswith("data:")):
        raise SystemExit("La referencia de audio debe usar HTTPS, OSS privado o data URI; HTTP no está permitido")
    input_data: dict = {
        "action": "create_voice",
        "target_model": args.target,
        "prefix": args.name,
        "url": url,
        "max_prompt_audio_length": args.prompt_seconds,
        "enable_preprocess": args.preprocess,
    }
    if args.language:
        input_data["language_hints"] = [args.language]
    extra = {"X-DashScope-OssResourceResolve": "enable"} if url.startswith("oss://") else None
    customize = f"{api_for(args.region)}/services/audio/tts/customization"
    raw, _ = post_json(customize, key, {"model": "voice-enrollment", "input": input_data}, extra)
    write_metadata(args.metadata, json.loads(raw), "cosyvoice", args.target, args.region)


def parse_audio_response(raw: bytes, content_type: str) -> bytes:
    if content_type.startswith("audio/"):
        return raw
    response = json.loads(raw)
    output = response.get("output") or {}
    audio = output.get("audio") or {}
    encoded = audio.get("data") or output.get("audio_data")
    if encoded:
        return base64.b64decode(encoded)
    url = audio.get("url") or output.get("audio_url")
    if url:
        if urllib.parse.urlparse(url).scheme != "https":
            raise SystemExit("La API devolvió audio por una URL no HTTPS; se canceló la descarga")
        request = urllib.request.Request(url, headers={"Connection": "close"})
        with urllib.request.urlopen(request, timeout=90) as remote:
            return remote.read()
    raise SystemExit(f"Respuesta sin audio: {json.dumps(response, ensure_ascii=False)[:1200]}")


def synthesize_cosy_ws(metadata: dict, text: str, key: str, args: argparse.Namespace) -> bytes:
    try:
        import websocket
    except ImportError:
        raise SystemExit(
            "CosyVoice requiere websocket-client. Usa el entorno privado documentado en "
            "scripts/requirements-qwen-voice-lab.txt"
        ) from None

    region = metadata.get("region", "intl")
    try:
        ws_url = WS_BASES[region]
    except KeyError:
        raise SystemExit(f"Región WebSocket no permitida: {region}") from None
    task_id = str(uuid.uuid4())
    header = {"task_id": task_id, "streaming": "duplex"}
    run = {
        "header": {**header, "action": "run-task"},
        "payload": {
            "task_group": "audio",
            "task": "tts",
            "function": "SpeechSynthesizer",
            "model": metadata["target_model"],
            "parameters": {
                "text_type": "PlainText",
                "voice": metadata["voice"],
                "format": args.format,
                "sample_rate": args.sample_rate,
                "volume": 50,
                "rate": 1.0,
                "pitch": 1.0,
                "enable_ssml": False,
            },
            "input": {},
        },
    }
    if args.language_hint:
        run["payload"]["parameters"]["language_hints"] = [args.language_hint]
    connection = None
    try:
        connection = websocket.create_connection(
            ws_url,
            header=[f"Authorization: Bearer {key}", "User-Agent: BtoDicta-QA/1"],
            timeout=90,
            enable_multithread=False,
        )
        connection.send(json.dumps(run, ensure_ascii=False))
        while True:
            message = connection.recv()
            if isinstance(message, bytes):
                continue
            response = json.loads(message)
            event = (response.get("header") or {}).get("event")
            if event == "task-started":
                break
            if event == "task-failed":
                info = response.get("header") or {}
                raise SystemExit(f"CosyVoice rechazó la tarea: {info.get('error_code')}: {info.get('error_message')}")

        connection.send(json.dumps({
            "header": {**header, "action": "continue-task"},
            "payload": {"input": {"text": text}},
        }, ensure_ascii=False))
        connection.send(json.dumps({
            "header": {**header, "action": "finish-task"},
            "payload": {"input": {}},
        }, ensure_ascii=False))

        chunks: list[bytes] = []
        while True:
            message = connection.recv()
            if isinstance(message, bytes):
                chunks.append(message)
                continue
            response = json.loads(message)
            info = response.get("header") or {}
            event = info.get("event")
            if event == "task-finished":
                break
            if event == "task-failed":
                raise SystemExit(f"CosyVoice falló: {info.get('error_code')}: {info.get('error_message')}")
        audio = b"".join(chunks)
        if len(audio) < 1024:
            raise SystemExit(f"CosyVoice terminó sin audio suficiente ({len(audio)} bytes)")
        return audio
    except websocket.WebSocketBadStatusException as error:
        raise SystemExit(f"CosyVoice WebSocket rechazó la conexión (HTTP {error.status_code})") from None
    except websocket.WebSocketException as error:
        raise SystemExit(f"CosyVoice WebSocket falló: {error}") from None
    finally:
        if connection is not None:
            connection.close()


def synthesize(args: argparse.Namespace) -> None:
    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    text = args.text.read_text(encoding="utf-8").strip()
    family = metadata.get("family")
    if family == "qwen":
        api = api_for(metadata.get("region", "intl"))
        url = f"{api}/services/aigc/multimodal-generation/generation"
        payload = {
            "model": metadata["target_model"],
            "input": {"text": text, "voice": metadata["voice"], "language_type": "Spanish"},
            "parameters": {"stream": False},
        }
    elif family != "cosyvoice":
        raise SystemExit(f"Familia de voz no permitida: {family!r}")
    key = key_for(args)
    if family == "cosyvoice":
        audio = synthesize_cosy_ws(metadata, text, key, args)
    else:
        raw, content_type = post_json(url, key, payload)
        audio = parse_audio_response(raw, content_type)
    write_private(args.output, audio)
    print(f"OK audio={args.output} bytes={args.output.stat().st_size}")


def common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--env-file", type=pathlib.Path, default=pathlib.Path.home() / ".btodicta/.env")
    parser.add_argument("--key-name", default="DASHSCOPE_API_KEY")
    parser.add_argument("--region", choices=sorted(API_BASES), default="intl")


def main() -> None:
    parser = argparse.ArgumentParser()
    subs = parser.add_subparsers(dest="command", required=True)

    qwen = subs.add_parser("enroll-qwen")
    common(qwen)
    qwen.add_argument("--target", required=True)
    qwen.add_argument("--name", default="clon1")
    qwen.add_argument("--audio", required=True, type=pathlib.Path)
    qwen.add_argument("--transcript", required=True, type=pathlib.Path)
    qwen.add_argument("--metadata", required=True, type=pathlib.Path)
    qwen.set_defaults(run=enroll_qwen)

    cosy = subs.add_parser("enroll-cosy")
    common(cosy)
    cosy.add_argument("--target", choices=["cosyvoice-v3-plus", "cosyvoice-v3-flash"], required=True)
    cosy.add_argument("--name", default="clon1")
    cosy.add_argument("--audio", required=True, type=pathlib.Path)
    cosy.add_argument("--audio-url")
    cosy.add_argument("--try-data-uri", action="store_true")
    cosy.add_argument("--temporary-upload", action="store_true")
    cosy.add_argument("--language", default="")
    cosy.add_argument("--prompt-seconds", type=int, default=12)
    cosy.add_argument("--preprocess", action="store_true")
    cosy.add_argument("--metadata", required=True, type=pathlib.Path)
    cosy.set_defaults(run=enroll_cosy)

    speak = subs.add_parser("synthesize")
    common(speak)
    speak.add_argument("--metadata", required=True, type=pathlib.Path)
    speak.add_argument("--text", required=True, type=pathlib.Path)
    speak.add_argument("--output", required=True, type=pathlib.Path)
    speak.add_argument("--format", default="wav")
    speak.add_argument("--sample-rate", type=int, default=24000)
    speak.add_argument("--language-hint", default="")
    speak.set_defaults(run=synthesize)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
