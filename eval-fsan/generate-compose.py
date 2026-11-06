import copy
import os
import yaml
projects = []
PROJ_FILE=os.environ.get("PROJECTS_FILE", None)
if PROJ_FILE is None:
    print("PROJECTS_FILE not set")
    exit(1)

with open(PROJ_FILE) as f:
    projects = [line.strip().split(":")[0] for line in f if line.strip()]

CWD = os.getcwd()
HOST_MOUNT_PATH = os.environ.get("HOST_MOUNT_PATH", CWD + "/fuzzing")

common = {
    "command": "/bin/bash",
    "init": True,
    "privileged": True,
    "stdin_open": True,
    "tty": True,
    "deploy": {"replicas": 1},
    "environment": {
        "PINNED_CORES_START": 0,
        "PINNED_CORES_END": 0,
        "PROJECT": "",
    }
}
NPROC_OUT = os.popen("nproc").read().strip()
N_CORES = int(NPROC_OUT) if NPROC_OUT.isdigit() else 100
N_CORES = min(N_CORES, 170)
# select MAX 10 harnesses per project
HARN_MAX = 10
MAP_PRO_TO_HARN_N = {}
for name in projects:
    # read n harnesses -> if the file is not there, assume 25
    n_harnesses = 0
    FILEPATH = f"{HOST_MOUNT_PATH}/{name}/HARNESSES.txt"
    print(f"Reading harnesses from {FILEPATH}")
    try:
        with open(f"{HOST_MOUNT_PATH}/{name}/HARNESSES.txt", "r") as f:
            n_harnesses = min(len([line.strip() for line in f if line.strip()]), HARN_MAX)
    except FileNotFoundError:
        # continue
        print(f"[!] File {FILEPATH} not found, assuming 0 harnesses for project {name}")
        n_harnesses = 10
    MAP_PRO_TO_HARN_N[name] = n_harnesses
print(f"MAP_PRO_TO_HARN_N: {MAP_PRO_TO_HARN_N}")
# count total 
total_harnesses = sum(MAP_PRO_TO_HARN_N.values())
print(f"Total harnesses: {total_harnesses}, N_CORES: {N_CORES}")
    
services = {}
CORES_START_GLOBAL = 0
for name in projects:
    n_harnesses = MAP_PRO_TO_HARN_N[name]
    CORES_END_GLOBAL = CORES_START_GLOBAL + min(n_harnesses, 10) if n_harnesses > 0 else 10
    common["environment"]["PINNED_CORES_START"] = CORES_START_GLOBAL
    common["environment"]["PINNED_CORES_END"] = CORES_END_GLOBAL
    CORES_START_GLOBAL = CORES_END_GLOBAL + 1
    svc = copy.deepcopy(common)
    svc["image"] = "gcr.io/oss-fuzz/" + name + ":latest"
    svc["volumes"] = [HOST_MOUNT_PATH + "/" + name + ":/fuzzing-campaign"]
    svc["environment"]["PROJECT"] = name if name != "pcapplusplus" else "PcapPlusPlus"
    services["eval-" + name] = svc

with open("docker-compose.yml", "w") as f:
    yaml.dump({"services": services}, f, sort_keys=False)