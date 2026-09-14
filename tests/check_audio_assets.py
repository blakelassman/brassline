"""Decode every shipped clip; check transients, peaks, loops and catalog completeness."""
from pathlib import Path
import json, subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[1]/'assets/audio'
report={}
for cue, names in json.loads((ROOT/'catalog.json').read_text()).items():
    for name in names:
        x=np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-i',str(ROOT/name),'-f','f32le','-ac','1','-ar','44100','-']),dtype='<f4')
        assert len(x)>100 and np.isfinite(x).all(),name
        peak=float(abs(x).max());rms=float(np.sqrt(np.mean(x*x)))
        assert 0.01<peak<.99,(name,'peak',peak)
        assert abs(float(np.mean(x)))<.005,(name,'DC offset')
        onset=np.flatnonzero(abs(x)>peak*.025)[0]/44.1
        if cue in ('rifle','pistol','sniper','head'):assert onset<5,(name,'delayed attack',onset)
        if cue=='drone' or cue.startswith('ambient_'):
            assert len(x)/44100>15.9
            assert abs(float(x[-1]-x[0]))<.06,(name,'loop seam')
        report[name]={'seconds':round(len(x)/44100,3),'peak_dbfs':round(20*np.log10(peak),2),
                      'rms_dbfs':round(20*np.log10(rms),2),'attack_ms':round(onset,2)}
assert len(report)==52
print(json.dumps(report,indent=2))
print('AUDIO_ASSETS_RESULT: 52 decoded, bounded-peak clips passed')
