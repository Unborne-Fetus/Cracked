CREATE TABLE IF NOT EXISTS scores (day TEXT NOT NULL, player TEXT NOT NULL, distance REAL NOT NULL, speed REAL NOT NULL, seconds REAL NOT NULL, PRIMARY KEY(day,player));
CREATE INDEX IF NOT EXISTS score_ranking ON scores(day,distance DESC);
