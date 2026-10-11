#!/usr/bin/env python3
"""Run tools/balance_sim.gd for several difficulties x seeds in parallel and summarise.

  GODOT=/path/to/godot python3 godot/tools/run_balance.py out.jsonl --diffs 1,2,3,4 --seeds 1-4 --secs 1500 [--extra weapons=best skill=brawl]

Results (one JSON object per run) are appended to out.jsonl; a markdown summary is printed.
"""
import argparse, json, os, statistics, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)


def run(job):
    d, seed, secs, extra = job
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--path", PROJECT, "-s", "tools/balance_sim.gd", "--", str(d), str(secs), str(seed)] + extra
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("RESULT "):
            return json.loads(line[7:])
    return {"diff": d, "seed": seed, "error": out[-500:]}


def parse_seeds(s):
    if "-" in s:
        a, b = s.split("-")
        return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]


def summarize(results):
    names = {1: "Easy", 2: "Normal", 3: "Getting Worse", 4: "Hell"}
    print("| Difficulty | runs | died | median time of death (min) | median day | kills (median) | level | main killers |")
    print("|---|---|---|---|---|---|---|---|")
    for d in sorted({r["diff"] for r in results}):
        rs = [r for r in results if r["diff"] == d and "error" not in r]
        if not rs:
            continue
        died = [r for r in rs if r["died"]]
        times = [r["time"] for r in rs]
        killers = {}
        for r in rs:
            for k, v in r["dmg_by"].items():
                killers[k] = killers.get(k, 0) + v
        tot = sum(killers.values()) or 1
        kl = ", ".join(f"{k} {100*v/tot:.0f}%" for k, v in sorted(killers.items(), key=lambda kv: -kv[1])[:3])
        print(f"| {names[d]} | {len(rs)} | {len(died)} | {statistics.median(times)/60:.1f} (min {min(times)/60:.1f}, max {max(times)/60:.1f}) | "
              f"{statistics.median([r['day'] for r in rs]):.0f} | {statistics.median([r['kills'] for r in rs]):.0f} | {statistics.median([r['level'] for r in rs]):.0f} | {kl} |")


def per_day(results):
    for d in sorted({r["diff"] for r in results}):
        rs = [r for r in results if r["diff"] == d and "error" not in r]
        print(f"\nPer-day averages, difficulty {d} (over runs that reached the day)")
        print("| day | runs | kills | dmg taken | hits | hp min | hp avg | stamina avg | stamina<12 % | enemies | bandage+almond found | used | held | level |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for day in range(1, 40):
            ds = [x for r in rs for x in r["days"] if x["day"] == day]
            if not ds:
                break
            av = lambda f: sum(f(x) for x in ds) / len(ds)
            dmg = av(lambda x: sum(x["dmg"].values()))
            print(f"| {day} | {len(ds)} | {av(lambda x: x['kills']):.0f} | {dmg:.0f} | {av(lambda x: x['hits']):.1f} | {av(lambda x: x['hp_min']):.0f} | {av(lambda x: x['hp_avg']):.0f} | "
                  f"{av(lambda x: x['stam_avg']):.0f} | {av(lambda x: x['stam_empty_pct']):.0f} | {av(lambda x: x['enemies_avg']):.0f} | "
                  f"{av(lambda x: x['heal_found']['bandage']+x['heal_found']['almond']):.1f} | {av(lambda x: x['heal_used']['bandage']+x['heal_used']['almond']):.1f} | "
                  f"{av(lambda x: x['bandages_held']+x['almond_held']):.1f} | {av(lambda x: x['level']):.0f} |")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--diffs", default="1,2,3,4")
    ap.add_argument("--seeds", default="1-4")
    ap.add_argument("--secs", type=int, default=1500)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--extra", nargs="*", default=[])
    ap.add_argument("--days", action="store_true")
    a = ap.parse_args()
    jobs = [(int(d), s, a.secs, a.extra) for d in a.diffs.split(",") for s in parse_seeds(a.seeds)]
    with ThreadPoolExecutor(a.jobs) as ex:
        results = list(ex.map(run, jobs))
    with open(a.out, "a") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")
    bad = [r for r in results if "error" in r]
    if bad:
        print("FAILED RUNS:", bad[:2], file=sys.stderr)
    summarize([r for r in results if "error" not in r])
    if a.days:
        per_day([r for r in results if "error" not in r])
