import json
import subprocess
import time
from pathlib import Path

inspect = json.loads(subprocess.check_output(["docker", "inspect", "supabase_edge_runtime_AlphaPos"]))[0]
env = inspect["Config"]["Env"]
new_env = []

secrets_file = Path("/opt/alphapos/supabase/functions/.env")
secret_overrides = {}
if secrets_file.exists():
    for raw_line in secrets_file.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.startswith("APNS_"):
            secret_overrides[key] = value

for item in env:
    env_key = item.split("=", 1)[0]
    if env_key in secret_overrides:
        continue
    if item.startswith("SUPABASE_INTERNAL_FUNCTIONS_CONFIG="):
        key, value = item.split("=", 1)
        cfg = json.loads(value)
        cfg["activate-merchant"] = {
            "verifyJWT": False,
            "entrypointPath": "supabase/functions/activate-merchant/index.ts",
            "importMapPath": "supabase/functions/activate-merchant/deno.json",
        }
        cfg["send-staff-push"] = {
            "verifyJWT": True,
            "entrypointPath": "supabase/functions/send-staff-push/index.ts",
        }
        item = key + "=" + json.dumps(cfg, separators=(",", ":"))
    new_env.append(item)

for key, value in secret_overrides.items():
    new_env.append(f"{key}={value}")

entrypoint = inspect["Config"].get("Entrypoint") or []
container_cmd = inspect["Config"].get("Cmd") or []
if len(entrypoint) >= 3:
    entrypoint_script = entrypoint[2]
elif len(container_cmd) >= 2 and container_cmd[0] == "-c":
    entrypoint_script = container_cmd[1]
else:
    raise RuntimeError(f"Unable to locate edge runtime entrypoint script: Entrypoint={entrypoint!r} Cmd={container_cmd!r}")
image = inspect["Config"]["Image"]

cmd = [
    "docker", "run", "-d",
    "--name", "supabase_edge_runtime_AlphaPos",
    "--restart", "unless-stopped",
    "--network", "supabase_network_AlphaPos",
    "--network-alias", "edge_runtime",
    "--add-host", "host.docker.internal:host-gateway",
    "--workdir", "/opt/alphapos",
    "--ulimit", "nofile=65536:65536",
    "-v", "supabase_edge_runtime_AlphaPos:/root/.cache/deno:rw",
    "-v", "/opt/alphapos/supabase/functions/:/opt/alphapos/supabase/functions/:ro",
    "--label", "com.docker.compose.project=AlphaPos",
    "--label", "com.supabase.cli.project=AlphaPos",
]

for item in new_env:
    cmd.extend(["-e", item])

cmd.extend(["--entrypoint", "sh", image, "-c", entrypoint_script])

old_name = f"supabase_edge_runtime_AlphaPos_old_{int(time.time())}"
subprocess.check_call(["docker", "stop", "supabase_edge_runtime_AlphaPos"])
subprocess.check_call(["docker", "rename", "supabase_edge_runtime_AlphaPos", old_name])
try:
    subprocess.check_call(cmd)
    time.sleep(4)
    subprocess.check_call(["docker", "exec", "supabase_edge_runtime_AlphaPos", "true"])
except Exception:
    subprocess.run(["docker", "rm", "-f", "supabase_edge_runtime_AlphaPos"])
    subprocess.check_call(["docker", "rename", old_name, "supabase_edge_runtime_AlphaPos"])
    subprocess.check_call(["docker", "start", "supabase_edge_runtime_AlphaPos"])
    raise
subprocess.check_call(["docker", "rm", old_name])
