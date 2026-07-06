# Ranked Matchmaking Player Guide

This is the short version of how SoulCalibur VI ranked search appears to work
from the game's matchmaking logic. It is written for players, not modders.

## The Big Idea

Ranked search is not just "find anyone online." The game creates a ranked
ticket with your current character/style rank, connection preferences, region
settings, and a small "previous result" bucket.

When another player is found, the game is trying to satisfy several filters at
once. The most important ones are:

- rank range
- connection/search quality
- area/language settings
- previous-result bucket
- session availability

## Rank Range

The game starts by looking close to your current rank.

It stores:

| Value | Meaning |
|---|---|
| Your rank | Your current character/style rank. |
| Lower rank | The lowest rank you are willing to match. |
| Higher rank | The highest rank you are willing to match. |

The match only works if both players fit each other's ranges:

```text
Their rank must fit inside your allowed range.
Your rank must fit inside their allowed range.
```

That means two players can miss each other even if one side would accept the
match, because the other player's search range may still be too narrow.

## The Range Expands Over Time

At first, ranked search is strict. If it keeps retrying, the rank range expands.

Approximate expansion:

| Search time | Rank range |
|---:|---|
| `0-8` seconds | exact rank |
| `8-16` seconds | about `+/- 2` ranks |
| `16-24` seconds | about `+/- 4` ranks |
| `24-32` seconds | about `+/- 6` ranks |
| `32-40` seconds | about `+/- 10` ranks |
| `40+` seconds | effectively all ranks |

So if you want a closer-ranked opponent, restarting search before it expands
too far may help. If you just want a match, letting it run longer makes the
game accept wider rank gaps.

## Previous Result

Ranked search also uses your recent result state.

In simple terms:

| Your recent state | First-search bucket |
|---|---:|
| You are on a winning streak / last result counts as winning | `1` |
| You are not on a winning streak / last result counts as not winning | `2` |

On the first fresh search, the game tries to match players in the same bucket.
So if you won your last game and your friend lost theirs, the first search is
less likely to pair you together.

This is not permanent. After the search retries, this filter can be relaxed,
and then players from different previous-result buckets can match.

## Same Opponent

The ranked search does not appear to have a direct "do not match the same
person again" rule.

It does not search by "last opponent." It searches by session metadata such as
rank range and previous-result bucket. If it feels like the game avoids a
repeat opponent, that is probably because the rank/result/search filters are
changing who is eligible, not because the game stored that opponent's identity
as a blacklist.

## Practical Takeaways

- Early search is stricter.
- Longer search allows wider rank gaps.
- Around 40 seconds, ranked search can become very broad.
- Winning players are initially nudged toward other winning-bucket players.
- Losing or zero-streak players are initially nudged toward the other bucket.
- After retries, the previous-result filter can turn off.
- The game does not appear to directly block rematching the same person by
  identity.

If you are trying to queue into a specific friend, matching your recent result
state and letting the search expand makes it more likely. If you want tighter
ranked matches, restart search before it gets too wide.
