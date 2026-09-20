#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time

CONTAINER = "supabase_edge_runtime_AlphaPos"
WORKDIR = "/opt/alphapos"
CACHE_DIR = "/var/lib/docker/volumes/supabase_edge_runtime_AlphaPos/_data"


def run(args, **kwargs):
    return subprocess.run(args, text=True, check=True, **kwargs)


data = json.loads(run(["docker", "inspect", CONTAINER], capture_output=True).stdout)[0]
config = data["Config"]
host_config = data["HostConfig"]
image = config["Image"]
old_name = f"{CONTAINER}_old_workdir_{int(time.time())}"

for name in (
    "dep_analysis_cache_v2",
    "dep_analysis_cache_v2-shm",
    "dep_analysis_cache_v2-wal",
    "node_analysis_cache_v2",
    "node_analysis_cache_v2-shm",
    "node_analysis_cache_v2-wal",
):
    try:
        os.remove(os.path.join(CACHE_DIR, name))
    except FileNotFoundError:
        pass

network = next(iter(data["NetworkSettings"]["Networks"]), None)
mount_args = []
for mount in data["Mounts"]:
    suffix = ":ro" if not mount["RW"] else ""
    if mount["Type"] == "bind":
        mount_args += ["-v", f"{mount['Source']}:{mount['Destination']}{suffix}"]
    elif mount["Type"] == "volume":
        mount_args += ["-v", f"{mount['Name']}:{mount['Destination']}{suffix}"]

cmd = ["docker", "run", "-d", "--name", CONTAINER, "-w", WORKDIR]
if host_config.get("RestartPolicy", {}).get("Name"):
    cmd += ["--restart", host_config["RestartPolicy"]["Name"]]
if network:
    cmd += ["--network", network]
cmd += mount_args
for env in config.get("Env") or []:
    cmd += ["-e", env]
if config.get("Entrypoint"):
    cmd += ["--entrypoint", config["Entrypoint"][0]]
cmd.append(image)
cmd += config.get("Cmd") or []

try:
    run(["docker", "stop", CONTAINER])
    run(["docker", "rename", CONTAINER, old_name])
    result = run(cmd, capture_output=True)
except Exception:
    subprocess.run(["docker", "start", CONTAINER], text=True)
    raise

time.sleep(4)
logs = subprocess.run(["docker", "logs", "--tail", "30", CONTAINER], text=True, capture_output=True)
print(result.stdout.strip())
print(logs.stdout)
print(logs.stderr, file=sys.stderr)
subprocess.run(["docker", "rm", old_name], text=True, capture_output=True)
