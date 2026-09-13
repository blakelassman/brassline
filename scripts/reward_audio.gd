extends RefCounted
## Short original quest chime and case cues, synthesized once without external assets.
static func make(kind: String) -> AudioStreamWAV:
	var rate = 22050
	var length = .72 if kind=="achievement" else (.09 if kind=="case_tick" else .9)
	var bytes = PackedByteArray()
	bytes.resize(int(rate*length)*2)
	var notes = [659.25,830.61,987.77,1318.51] if kind=="achievement" else [392.0,493.88,587.33,783.99]
	for i in range(bytes.size()/2):
		var t = float(i)/rate
		var sample = 0.0
		for j in range(4 if kind!="case_tick" else 1):
			var age = t-j*.10
			if age>=0:
				var f = notes[j] if kind!="case_tick" else 1600.0
				sample += sin(age*f*TAU)*exp(-age*(8 if kind!="case_tick" else 65))*minf(1,age*200)*.17
		bytes.encode_s16(i*2,int(clampf(sample,-1,1)*26000))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
