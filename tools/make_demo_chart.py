"""Writes assets/data/strand-demo/strand-demo.json: a short silent chart for trying Strand out.

Sections alternate sides; the second half gets denser, ending in a stacked spam burst so
stack merging and draw skip have something to do.
"""
import json, random

random.seed(7)
BPM = 150
beat = 60000 / BPM
step = beat / 4
sections = []
for s in range(40):
    must = s % 2 == 1
    notes = []
    density = 0.35 + 0.6 * (s / 40)
    for k in range(16):
        t = (s * 16 + k) * step
        if s < 2:
            continue
        if random.random() < density:
            lane = random.randrange(4)
            hold = step * 3 if random.random() < 0.08 else 0
            notes.append([round(t, 3), lane, round(hold, 3)])
        if s >= 30 and random.random() < 0.5:

            notes.append([round(t + step / 2, 3), random.randrange(4) + 4, 0])
    if s >= 36:

        for k in range(64):
            t = s * 16 * step + k * step / 4
            for _ in range(20):
                notes.append([round(t, 3), k % 4, 0])
    sections.append({"sectionNotes": notes, "lengthInSteps": 16, "mustHitSection": must})
song = {"song": {"song": "strand demo", "bpm": BPM, "speed": 2.2, "keyCount": 4, "needsVoices": False,
                 "player1": "bf", "player2": "dad", "notes": sections, "events": []}}
with open("assets/data/strand-demo/strand-demo.json", "w") as f:
    json.dump(song, f, separators=(",", ":"))
print(sum(len(s["sectionNotes"]) for s in sections), "notes")
