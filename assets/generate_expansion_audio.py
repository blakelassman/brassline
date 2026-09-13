"""Original synthesized foley, ambience and layered shots. No sampled game assets."""
from pathlib import Path
import math, random, wave, struct
OUT=Path(__file__).resolve().parent
RATE=22050
SOUNDS={'mag_out':.23,'mag_in':.24,'slide':.27,'empty':.11,'land':.25,
        'step_concrete':.14,'step_metal':.20,'step_tile':.16,'grenade_bounce':.20,
        'smoke_hiss':1.5,'impact_concrete':.22,'impact_metal':.3,'ui':.09,'kill':.20,
        'ambient_foundry':8,'ambient_dock':8,'ambient_sunspire':8,'ambient_relay':8,
        'rifle':.30,'pistol':.38,'sniper':.65,'blast':.9}
for name,duration in SOUNDS.items():
    rng=random.Random('brassline-06-'+name)
    values=[]; low=0.; medium=0.
    for i in range(int(RATE*duration)):
        t=i/RATE; u=t/duration; noise=rng.uniform(-1,1)
        low=.975*low+.025*noise; medium=.75*medium+.25*noise
        if name.startswith('ambient_'):
            # Periodic envelopes and edge taper avoid a click at the loop boundary.
            edge=min(1,t/.12,(duration-t)/.12)
            breeze=(low*3+medium*.08)*(.65+.2*math.sin(2*math.pi*t/duration))
            if name=='ambient_dock': value=breeze*.55+math.sin(2*math.pi*55*t)*.025
            elif name=='ambient_relay': value=breeze*.16+math.sin(2*math.pi*60*t)*.09+math.sin(2*math.pi*120*t)*.035
            elif name=='ambient_sunspire': value=breeze*.30
            else: value=breeze*.25+math.sin(2*math.pi*80*t)*.03
            value*=edge
        elif name in ('rifle','pistol','sniper','blast'):
            frequency={'rifle':105,'pistol':78,'sniper':57,'blast':38}[name]
            crack=noise*math.exp(-t*170)*.7
            body=math.sin(2*math.pi*(frequency*t-20*t*t))*math.exp(-t*(16 if name!='blast' else 6))*.7
            roar=medium*math.exp(-t*(13 if name!='blast' else 5))*.9
            tail=0
            for onset,gain in [(.038,.28),(.071,.12),(.105,.08)]:
                if t>=onset: tail+=medium*math.exp(-(t-onset)*24)*gain
            value=math.tanh((crack+body+roar+tail)*1.35)*.85
        elif name.startswith('step_') or name=='land':
            f=86 if name=='land' else 140
            value=(math.sin(2*math.pi*f*t)*.6+medium*.9)*math.exp(-t*37)
            if name=='step_metal': value+=sum(math.sin(2*math.pi*f*t) for f in [430,713,1021])*math.exp(-t*28)*.09
            if name=='step_tile': value+=noise*math.exp(-t*95)*.25
            if t>.038: value+=medium*math.exp(-(t-.038)*45)*.22
        elif name in ('mag_out','mag_in','slide','empty','grenade_bounce','impact_metal'):
            f={'mag_out':720,'mag_in':350,'slide':980,'empty':1100,'grenade_bounce':520,'impact_metal':1830}[name]
            value=0
            for onset,gain in [(0,.75),(.034,.45),(.081,.2)]:
                if t>=onset:
                    age=t-onset
                    value+=(noise*.6+math.sin(2*math.pi*f*age)*.3)*math.exp(-age*80)*gain
            value+=medium*math.sin(math.pi*u)*math.exp(-u*4)*.3
            if name=='impact_metal': value+=math.sin(2*math.pi*2400*t)*math.exp(-t*20)*.12
        elif name=='smoke_hiss': value=medium*math.sin(math.pi*u)*.48
        elif name=='impact_concrete': value=(noise*.5+medium*.8)*math.exp(-t*42)
        elif name=='kill': value=(math.sin(2*math.pi*740*t)*.3+math.sin(2*math.pi*1110*t)*.15)*math.exp(-t*24)
        else: value=math.sin(2*math.pi*850*t)*math.sin(math.pi*u)*.2
        values.append(max(-.95,min(.95,value)))
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
        f.writeframes(struct.pack('<'+'h'*len(values),*(int(v*30000) for v in values)))
    print(name,len(values))
