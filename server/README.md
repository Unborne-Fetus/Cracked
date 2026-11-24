# Optional daily leaderboard

This source is not deployed automatically by GitHub Pages. Create a Cloudflare D1 database, copy wrangler.example.toml to wrangler.toml, set the database ID, apply schema.sql, and deploy the Worker. Set velocity/leaderboard_url in Godot ProjectSettings to the Worker HTTPS URL before exporting. Do not embed a secret in a client build. Public scores contain only random anonymous runner IDs and gameplay statistics. This prototype accepts unverified client reports; production competition needs replay verification, abuse limits and a version-specific board.

GET /scores?day=YYYY-MM-DD returns the top 50. POST /scores accepts the current UTC day's score and returns rank plus the board.
