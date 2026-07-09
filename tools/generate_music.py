from elevenlabs.client import ElevenLabs
import os

API_KEY = "sk_39f56d61cb5f7385c464b01f00b3d49539627e11898dcbfb"
OUT = r"C:\Users\Patrick\dev\kingdom-(test)\Audio\music"
os.makedirs(OUT, exist_ok=True)

client = ElevenLabs(api_key=API_KEY)

print("Generating campaign map theme...")
track = client.music.compose(
    prompt="Orchestral fantasy adventure music. Opens with a dramatic tom drum roll building anticipation, then erupts into a grand sweeping orchestral theme with soaring strings, powerful brass fanfare, and full choir. Heroic, majestic, and noble. Cinematic medieval fantasy campaign map theme. No lyrics.",
    music_length_ms=120000,
    model_id="music_v2",
    output_format="pcm_44100",
)

out_path = os.path.join(OUT, "campaign_map_theme.wav")
with open(out_path, "wb") as f:
    for chunk in track:
        f.write(chunk)

print(f"Saved to {out_path}")
