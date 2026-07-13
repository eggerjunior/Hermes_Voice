#!/usr/bin/env python3
"""Cria o Bundle ID e o app Hermes Voice no App Store Connect, se necessário."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

BUNDLE_ID = "br.app.egger.hermesvoice"
APP_NAME = "Hermes Voice"
SKU = "br.app.egger.hermesvoice"
PRIMARY_LOCALE = "pt-BR"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(ROOT, "scripts", "asc.env")


def read_env(path):
    values = {}
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = os.path.expandvars(os.path.expanduser(value.strip().strip('"').strip("'")))
    return values


if not os.path.exists(ENV_PATH):
    print("ERRO: scripts/asc.env não encontrado.", file=sys.stderr)
    sys.exit(1)

env = read_env(ENV_PATH)
key_id = env.get("ASC_KEY_ID")
issuer_id = env.get("ASC_ISSUER_ID")
key_path = env.get("ASC_KEY_PATH")

if not key_id or not issuer_id or not key_path:
    print("ERRO: preencha ASC_KEY_ID, ASC_ISSUER_ID e ASC_KEY_PATH em scripts/asc.env.", file=sys.stderr)
    sys.exit(1)

with open(key_path, "r", encoding="utf-8") as handle:
    key = handle.read()

now = int(time.time())
token = jwt.encode(
    {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
    key,
    algorithm="ES256",
    headers={"kid": key_id},
)
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def api(method, path, body=None):
    url = f"https://api.appstoreconnect.apple.com/v1/{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return json.loads(raw)
        except Exception:
            return {"errors": [{"title": f"HTTP {error.code}", "detail": raw.decode("utf-8", "ignore")}]}


bundle_response = api("GET", f"bundleIds?filter[identifier]={BUNDLE_ID}")
if bundle_response.get("data"):
    bundle_id = bundle_response["data"][0]["id"]
    print(f"Bundle ID já existe: {bundle_id}")
else:
    created = api("POST", "bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_ID,
        "name": APP_NAME,
        "platform": "IOS"
    }}})
    if "data" not in created:
        for error in created.get("errors", []):
            print(f"Erro ao criar Bundle ID: {error.get('title')} - {error.get('detail')}", file=sys.stderr)
        sys.exit(1)
    bundle_id = created["data"]["id"]
    print(f"Bundle ID criado: {bundle_id}")

apps = api("GET", f"apps?filter[bundleId]={bundle_id}")
if apps.get("data"):
    print(f"App já existe: {apps['data'][0]['id']}")
    sys.exit(0)

created_app = api("POST", "apps", {"data": {"type": "apps", "attributes": {
    "bundleId": bundle_id,
    "name": APP_NAME,
    "primaryLocale": PRIMARY_LOCALE,
    "sku": SKU,
    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"
}, "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}}}})

if "data" in created_app:
    print(f"App criado com sucesso: {created_app['data']['id']}")
else:
    for error in created_app.get("errors", []):
        print(f"Erro ao criar app: {error.get('title')} - {error.get('detail')}", file=sys.stderr)
    sys.exit(1)
