"""Probes which listener data Navidrome stores and returns through OpenSubsonic calls.

Usage: python3 -I probe.py
Start the server first: scripts/fixture-server.sh <work-dir>. It leaves a throwaway Navidrome on
127.0.0.1:4533 with the admin user from that script. Set KLASSIK_USER and KLASSIK_PASSWORD to
use another admin. The probe makes a second user "other" through Navidrome's own admin API.
That call is test setup only. OpenSubsonic has no call that creates a user.
Run it against a fresh server. It writes stars, ratings, playlists, bookmarks, a queue and plays.
"""
import json
import os
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:4533"
ADMIN = (os.environ.get("KLASSIK_USER", "fixture"), os.environ.get("KLASSIK_PASSWORD", "fixture"))
OTHER = ("other", "other-probe-pw")


def rest(endpoint, user=None, client="probe", post=False, **params):
    """Calls one OpenSubsonic endpoint. A list value repeats the parameter."""
    user = user or ADMIN
    pairs = [("u", user[0]), ("p", user[1]), ("v", "1.16.1"), ("c", client), ("f", "json")]
    for key, value in params.items():
        for item in value if isinstance(value, list) else [value]:
            pairs.append((key, str(item)))
    body = urllib.parse.urlencode(pairs)
    url = f"{BASE}/rest/{endpoint}.view"
    request = urllib.request.Request(url, data=body.encode()) if post else urllib.request.Request(f"{url}?{body}")
    with urllib.request.urlopen(request) as response:
        return json.load(response)["subsonic-response"]


def error(reply):
    """Returns 'ok' or 'error <code>: <message>'."""
    if reply["status"] == "ok":
        return "ok"
    return f"error {reply['error']['code']}: {reply['error']['message']}"


def show(title, value):
    print(f"  {title}: {value}")


def head(title):
    print(f"\n== {title}")


def make_other_user():
    def post(path, payload, headers):
        request = urllib.request.Request(BASE + path, json.dumps(payload).encode(),
                                         {"Content-Type": "application/json", **headers})
        with urllib.request.urlopen(request) as response:
            return json.load(response)

    token = post("/auth/login", {"username": ADMIN[0], "password": ADMIN[1]}, {})["token"]
    try:
        post("/api/user", {"userName": OTHER[0], "name": "Other", "password": OTHER[1], "isAdmin": False},
             {"X-ND-Authorization": f"Bearer {token}"})
    except urllib.error.HTTPError as e:
        print("  other user exists or failed:", e.code)


def pick():
    reply = rest("search3", query="", songCount=500, albumCount=50, artistCount=50)["searchResult3"]
    songs, albums, artists = reply["song"], reply["album"], reply["artist"]
    composer = next(a for a in artists if a["roles"] == ["composer"])
    performer = next(a for a in artists if "composer" not in a["roles"])
    return songs, albums, composer, performer


def star():
    head("star")
    songs, albums, composer, performer = pick()
    song, album = songs[0], albums[0]
    show("composer artist", {k: composer[k] for k in ("id", "name", "roles", "albumCount")})
    for label, params in [("song id", {"id": song["id"]}), ("albumId", {"albumId": album["id"]}),
                          ("album as id", {"id": albums[1]["id"]}), ("artistId performer", {"artistId": performer["id"]}),
                          ("artistId composer", {"artistId": composer["id"]}),
                          ("composer as id", {"id": composer["id"]}), ("unknown id", {"id": "nope"})]:
        show(f"star {label}", error(rest("star", **params)))
    starred = rest("getStarred2")["starred2"]
    show("getStarred2 counts", {k: len(v) for k, v in starred.items()})
    show("getStarred2 artists", [(a["name"], a["roles"], a["starred"]) for a in starred.get("artist", [])])
    show("getStarred2 album starred", [a["starred"] for a in starred.get("album", [])][:2])
    first = rest("getSong", id=song["id"])["song"]["starred"]
    rest("star", id=song["id"])
    show("starred timestamp kept on second star", first == rest("getSong", id=song["id"])["song"]["starred"])
    show("getArtist composer starred", rest("getArtist", id=composer["id"])["artist"].get("starred"))
    show("search3 shows starred on song", rest("search3", query=song["title"][:8])["searchResult3"]["song"][0].get("starred"))
    show("other user getStarred2", rest("getStarred2", user=OTHER)["starred2"])
    show("other user getSong starred", rest("getSong", user=OTHER, id=song["id"])["song"].get("starred"))
    show("getAlbumList2 starred", [a["name"] for a in rest("getAlbumList2", type="starred")["albumList2"].get("album", [])])
    rest("unstar", id=song["id"])
    rest("unstar", artistId=composer["id"])
    show("after unstar song and composer", {k: len(v) for k, v in rest("getStarred2")["starred2"].items()})


def rating():
    head("setRating")
    songs, albums, composer, performer = pick()
    song, album = songs[1], albums[2]
    song_id = song["id"]
    for value in (4, 6, 100, -1, 2.5, 0):
        verdict = error(rest("setRating", id=song_id, rating=value))
        stored = rest("getSong", id=song_id)["song"].get("userRating")
        show(f"setRating song {value}", f"{verdict}; userRating now {stored}")
    rest("setRating", id=song_id, rating=4)
    for label, ident, value in [("album 5", album["id"], 5), ("performer 3", performer["id"], 3),
                                ("composer 2", composer["id"], 2), ("unknown id 3", "nope", 3)]:
        show(f"setRating {label}", error(rest("setRating", id=ident, rating=value)))
    show("getSong userRating", rest("getSong", id=song["id"])["song"].get("userRating"))
    show("getAlbum userRating", rest("getAlbum", id=album["id"])["album"].get("userRating"))
    show("getArtist composer userRating", rest("getArtist", id=composer["id"])["artist"].get("userRating"))
    show("getArtist performer userRating", rest("getArtist", id=performer["id"])["artist"].get("userRating"))
    show("getSong averageRating (one rater)", rest("getSong", id=song["id"])["song"].get("averageRating"))
    show("other user sees userRating", rest("getSong", user=OTHER, id=song["id"])["song"].get("userRating"))
    rest("setRating", user=OTHER, id=song["id"], rating=2)
    mine = rest("getSong", id=song["id"])["song"]
    show("two raters: userRating, averageRating", (mine.get("userRating"), mine.get("averageRating")))
    show("getAlbumList2 highest", [a["name"] for a in rest("getAlbumList2", type="highest")["albumList2"].get("album", [])])
    show("getAlbumList2 highest as other", [a["name"] for a in rest("getAlbumList2", user=OTHER, type="highest")["albumList2"].get("album", [])])
    rest("setRating", id=song["id"], rating=0)
    unset = rest("getSong", id=song["id"])["song"]
    show("after rating 0: userRating key present", "userRating" in unset)
    show("after rating 0: other's averageRating", unset.get("averageRating"))


def playlists():
    head("playlists")
    songs, *_ = pick()
    ids = [s["id"] for s in songs]
    made = rest("createPlaylist", name="Probe list", songId=ids[:3])["playlist"]
    show("create keys", sorted(made))
    show("create fields", {k: made.get(k) for k in ("name", "comment", "public", "owner", "songCount", "readonly")})
    pid = made["id"]
    rest("updatePlaylist", playlistId=pid, comment="a comment", public="false")
    show("comment, public after update", {k: rest("getPlaylist", id=pid)["playlist"].get(k) for k in ("comment", "public")})
    show("other user getPlaylists", [p["name"] for p in rest("getPlaylists", user=OTHER)["playlists"].get("playlist", [])])
    show("other user getPlaylist private", error(rest("getPlaylist", user=OTHER, id=pid)))
    rest("updatePlaylist", playlistId=pid, public="true")
    other_view = rest("getPlaylist", user=OTHER, id=pid)["playlist"]
    show("other user getPlaylist public", (other_view["name"], other_view["owner"], other_view.get("readonly"), other_view["songCount"]))
    show("other user updatePlaylist", error(rest("updatePlaylist", user=OTHER, playlistId=pid, name="hijack")))
    show("other user sees comment", other_view.get("comment"))
    rest("updatePlaylist", playlistId=pid, songIdToAdd=[ids[0], ids[0]])
    order = [e["id"] for e in rest("getPlaylist", id=pid)["playlist"]["entry"]]
    show("duplicates kept, order (index of id)", [ids.index(i) for i in order])
    rest("updatePlaylist", playlistId=pid, songIndexToRemove=[0, 3])
    order = [e["id"] for e in rest("getPlaylist", id=pid)["playlist"]["entry"]]
    show("after remove index 0 and 3", [ids.index(i) for i in order])
    rest("createPlaylist", playlistId=pid, songId=[ids[5], ids[4], ids[3]])
    reordered = rest("getPlaylist", id=pid)["playlist"]
    show("createPlaylist with playlistId replaces order", [ids.index(e["id"]) for e in reordered["entry"]])
    show("name and public kept after replace", (reordered["name"], reordered["public"]))
    show("empty name", error(rest("createPlaylist", name="")))
    big_ids = (ids * 100)[:3000]
    big = rest("createPlaylist", post=True, name="Probe big", songId=big_ids)
    show("create 3000 entries", error(big))
    if big["status"] == "ok":
        show("big songCount, entries returned", (big["playlist"]["songCount"], len(big["playlist"].get("entry", []))))
    show("playlist with comment 5000 chars", error(rest("updatePlaylist", post=True, playlistId=pid, comment="x" * 5000)))
    show("stored comment length", len(rest("getPlaylist", id=pid)["playlist"].get("comment", "")))
    show("name unicode", rest("createPlaylist", name="Wiedergabe – Schön \U0001F3BB", songId=ids[0])["playlist"]["name"])
    bad = rest("createPlaylist", name="bad", songId=["nope", ids[0]])
    show("playlist with unknown song id", (error(bad), bad.get("playlist", {}).get("songCount")))
    album_id = pick()[1][0]["id"]
    bad = rest("createPlaylist", name="bad2", songId=[album_id])
    show("playlist with album id", (error(bad), bad.get("playlist", {}).get("songCount")))
    show("getPlaylists owner and public keys", [(p["name"], p.get("public"), p["songCount"]) for p in rest("getPlaylists")["playlists"]["playlist"]])


def bookmarks():
    head("bookmarks")
    songs, albums, *_ = pick()
    a, b = songs[0], songs[1]
    show("create song a at 12 s", error(rest("createBookmark", id=a["id"], position=12000, comment="first")))
    show("create song a at 34 s (same song)", error(rest("createBookmark", id=a["id"], position=34000, comment="second")))
    show("create song b", error(rest("createBookmark", id=b["id"], position=5000)))
    show("create on album id", error(rest("createBookmark", id=albums[0]["id"], position=1000)))
    show("create on unknown id", error(rest("createBookmark", id="nope", position=1000)))
    show("create negative position", error(rest("createBookmark", id=songs[2]["id"], position=-5)))
    show("position beyond duration", error(rest("createBookmark", id=songs[3]["id"], position=99999999)))
    listing = rest("getBookmarks")["bookmarks"]["bookmark"]
    show("getBookmarks", [(x["entry"]["id"] == a["id"], x["position"], x.get("comment"), x["username"]) for x in listing])
    show("bookmark keys", sorted(listing[0]))
    show("other user getBookmarks", rest("getBookmarks", user=OTHER)["bookmarks"])
    show("comment 3000 chars", error(rest("createBookmark", post=True, id=songs[4]["id"], position=1, comment="y" * 3000)))
    show("stored comment length", [len(x.get("comment", "")) for x in rest("getBookmarks")["bookmarks"]["bookmark"] if x["entry"]["id"] == songs[4]["id"]])
    for s in songs[5:25]:
        rest("createBookmark", id=s["id"], position=1)
    show("bookmark count after 25 songs", len(rest("getBookmarks")["bookmarks"]["bookmark"]))
    rest("deleteBookmark", id=a["id"])
    show("after deleteBookmark a", a["id"] in [x["entry"]["id"] for x in rest("getBookmarks")["bookmarks"]["bookmark"]])
    show("getSong has bookmark field", "bookmarkPosition" in rest("getSong", id=b["id"])["song"])
    show("song bookmarkPosition", rest("getSong", id=b["id"])["song"].get("bookmarkPosition"))


def play_queue():
    head("play queue")
    songs, *_ = pick()
    ids = [s["id"] for s in songs]
    show("save 5 ids, current 3rd, position 4321", error(rest("savePlayQueue", client="Klassik-A", id=ids[:5], current=ids[2], position=4321)))
    queue = rest("getPlayQueue")["playQueue"]
    show("keys", sorted(queue))
    show("current, position, changedBy, username, entries", (queue["current"] == ids[2], queue["position"], queue.get("changedBy"), queue["username"], len(queue["entry"])))
    show("entries are full songs", sorted(queue["entry"][0])[:6])
    rest("savePlayQueue", client="Klassik-B", id=ids[5:7], current=ids[6], position=9)
    queue = rest("getPlayQueue", client="Klassik-A")["playQueue"]
    show("second client overwrites; changedBy", (len(queue["entry"]), queue["changedBy"]))
    show("other user getPlayQueue", rest("getPlayQueue", user=OTHER))
    show("current not in ids", error(rest("savePlayQueue", id=ids[:2], current=ids[10], position=1)))
    queue = rest("getPlayQueue").get("playQueue", {})
    show("queue after bad current: size, current is first id", (len(queue.get("entry", [])), queue.get("current") == ids[0]))
    show("no current", error(rest("savePlayQueue", id=ids[:2])))
    queue = rest("getPlayQueue")["playQueue"]
    show("queue without current: current is first id, position", (queue.get("current") == ids[0], queue.get("position")))
    rest("savePlayQueue", id=ids[:4], current=ids[2], position=77)
    by_index = rest("getPlayQueueByIndex")
    show("getPlayQueueByIndex", (error(by_index), {k: v for k, v in by_index.get("playQueueByIndex", {}).items() if k != "entry"}))
    big = (ids * 100)[:3000]
    show("save 3000 ids", error(rest("savePlayQueue", post=True, id=big, current=big[0], position=1)))
    show("stored size", len(rest("getPlayQueue")["playQueue"]["entry"]))
    show("save with no ids", error(rest("savePlayQueue")))
    show("getPlayQueue after empty save", rest("getPlayQueue").get("playQueue"))


def scrobbles():
    head("scrobble and play counts")
    songs, albums, composer, performer = pick()
    s = rest("getSong", id=songs[7]["id"])["song"]
    album_before = rest("getAlbum", id=s["albumId"])["album"]
    show("before: playCount, played", (s.get("playCount"), s.get("played")))
    show("album before playCount, played", (album_before.get("playCount"), album_before.get("played")))
    show("scrobble submission=false", error(rest("scrobble", id=s["id"], submission="false")))
    now = rest("getNowPlaying", user=OTHER)["nowPlaying"].get("entry", [])
    show("other user getNowPlaying", [(e["id"] == s["id"], e["username"], e["minutesAgo"], e["playerName"]) for e in now])
    after = rest("getSong", id=s["id"])["song"]
    show("after submission=false: playCount, played", (after.get("playCount"), after.get("played")))
    past = 1700000000000
    show("scrobble submission=true time=2023-11-14", error(rest("scrobble", id=s["id"], time=past, submission="true")))
    after = rest("getSong", id=s["id"])["song"]
    show("after: playCount, played", (after.get("playCount"), after.get("played")))
    show("scrobble true again, no time", error(rest("scrobble", id=s["id"])))
    after = rest("getSong", id=s["id"])["song"]
    show("after: playCount, played", (after.get("playCount"), after.get("played")))
    show("scrobble true with older time", error(rest("scrobble", id=s["id"], time=past - 86400000, submission="true")))
    show("played after older time (does it go back?)", rest("getSong", id=s["id"])["song"].get("played"))
    show("scrobble two ids with two times", error(rest("scrobble", id=[songs[8]["id"], songs[9]["id"]], time=[past, past + 1000])))
    show("scrobble unknown id", error(rest("scrobble", id="nope")))
    show("scrobble album id", error(rest("scrobble", id=albums[0]["id"])))
    album_after = rest("getAlbum", id=s["albumId"])["album"]
    show("album after: playCount, played", (album_after.get("playCount"), album_after.get("played")))
    artist_id = s["artistId"] if "artistId" in s else s["artists"][0]["id"]
    artist = rest("getArtist", id=artist_id)["artist"]
    show("artist keys with listener data", [k for k in artist if k in ("playCount", "played", "starred", "userRating")])
    composer_after = rest("getArtist", id=composer["id"])["artist"]
    show("composer playCount, played", (composer_after.get("playCount"), composer_after.get("played")))
    show("other user sees my playCount", rest("getSong", user=OTHER, id=s["id"])["song"].get("playCount"))
    show("getAlbumList2 frequent", [(a["name"], a.get("playCount")) for a in rest("getAlbumList2", type="frequent")["albumList2"].get("album", [])])
    show("getAlbumList2 recent", [(a["name"], a.get("played")) for a in rest("getAlbumList2", type="recent")["albumList2"].get("album", [])])
    show("getAlbumList2 frequent as other", rest("getAlbumList2", user=OTHER, type="frequent")["albumList2"])
    show("getNowPlaying after submission=true", [e["id"] for e in rest("getNowPlaying")["nowPlaying"].get("entry", [])])
    show("song keys that carry listener data", [k for k in sorted(after) if k in ("playCount", "played", "starred", "userRating", "averageRating", "bookmarkPosition")])


if __name__ == "__main__":
    print("Navidrome:", rest("ping").get("serverVersion"))
    make_other_user()
    for step in (star, rating, playlists, bookmarks, play_queue, scrobbles):
        step()
