"""Optional developer test runner. Playing BRASSLINE does not require Python.
Usage: python run_multiplayer.py --godot /path/to/godot [--latency | --capacity]
"""
import argparse
import heapq
from pathlib import Path
import random
import socket
import subprocess
import tempfile
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default=str(Path(__file__).resolve().parents[1] / 'engine' / 'Godot_v4.7.2-stable_win64_console.exe'))
parser.add_argument('--project', default=str(Path(__file__).resolve().parents[1]))
parser.add_argument('--latency', action='store_true')
parser.add_argument('--capacity', action='store_true')
parser.add_argument('--destroy', action='store_true')
parser.add_argument('--killcams', action='store_true')
parser.add_argument('--prediction', action='store_true')
parser.add_argument('--lag-compensation', action='store_true')
parser.add_argument('--delay-ms', type=float, default=40)
parser.add_argument('--jitter-ms', type=float, default=10)
parser.add_argument('--loss', type=float, default=.02)
parser.add_argument('--client-fps', type=int, default=120)
args = parser.parse_args()
stop = threading.Event()
metrics = {'packets': 0, 'dropped': 0, 'max_datagram': 0}

def proxy():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', 27918))
    sock.settimeout(.001)
    server = ('127.0.0.1', 27917)
    client, queue, rng = None, [], random.Random(202607)
    try:
        while not stop.is_set():
            try:
                packet, address = sock.recvfrom(65535)
                metrics['packets'] += 1
                metrics['max_datagram'] = max(metrics['max_datagram'], len(packet))
                if address == server:
                    destination = client
                else:
                    client = address
                    destination = server
                if destination:
                    if rng.random() < args.loss:
                        metrics['dropped'] += 1
                    else:
                        heapq.heappush(queue, (time.monotonic() + max(0, args.delay_ms + rng.uniform(-args.jitter_ms, args.jitter_ms))/1000, metrics['packets'], packet, destination))
            except socket.timeout:
                pass
            while queue and queue[0][0] <= time.monotonic():
                _, _, packet, destination = heapq.heappop(queue)
                sock.sendto(packet, destination)
    finally:
        sock.close()

failed = False
with tempfile.TemporaryDirectory(prefix='brassline-test-') as folder:
    processes = []
    thread = None
    if args.latency and not args.capacity:
        thread = threading.Thread(target=proxy)
        thread.start()
    roles = ['host'] + ['client' + str(i) for i in range(9)] + ['full'] if args.capacity else (['host', 'client'] if args.prediction or args.lag_compensation or args.killcams else ['host', 'client', 'reject'])
    try:
        for role in roles:
            log_path = Path(folder) / (role + '.log')
            log = log_path.open('w')
            command = [args.godot, '--headless', '--path', args.project, '--',
                       '--killcam-test' if args.killcams else ('--destroy-test' if args.destroy else ('--capacity-test' if args.capacity else ('--lagcomp-test' if args.lag_compensation else ('--prediction-test' if args.prediction else '--network-test')))),
                       '--role=' + role, '--coord=' + folder, '--client-fps=' + str(args.client_fps),
                       '--join-port=' + ('27918' if args.latency else '27917')]
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            processes.append((role, process, log, log_path))
            time.sleep(.35)
        deadline = time.monotonic() + 90
        while any(p.poll() is None for _, p, _, _ in processes) and time.monotonic() < deadline:
            time.sleep(.1)
    finally:
        stop.set()
        if thread:
            thread.join()
        for role, process, log, log_path in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
            log.close()
            output = log_path.read_text(errors='replace')
            print(role, 'exit', process.returncode)
            print(output)
            failed |= process.returncode != 0 or 'FAIL ' in output or 'ERROR:' in output or ('_RESULT ' not in output and 'DESTROY_RESULT_TEST ' not in output)
    if args.latency:
        print('PROXY_METRICS', metrics)
raise SystemExit(1 if failed else 0)
