"""BRASSLINE audio master. Requires Python numpy/scipy + FFmpeg (developers only).

Usage: python tools/build_audio.py /path/to/audio_sources
Sources: extracted Prepared SFX Library and impact/Audio (see audio/CREDITS.txt).
All shipped clips are prebuilt Ogg Vorbis; no downloads or synthesis at runtime.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess
import numpy as np
from scipy import signal
from scipy.io import wavfile

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
CATALOG = {}
SOURCES = {}
RNG = np.random.default_rng(9012026)


def decode(path):
    data = subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-f','f32le','-ac','1','-ar',str(RATE),'-'])
    return np.frombuffer(data, dtype='<f4').astype(float)


def filt(x, frequency, kind='lowpass'):
    return signal.sosfilt(signal.butter(2, frequency, btype=kind, fs=RATE, output='sos'), x)


def resize(x, duration):
    n = int(duration * RATE)
    return np.pad(x[:n], (0,max(0,n-len(x))))


def edges(x, attack=.0008, release=.045):
    x=x.copy(); a=min(int(attack*RATE),len(x)//2); b=min(int(release*RATE),len(x)//2)
    if a: x[:a]*=np.linspace(0,1,a)
    if b: x[-b:]*=np.linspace(1,0,b)**2
    return x


def norm(x, peak=.84):
    x=x-np.mean(x)
    return x*(peak/max(1e-9,np.max(abs(x))))


def mix(duration, *layers):
    x=np.zeros(int(duration*RATE))
    for clip,gain,onset in layers:
        start=int(onset*RATE); count=min(len(clip),len(x)-start)
        if count>0:x[start:start+count]+=clip[:count]*gain
    return x


def noise(duration, band=(100,8500)):
    x=RNG.normal(size=int(duration*RATE))
    return norm(filt(filt(x,band[0],'highpass'),band[1]))


def impact(source, seconds=.35, rate=1.0):
    x=decode(source)
    if rate != 1:x=signal.resample_poly(x,1000,int(1000*rate))
    active=np.flatnonzero(abs(x)>np.max(abs(x))*.025)
    if len(active):x=x[max(0,active[0]-44):]
    return edges(norm(resize(filt(x,55,'highpass'),seconds)),release=.06)


def write(cue, x, source, loop=False):
    index=len(CATALOG.get(cue,[]))+1; name=f'{cue}_{index:02}.ogg'
    x=np.clip(x,-.91,.91)
    # Encode already mixed clips; transient headroom also covers Vorbis overshoot.
    subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(RATE),'-ac','1',
                    '-i','-','-c:a','libvorbis','-q:a','5','-f','ogg',str(OUT/(name+'.tmp'))],input=x.astype('<f4').tobytes(),check=True)
    assert (OUT/(name+'.tmp')).stat().st_size>1000, name
    (OUT/(name+'.tmp')).replace(OUT/name)
    CATALOG.setdefault(cue,[]).append(name); SOURCES[name]=source


def gun(path, peaks, duration, weight):
    x=decode(path)
    clips=[]
    for center in peaks:
        left=max(0,int((center-.09)*RATE)); right=int((center+.08)*RATE)
        onset=left+int(np.argmax(abs(x[left:right])))
        # Find the leading impulse, retaining one millisecond of attack, no dead air.
        section=x[max(0,onset-int(.018*RATE)):onset+1]
        active=np.flatnonzero(abs(section)>np.max(abs(section))*.07)
        start=max(0,onset-int(.018*RATE))+int(active[0])-44
        dry=norm(resize(x[max(0,start):],duration),.72)
        dry=filt(dry,45,'highpass')
        body=filt(dry,350)*weight
        # Preserve the recorded report/reverberation, add a restrained low body layer.
        result=norm(edges(dry+body,release=.10),.84)
        clips.append(result)
    return clips


def main(source):
    OUT.mkdir(parents=True,exist_ok=True)
    fire=source/'Prepared SFX Library'; foley=source/'impact/Audio'
    for cue,file,peaks,duration,weight in [
        ('rifle','AK-47/C_28P.wav',[.61,3.25,6.02,9.15],.72,.25),
        ('pistol','1911/A_42P.wav',[.94,5.0],.82,.45),
        ('sniper','Tikka/W_29P.wav',[.58,5.66],1.1,.6)]:
        for x in gun(fire/file,peaks,duration,weight):write(cue,x,'Free Firearm Sound Library: '+file)
    def k(name,duration=.35,rate=1):return impact(foley/(name+'.ogg'),duration,rate)
    # Surface footsteps use separate takes instead of broad pitch randomization.
    for i in range(4):
        concrete=k(f'footstep_concrete_{i:03}',.24)
        wood=k(f'footstep_wood_{i:03}',.28)
        metal=k(f'impactPlate_light_{i:03}',.28,.90)
        for cue,x in [('step_concrete',concrete),('step_tile',mix(.26,(concrete,.7,0),(wood,.30,.008))),
                      ('step_metal',mix(.3,(concrete,.7,0),(metal,.23,.014)))]:
            write(cue,edges(norm(x,.75)),f'Kenney Impact Sounds: footsteps/plate take {i}')
    write('step',k('footstep_concrete_000',.24),'Kenney: footstep_concrete_000')
    cloth=k('footstep_carpet_002',.25)
    heavy=k('impactSoft_heavy_001',.36,.82)
    write('jump',norm(mix(.22,(cloth,.8,0),(noise(.22,(120,2600))*.18,.3,.02)),.55),'Kenney carpet + original air')
    write('land',norm(mix(.38,(heavy,.8,0),(k('footstep_concrete_003',.28),.7,.015)),.82),'Kenney soft heavy + concrete')
    for cue,names,offsets in [
        ('mag_out',['impactMetal_light_001','impactGeneric_light_000'],[0,.085]),
        ('mag_in',['impactGeneric_light_003','impactMetal_medium_001'],[0,.06]),
        ('slide',['impactMetal_light_003','impactTin_medium_002'],[0,.075]),
        ('bolt_open',['impactMetal_light_002','impactPlate_light_001'],[0,.095]),
        ('bolt_close',['impactTin_medium_000','impactMetal_medium_003'],[0,.04]),
        ('equip',['impactGeneric_light_001','footstep_carpet_001'],[0,.035])]:
        layers=[(k(n,.24,.84 if cue.startswith('bolt') else 1),.7 if j==0 else .42,offsets[j]) for j,n in enumerate(names)]
        write(cue,edges(norm(mix(.34,*layers),.74)), 'Kenney: '+', '.join(names)+' (edited mechanical foley)')
    write('empty',k('impactMetal_light_004',.12),'Kenney: impactMetal_light_004')
    for i in range(2):
        punch=k(f'impactPunch_heavy_{i:03}',.30,.85)
        crack=k(f'impactWood_medium_{i:03}',.24,1.2)
        grit=k(f'impactGlass_light_{i:03}',.25,.85)
        # One quick dry crack, dense impact, a short crunchy tail. No piercing sine beep.
        x=mix(.33,(punch,.75,0),(crack,.62,.003),(grit,.24,.018))
        write('head',edges(norm(filt(x,11000),.85)),f'Kenney punch/wood/glass take {i}; layered headshot confirmation')
    write('hit',edges(norm(k('impactPunch_medium_002',.16),.69)),'Kenney: impactPunch_medium_002')
    write('hurt',edges(norm(k('impactSoft_heavy_002',.26,.8),.74)),'Kenney: impactSoft_heavy_002')
    for cue,name,duration in [('impact_concrete','impactMining_002',.3),('impact_metal','impactMetal_medium_003',.48),
                              ('grenade_bounce','impactMetal_light_000',.23),('parry','impactPlate_heavy_001',.48)]:
        write(cue,k(name,duration),f'Kenney: {name}')
    t=np.arange(int(.3*RATE))/RATE
    whoosh=noise(.3,(220,6500))*np.sin(np.pi*np.linspace(0,1,len(t)))**2
    write('sword',edges(norm(whoosh,.70)),'Original band-limited sword air')
    t=np.arange(int(1.6*RATE))/RATE
    firebody=noise(1.6,(38,2600))*(1-np.exp(-t*900))*np.exp(-t*3.8)
    snap=k('impactPunch_heavy_003',.4,.7)
    debris=k('impactMining_004',.8,.60)
    write('blast',edges(norm(mix(1.6,(firebody,1,0),(snap,.9,0),(debris,.22,.11)),.87),release=.25),
          'Original filtered blast pressure + Kenney punch/mining debris')
    hiss=noise(2,(250,5500))*np.sin(np.linspace(0,np.pi,int(2*RATE)))**.5
    write('smoke_hiss',edges(norm(hiss,.60),release=.25),'Original filtered smoke release')
    for cue,freq,duration in [('tick',1050,.07),('ui',620,.055),('case_tick',1300,.04)]:
        t=np.arange(int(duration*RATE))/RATE
        value=(np.sin(2*np.pi*freq*t)*.7+noise(duration,(700,7000))*.2)*np.exp(-t*75)
        write(cue,edges(norm(value,.48),release=.02),'Original short muted interface cue')
    for cue,notes,length in [('kill',[760,1140],.24),('achievement',[660,880,1100,1320],.8),('case_reveal',[440,660,880,1100],.85)]:
        value=np.zeros(int(length*RATE));t=np.arange(len(value))/RATE
        for j,f in enumerate(notes):
            a=np.maximum(0,t-j*.065); env=(t>=j*.065)*(1-np.exp(-a*380))*np.exp(-a*9)
            value+=(np.sin(2*np.pi*f*a)+.2*np.sin(2*np.pi*f*2.01*a))*env*.18
        write(cue,edges(norm(value,.64),release=.12),'Original layered confirmation chime')
    # Periodic low-passed noise + non-beating fan harmonics. No loop crossfade dip.
    duration=16; n=int(duration*RATE);t=np.arange(n)/RATE; frequencies=np.fft.rfftfreq(n,1/RATE)
    for cue,gain,hz in [('drone',1,62.5),('ambient_foundry',.8,87.5),('ambient_dock',.75,50),('ambient_sunspire',.5,75),('ambient_relay',.55,125)]:
        spectrum=(RNG.normal(size=len(frequencies))+1j*RNG.normal(size=len(frequencies)))
        spectrum/=np.maximum(frequencies,45)**.9
        spectrum*=np.exp(-(frequencies/1400)**4)*(1-np.exp(-(frequencies/40)**4));spectrum[0]=0
        air=np.fft.irfft(spectrum,n);air=air/max(np.std(air),1e-8)
        value=air*.11*gain+(.035*np.sin(2*np.pi*hz*t)+.015*np.sin(2*np.pi*hz*2*t))
        write(cue,value,'Original periodic filtered airflow/fan drone',loop=True)
    (OUT/'catalog.json').write_text(json.dumps(CATALOG,indent=2)+'\n')
    (OUT/'provenance.json').write_text(json.dumps(SOURCES,indent=2)+'\n')
    print(f'Built {sum(map(len,CATALOG.values()))} clips across {len(CATALOG)} cues.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('sources',type=Path);main(p.parse_args().sources)
