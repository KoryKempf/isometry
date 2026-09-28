# Supabase

`migrations/` records the schema changes applied to the production project
(`rzqfjaunlbbpradtgujl`), named with the versions Supabase assigned them.

| Migration | What it does |
|---|---|
| `harden_puzzle_access` | Removes the public insert policies on `daily_puzzles` and `puzzle_fingerprints`; puzzles become readable only once their day starts (US Eastern). |
| `server_side_results` | Adds `daily_puzzles.name`, new result columns, and `submit_result()`, which checks a submitted build against the puzzle's views before saving it and advances streaks server-side. |
| `rebalance_future_puzzles` | Backs up `daily_puzzles` to `backup.daily_puzzles_20260928`, schedules 12 hand-built Sunday puzzles (Medium), and re-orders every future day so Easy < Medium < Hard. |

## After deploying the new client

Run `post-deploy/lockdown_results_and_profiles.sql`. It removes the browser's
direct write access to `puzzle_results` and to the streak columns in
`profiles`, so results and streaks can only change through `submit_result()`.
Running it earlier would break result syncing for anyone still on the old page.

## Puzzle generation

Puzzles are pre-generated through 2031-04-18. The `generate-daily-puzzles` cron
job still calls an edge function that no longer exists (it gets a 404 daily).
Any future generator must write with the service-role key: the anon key can no
longer insert puzzles.
