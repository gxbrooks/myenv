# Ubuntu: HDMI audio through KVM (speakers on KVM)

**Symptom:** Speakers work when the KVM selects Windows; on Ubuntu (Chrome/YouTube) there is no sound.

**Typical causes:**

1. **Wrong output device** — Ubuntu is using built-in audio or a stale HDMI profile.
2. **HDMI profile not active** — PipeWire/PulseAudio did not select the HDMI sink after KVM switch.
3. **Muted / wrong card** — Sink muted or card profile is `off` / analog.

---

## 1. Quick GUI check

1. **Settings → Sound** (or **Sound** in the system menu).
2. Under **Output**, choose the device that matches **HDMI / DisplayPort** for your monitor/KVM path.
3. Raise volume; ensure not muted.
4. Use **Test** if shown.

---

## 2. CLI diagnosis (PipeWire / PulseAudio)

Ubuntu 22.04+ often uses **PipeWire** (`wpctl`) with PulseAudio compatibility (`pactl`).

### Sinks (playback devices)

```bash
wpctl status
```

or:

```bash
pactl list short sinks
```

### Default sink

```bash
pactl get-default-sink
```

### Cards and profiles (look for `hdmi`)

```bash
pactl list cards
```

---

## 3. Set HDMI as default (session)

**WirePlumber / wpctl:**

```bash
wpctl status    # note the numeric Sink id for HDMI
wpctl set-default <ID>
```

**PulseAudio-compatible:**

```bash
pactl list short sinks
pactl set-default-sink 'EXACT_SINK_NAME_FROM_LIST'
pactl set-sink-mute @DEFAULT_SINK@ 0
pactl set-sink-volume @DEFAULT_SINK@ 50%
```

---

## 4. Card profile (enable HDMI)

If HDMI sink does not appear, set the card profile (names vary):

```bash
pactl list cards short
pactl set-card-profile <CARD_NAME> output:hdmi-stereo
```

Use the exact profile string from `pactl list cards` (e.g. `output:hdmi-stereo`, `output:hdmi-surround`).

---

## 5. Restart user audio stack (after KVM switch)

```bash
systemctl --user restart wireplumber pipewire pipewire-pulse
```

Then re-open **Sound** settings and pick HDMI again.

---

## 6. ALSA

```bash
aplay -l
alsamixer -c <card_number>
```

Unmute **S/PDIF** / **HDMI** / **IEC958** if shown (`M`).

---

## 7. Chrome

- Fix **system** default output first; Chrome follows it.
- `chrome://settings/content/sound` — ensure the site isn’t blocked.

---

## 8. KVM / EDID

Some KVMs confuse hotplug: Ubuntu may keep a stale sink. Try switching KVM away and back **after** Ubuntu is logged in, or run the user audio restart (section 5).

If HDMI never appears in `wpctl` / `pactl`, test **Ubuntu → monitor direct** (no KVM) to isolate EDID/KVM issues.

---

## Helper script in this repo

From the myenv repo root on the Ubuntu machine:

```bash
./diagnose_hdmi_audio.sh
```

See also: `refresh_display_kvm.sh`, `wake_on_kvm.sh` (display/USB; complementary to audio).
