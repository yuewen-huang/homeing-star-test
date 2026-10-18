"""Author original crystal-crab impacts, offline. No borrowed landing/footstep samples.

Deterministic layers: shell/ground compression, dry salt fracture, irregular crystal
resonance and scattering grit. PCM assets ship independently of this generator.
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'homeing-star-game/assets/sideview/audio/crystal_crab'
REPORT = ROOT / 'homeing-star-test/artifacts/crab-contact-audit'
RATE = 48000


def noise(rng, count, low, high):
    raw = rng.normal(0, 1, count)
    freq = np.fft.rfftfreq(count, 1 / RATE)
    mask = np.minimum(np.clip((freq-low)/max(low*.3, 30), 0, 1),
                      np.clip((high-freq)/max(high*.2, 200), 0, 1))
    band = np.fft.irfft(np.fft.rfft(raw)*mask, n=count)
    return band / max(np.std(band), 1e-8)


def impact(seed, length, weight, crystal, peak):
    rng = np.random.default_rng(seed)
    t = np.arange(round(length*RATE)) / RATE
    count = len(t)
    attack = 1-np.exp(-t/.0007)
    compression = noise(rng, count, 22, 210) * np.exp(-t/(.095*weight)) * .85
    phase = 2*np.pi*(38*t + 42*.026*(1-np.exp(-t/.026)))
    compression += np.sin(phase)*np.exp(-t/(.085*weight)) * .65
    # A heavy body arrives first. Salt fracture follows 18 ms later instead of
    # masking the low-frequency onset with a brittle high-frequency click.
    compression += np.sin(2*np.pi*52*t)*np.exp(-t/(.060*weight))*.32
    u = np.maximum(t-.018,0)
    fracture = noise(rng,count,420,6800)*(t>=.018)*(1-np.exp(-u/.0008))*np.exp(-u/.032)*.36
    fracture += noise(rng,count,150,900)*np.exp(-t/.018)*.22
    resonance = np.zeros(count)
    for freq, gain in [(730, .08), (1310, .10), (1877, .08), (2690, .045)]:
        resonance += gain*np.sin(2*np.pi*freq*t+rng.uniform(-.15,.15))*np.exp(-t/(.055*crystal))
    grit = np.zeros(count)
    for delay in rng.uniform(.018, min(.33,length*.7), 14):
        u = np.maximum(t-delay, 0)
        env = (t>=delay)*(1-np.exp(-u/.0004))*np.exp(-u/.013)
        grit += noise(rng,count,900,8200)*env*rng.uniform(.012,.035)
    mono = np.tanh((compression+fracture+resonance+grit)*attack*1.15)
    # Dry, narrow stereo: preserve attack location without a broad synthetic reverb.
    stereo = np.column_stack([mono+grit*.12, mono-grit*.12])
    stereo *= np.minimum(1, (length-t)/.035)[:,None]
    stereo -= np.mean(stereo,axis=0)
    stereo *= peak/max(np.max(np.abs(stereo)),1e-8)
    return stereo


def write(path, samples):
    pcm = np.round(np.clip(samples,-1,1)*32767).astype('<i2')
    with wave.open(str(path),'wb') as wav:
        wav.setnchannels(2); wav.setsampwidth(2); wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    REPORT.mkdir(parents=True,exist_ok=True)
    presets = {
        'claw_slam_a': (401,.52,1.0,.8,.82),
        'claw_slam_b': (402,.50,.95,.9,.82),
        'double_slam': (410,.80,1.8,1.4,.90),
        'salt_echo': (420,.26,.55,1.1,.58),
        'burrow_crush': (430,.76,1.5,.65,.86),
        'crystal_aftershock': (440,.90,2.1,1.65,.88),
    }
    report = {}
    preview = []
    for name, preset in presets.items():
        samples = impact(*preset)
        write(OUT/(name+'.wav'),samples)
        peak = float(np.max(np.abs(samples)))
        rms = float(np.sqrt(np.mean(samples**2)))
        assert peak < .95 and rms > .015
        assert float(np.max(np.abs(samples[:480]))) > .1, 'Attack must be audible in the first 10ms'
        report[name] = {'seconds':len(samples)/RATE,'peak_dbfs':round(20*np.log10(peak),2),
                        'rms_dbfs':round(20*np.log10(rms),2),'clipped_samples':int(np.sum(np.abs(samples)>=1))}
        preview.extend([samples,np.zeros((RATE//3,2))])
    write(REPORT/'crab_impacts_audition.wav',np.concatenate(preview))
    (REPORT/'audio_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
