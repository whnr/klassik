# Specimen data

`specimen.json` is the data for the design specimen of map sz-rs30.1.83 (ticket sz-rs30.1.83.2). It holds the OpenSubsonic responses of Navidrome 0.64.2, so the specimen sees the same fields as the app.

- `albums`: `getAlbum` for each album, with its songs. Field `set` is `flo` or `weak`.
- `artists`: `getArtists`.
- `covers`: album ID to a public-domain painting from Wikimedia Commons, with its credit. Load the `url` at runtime. Two albums have `null`: they show the state without a cover.

## Sets

- `flo`: Flo's own tags. All of Chopin, for a long list, and about 30 works from Gabrieli to Zender. Flo allows his tags in the public prototypes.
- `weak`: three recordings in another tagging style. No work, movement or role tags. All performers are in one artist string. One album has a surname-only composer, one has no composer, one has no genre.

## Regenerate

```
python3 make_data.py "<library>/Classical" <work dir>
```

It needs ffmpeg, mutagen and network access. It links the chosen folders into a throwaway Navidrome, so no audio is copied. It writes the weak set as silent MP3 files. It drops file paths, server URLs and the embedded covers. Each painting is the one nearest to the composition year of the album's works. `paintings.rq` is the Wikidata query for the paintings.
