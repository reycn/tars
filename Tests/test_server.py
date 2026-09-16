#!/usr/bin/env python3
"""Integration check against an isolated compiled server; never sends Vibe Island events."""
import json
import socket
import subprocess
import sys
import time

binary = sys.argv[1]
server = subprocess.Popen([binary, '--port', '27893', '--event-port', '27894'], stdout=subprocess.DEVNULL)
try:
    deadline = time.monotonic() + 5
    while True:
        try:
            connection = socket.create_connection(('127.0.0.1', 27893), .5)
            break
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(.05)
    connection.settimeout(7)
    reader = connection.makefile('rb')
    def read():
        packet = json.loads(reader.readline())
        assert packet['version'] == 1
        assert set(packet) == {'version','session','seq','state','sourceAvailable','heartbeat'}
        return packet
    def event(session, state):
        with socket.create_connection(('127.0.0.1', 27894), 1) as source:
            data = json.dumps(dict(session=session, state=state)).encode() + b'\n'
            source.sendall(data[:5])
            source.sendall(data[5:])
    initial = read()
    assert initial['state'] == 'waiting' and not initial['sourceAvailable']
    event('a','working')
    working = read()
    assert working['state'] == 'working' and working['seq'] > initial['seq']
    assert working['heartbeat'] == 20
    event('b','approval')
    assert read()['state'] == 'approval'
    event('a','completed')
    event('b','ended')
    assert read()['state'] == 'waiting'  # hidden completion never replays
    event('c','completed')
    complete = read()
    assert complete['state'] == 'completed'
    started = time.monotonic()
    waiting = read()
    assert waiting['state'] == 'waiting' and waiting['seq'] > complete['seq']
    assert 4.5 < time.monotonic() - started < 6.5
    assert waiting['heartbeat'] == 120
    with socket.create_connection(('127.0.0.1',27893), 1) as other:
        snapshot = json.loads(other.makefile('rb').readline())
        assert snapshot == waiting  # reconnect gets current full snapshot
    with socket.create_connection(('127.0.0.1',27894), 1) as bad:
        bad.sendall(b'x' * 3000)
    event('d','working')
    assert read()['state'] == 'working'
    print('PASS: snapshot, split framing, priority, sequence, completion timing, reconnect, oversized input')
finally:
    server.terminate()
    server.wait(timeout=5)
