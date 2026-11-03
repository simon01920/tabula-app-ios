# Licences and rights — Tabula App Preview (EN)

Checked 2026-11-04. Not legal advice; the owner confirms before distribution.

| Asset | Source | Licence / rights | Attribution needed? | Evidence |
|---|---|---|---|---|
| App footage | Tabula simulator build (owner's app), fictional seed data | Owner's own work | No | `capture-manifest.md` |
| App icon `AppIcon.png` | `Resources/AppIcon.png` (supplied, unmodified) | Owner's own work | No | repo |
| Import prop photo | `video/tools/make_import_photo.py` (rendered, no AI imagery, no stock) | Owner's own work; text set in Inter | No | script + output in `video/assets/` |
| Caption font Inter | Bundled with Hyperframes; also `C:/Windows/Fonts/Inter-*.ttf` | SIL Open Font License 1.1 (embedding and commercial use allowed) | No | rsms/inter OFL |
| Music bed | ElevenLabs Music v2.5, flow `mM2SxE9irFJvT8fUTrq0`, batch 1 `oNS1LqO0yht52oBn8Vaa` / `6eUQGsZSMBCzUpOYC9fq` (rejected by owner: "generic"), batch 2 `4JEJ6j4qVLiNgovAllJy` (indie-electronic) / `M320qbvpgeY4DT9E3e27` (lo-fi), created 2026-11-04 on the **Free** plan | ElevenLabs Music Terms, Exhibit A: Free = individual use; "All online and offline commercial use permitted, except film, TV, radio, and Studio Games"; streaming distribution prohibited | **Free plan: required** ("denote Eleven Music when distributing", §4.8(a), e.g. "Created in collaboration with ElevenLabs"). **Not required after upgrading to Creator:** §1.5, "all Output in your account at the time of the upgrade are subject to the upgraded plan" | https://elevenlabs.io/music-terms (read 2026-11-04) |
| Sound effects | none used | — | — | — |
| Simulator stock photos (PhotosPicker defaults) | iOS Simulator | Rights undocumented | — | **Not shown**: the picker shot was removed after QA (M3); only the owner's own rendered photo appears |
| GSAP | runtime of the composition (not distributed in the video) | GSAP standard licence (free, including commercial) | No | gsap.com |

Terms checked by the orchestrator with WebFetch on 2026-11-04 (the QA agent had no web access). Free-plan audio files are git-ignored (`.git/info/exclude`) so they are never distributed from the public repo.

**Owner action before publishing:** upgrade to Creator (student offer) *before* the preview goes live. Otherwise, place the ElevenLabs credit somewhere reasonable (App Store description or the app's About/Acknowledgements), because an in-video credit would add text Apple's preview rules don't need. Keep the 4-line generation record above. BRAG's bundled "Happy Beats" (CC BY 4.0) is not used.
