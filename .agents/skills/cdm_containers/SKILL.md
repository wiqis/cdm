---
name: cdm_containers
description: ChemicalDM container/card-type architecture — non-schedulable container items (ITEM_TYPE_PLAYLIST / ITEM_TYPE_YT_SINGLE) that represent YouTube jobs as real DownloadItems, parent/child nesting via card_type + parent_id, container lifecycle helpers in DownloadManager, UI card dispatch, and the persistence rule (containers are never saved). Load when touching YouTube job cards, item nesting, or queue rendering.
---

# ChemicalDM container items (card_type system)

A YouTube job (playlist or single video+audio merge) is represented in the queue as a
**container item**: a real `DownloadItem` that shows as a card but is NEVER scheduled.
Its children (video/audio streams) are also real `DownloadItem`s — actually downloaded by
the engine — but they are **nested inside the parent card**, never shown top-level.

## The types (`cdmlib/src/Constants.ch`)

```chemical
public const ITEM_TYPE_NORMAL    : int = 0   // a regular download
public const ITEM_TYPE_PLAYLIST  : int = 1   // a YouTube playlist container
public type  ITEM_TYPE_YT_SINGLE : int = 2   // a single YouTube video container
public const ITEM_TYPE_YT_CHILD  : int = 3   // a video/audio stream belonging to a container
```

Mirror ints in the UI (`CdmApp.ch`): `CARD_NORMAL=0, CARD_PLAYLIST=1, CARD_YT_SINGLE=2,
CARD_YT_CHILD=3`. `DownloadItem.card_type` and `DownloadItem.parent_id` live in
`cdmlib/src/Model.ch`; the engine never interprets them (same "opaque tag" philosophy as
`category`).

## Container lifecycle (cdmlib API, `DownloadManager.ch`)

| Helper | Purpose |
|--------|---------|
| `create_container_item(dm, card_type, url, dir, name) -> id` | Inserts a `DownloadItem` with `state = STATE_DOWNLOADING` — deliberately NOT `STATE_QUEUED`, so `start_pending` (which only picks QUEUED) never spawns a worker for it. Progress is driven externally. |
| `set_item_card_type(dm, id, card_type, parent_id) -> bool` | Tags a child with its type + parent id (under `items_mutex`). |
| `set_item_state_progress(dm, id, state, downloaded, total) -> bool` | The async yt-dlp poll drives the container's header state/progress through this. |

The flow (`src/core/YtAsync.ch`):

```
single video:  start_async_download
                 → g_async_dl.container_id = create_container_item(dm, ITEM_TYPE_YT_SINGLE, ...)
                 → add_task_ex(video) → add_task_ex(audio)
                 → set_item_card_type(child, ITEM_TYPE_YT_CHILD, container_id)   // per child
                 → poll_async_download merges aggregate into set_item_state_progress(container)
playlist:      start_async_playlist_download
                 → g_async_pl.container_id = create_container_item(dm, ITEM_TYPE_PLAYLIST, ...)
                 → per entry: do_item_download → children tagged YT_CHILD + parent = container_id
```

## Wire format (`src/core/JsonBuild.ch item_to_json`)

Every item carries `card_type` (int) and `parent_id` (string, empty for top-level). The
UI nests children by matching `parent_id` against the container id.

## UI card dispatch (`src/ui/CdmApp.ch`)

```js
var CARD_NORMAL = 0, CARD_PLAYLIST = 1, CARD_YT_SINGLE = 2, CARD_YT_CHILD = 3
var mainItems = items.filter((u) => u.card_type !== CARD_YT_CHILD)   // children hidden
// per card:
if(item.card_type === CARD_PLAYLIST)  return renderPlaylistCard(item)
if(item.card_type === CARD_YT_SINGLE) return renderYtVideoCard(item)
return renderNormalCard(item)
```

- The playlist card renders its per-video rows from the **poll payload**
  (`yt_download_playlist_poll` → `videos` array), not from DM items — the card is a
  view over the async job state, while the DM children only provide per-stream
  segmented progress bars (matched by task id).
- `ytPlContainerId` (JS state) captures `d.container_id` from the poll for card-side
  progress sync.
- NOTE: an older approach tracked child ids in a `ytPlTaskIds` map — **gone**. The
  `card_type` filter replaced it; do not reintroduce id-map filtering.

## Persistence rule (important)

`save_queue` and the shutdown progress writer (`Settings.ch`) **skip every item whose
`card_type != ITEM_TYPE_NORMAL`**:

> Playlist containers and their nested video/audio children are driven by yt-dlp and are
> not resumable as standalone DM tasks across restarts.

So after a restart, YouTube jobs vanish from the queue; cross-session recovery for those
happens through the yt_links file + `refresh_stale_yt_links` (see `yt_playlist` skill).
`periodic_save_progress` (cdmlib) applies the same filter via `ITEM_TYPE_NORMAL` check.

## Gotchas

1. **Containers must not be QUEUED.** `create_container_item` forces
   `STATE_DOWNLOADING` — a QUEUED container would be picked up by `start_pending`, which
   would try to download the playlist/HTML URL as if it were a file.
2. **cancel/remove must hit the container AND its children** — cancelling only the
   container card leaves orphan children downloading. The yt cancel paths
   (`yt_cancel`/`cancel_async_playlist_download`) handle this; don't bypass them.
3. UI mirrors of the int constants must stay in sync with `Constants.ch` — the JSON
   carries plain ints, and the UI matches them numerically.
4. If you add a new card type, update: `Constants.ch`, the UI `CARD_*` consts, the card
   dispatcher in CdmApp, and the `ITEM_TYPE_NORMAL` filters in Settings.ch +
   DownloadManager.ch (anything that only applies to "real" downloads).
