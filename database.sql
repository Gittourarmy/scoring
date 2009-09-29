-- Use InnoDB for transaction support?
-- SET storage_engine=InnoDB;

DROP TABLE IF EXISTS deaths_to_distinct_uniques;
DROP TABLE IF EXISTS deaths_to_uniques;
DROP TABLE IF EXISTS player_maxed_skills;
DROP TABLE IF EXISTS player_banners;
DROP TABLE IF EXISTS player_won_gods;
DROP TABLE IF EXISTS active_streaks;
DROP TABLE IF EXISTS most_recent_character;
DROP TABLE IF EXISTS streaks;
DROP TABLE IF EXISTS ziggurats;
DROP TABLE IF EXISTS rune_finds;
DROP TABLE IF EXISTS kunique_times;
DROP TABLE IF EXISTS kills_of_uniques;
DROP TABLE IF EXISTS kills_of_ghosts;
DROP TABLE IF EXISTS kills_by_ghosts;
DROP TABLE IF EXISTS milestone_bookmark;
DROP TABLE IF EXISTS milestones;
DROP VIEW IF EXISTS class_highscores;
DROP VIEW IF EXISTS species_highscores;
DROP VIEW IF EXISTS combo_highscores;
DROP TABLE IF EXISTS combo_highscores;
DROP TABLE IF EXISTS class_highscores;
DROP TABLE IF EXISTS species_highscores;
DROP TABLE IF EXISTS games;
DROP TABLE IF EXISTS players;

DROP VIEW IF EXISTS fastest_realtime;
DROP VIEW IF EXISTS fastest_turncount;
DROP VIEW IF EXISTS combo_win_highscores;
DROP VIEW IF EXISTS class_highscores;
DROP VIEW IF EXISTS game_species_highscores;
DROP VIEW IF EXISTS game_class_highscores;
DROP VIEW IF EXISTS game_combo_highscores;
DROP VIEW IF EXISTS clan_combo_highscores;
DROP VIEW IF EXISTS clan_total_scores;
DROP VIEW IF EXISTS clan_unique_kills;
DROP VIEW IF EXISTS game_combo_win_highscores;
DROP VIEW IF EXISTS combo_hs_scoreboard;
DROP VIEW IF EXISTS combo_hs_clan_scoreboard;
DROP VIEW IF EXISTS streak_scoreboard;
DROP VIEW IF EXISTS best_ziggurat_dives;
DROP VIEW IF EXISTS youngest_rune_finds;
DROP VIEW IF EXISTS most_deaths_to_uniques;
DROP VIEW IF EXISTS double_boris_kills;
DROP VIEW IF EXISTS atheist_wins;
DROP VIEW IF EXISTS super_sigmund_kills;
DROP VIEW IF EXISTS free_will_wins;
DROP VIEW IF EXISTS ghostbusters;
DROP VIEW IF EXISTS compulsive_shoppers;
DROP VIEW IF EXISTS most_pacific_wins;

CREATE TABLE IF NOT EXISTS players (
  name VARCHAR(20) PRIMARY KEY,
  games_played INT DEFAULT 0,
  games_won INT DEFAULT 0,
  total_score BIGINT,
  best_score BIGINT,
  best_scoring_game BIGINT
  );
CREATE INDEX player_total_scores ON players (name, total_score);
  
-- For mappings of logfile fields to columns, see loaddb.py
CREATE TABLE games (
  id BIGINT AUTO_INCREMENT,
  
  -- Source logfile
  source_file VARCHAR(150),
  -- Offset in the source file.
  source_file_offset BIGINT,

  player VARCHAR(20),
  start_time DATETIME,
  score BIGINT,
  race VARCHAR(20),
  -- Two letter race abbreviation so we can group by it without pain.
  raceabbr CHAR(2) NOT NULL,
  class VARCHAR(20),
  version CHAR(10),
  lv CHAR(8),
  uid INT,
  charabbrev CHAR(4),
  xl INT,
  skill VARCHAR(16),
  sk_lev INT,
  title VARCHAR(255),
  place CHAR(16),
  branch CHAR(16),
  lvl INT,
  ltyp CHAR(16),
  hp INT,
  maxhp INT,
  maxmaxhp INT,
  strength INT,
  intelligence INT,
  dexterity INT,
  god VARCHAR(20),
  duration INT,
  turn BIGINT,
  runes INT DEFAULT 0,
  killertype VARCHAR(20),
  killer CHAR(50),
  kgroup CHAR(50),
  kaux VARCHAR(255),
  -- Kills may be null.
  kills INT,
  damage INT,
  piety INT,
  penitence INT,
  gold INT,
  gold_found INT,
  gold_spent INT,
  end_time DATETIME,
  terse_msg VARCHAR(255),
  verb_msg VARCHAR(255),
  nrune INT DEFAULT 0,

  CONSTRAINT PRIMARY KEY (id)
  );

CREATE INDEX games_source_offset ON games (source_file, source_file_offset);

CREATE INDEX games_scores ON games (player, score);
CREATE INDEX games_kgrp ON games (kgroup);
CREATE INDEX games_charabbrev_score ON games (charabbrev, score);
CREATE INDEX games_ktyp ON games (killertype);
CREATE INDEX games_p_ktyp ON games (player, killertype);

-- Index to find games with fewest kills.
CREATE INDEX games_kills ON games (killertype, kills);

-- Index to help us find fastest wins (time) quick.
CREATE INDEX games_win_dur ON games (killertype, duration);

-- Index to help us find fastest wins (turncount) quick.
CREATE INDEX games_win_turn ON games (killertype, turn);

CREATE TABLE combo_highscores AS
SELECT * FROM games;
ALTER TABLE combo_highscores DROP COLUMN id;

CREATE INDEX ch_player ON combo_highscores (player, killertype, score);
CREATE INDEX ch_killer ON combo_highscores (killertype);

CREATE TABLE species_highscores AS
SELECT * FROM games;
ALTER TABLE species_highscores DROP COLUMN id;
CREATE INDEX sh_player ON species_highscores (player, killertype, score);
CREATE INDEX sh_killer ON species_highscores (killertype);

CREATE TABLE class_highscores AS
SELECT * FROM games;
ALTER TABLE class_highscores DROP COLUMN id;
CREATE INDEX clh_player ON class_highscores (player, killertype, score);
CREATE INDEX clh_killer ON class_highscores (killertype);

CREATE TABLE milestones (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  -- Source milestone file
  source_file VARCHAR(150),

  -- The actual game that this milestone is linked with.
  game_id BIGINT,

  version VARCHAR(10),
  cv VARCHAR(10),
  player VARCHAR(20),
  race VARCHAR(20),
  raceabbr CHAR(2) NOT NULL,
  class VARCHAR(20),
  charabbrev CHAR(4),
  xl INT,
  skill VARCHAR(16),
  sk_lev INT,
  title VARCHAR(50),
  place VARCHAR(16),

  branch VARCHAR(16),
  lvl INT,
  ltyp VARCHAR(16),
  hp INT,
  maxhp INT,
  maxmaxhp INT,
  strength INT,
  intelligence INT,
  dexterity INT,
  god VARCHAR(50),
  duration BIGINT,
  turn BIGINT,
  runes INT,
  nrune INT,

  -- Game start time.
  start_time DATETIME,

  -- Milestone time.
  milestone_time DATETIME,

  -- Known milestones: abyss.enter, abyss.exit, rune, orb, ghost, uniq,
  -- uniq.ban, br.enter, br.end.
  verb VARCHAR(20),
  noun VARCHAR(100),

  -- The actual milestone message.
  milestone VARCHAR(255),

  FOREIGN KEY (game_id) REFERENCES games (id)
  ON DELETE SET NULL
);

CREATE INDEX milestone_verb ON milestones (player, verb);
CREATE INDEX milestone_noun ON milestones (noun, verb, player, start_time);
-- To find milestones belonging to a particular game.
CREATE INDEX milestone_lookup_by_time ON milestones (player, start_time, verb);

-- A table to keep track of the last milestone we've processed. This
-- will have only one row for one filename.
CREATE TABLE milestone_bookmark (
  source_file VARCHAR(150) PRIMARY KEY,
  source_file_offset BIGINT
  );

CREATE TABLE kills_by_ghosts (
  killed_player VARCHAR(20) NOT NULL,
  killed_start_time DATETIME NOT NULL,
  killer VARCHAR(20) NOT NULL
  );

CREATE TABLE kills_of_ghosts (
  player VARCHAR(20),
  start_time DATETIME,
  ghost VARCHAR(20)
  );

CREATE TABLE kills_of_uniques (
  player VARCHAR(20) NOT NULL,
  kill_time DATETIME NOT NULL,
  monster VARCHAR(20),
  FOREIGN KEY (player) REFERENCES players (name)
  );

CREATE INDEX kill_uniq_pmons ON kills_of_uniques (player, monster);

-- Keep track of who's killed how many uniques, and when they achieved this.
CREATE TABLE kunique_times (
  player VARCHAR(20) PRIMARY KEY,
  -- Number of distinct uniques slain.
  nuniques INT DEFAULT 0 NOT NULL,
  -- When this number was reached.
  kill_time DATETIME NOT NULL,
  FOREIGN KEY (player) REFERENCES players (name) ON DELETE CASCADE
  );

CREATE TABLE rune_finds (
  player VARCHAR(20),
  start_time DATETIME,
  rune_time DATETIME,
  rune VARCHAR(20),
  xl INT,
  FOREIGN KEY (player) REFERENCES players (name) ON DELETE CASCADE
  );
CREATE INDEX rune_finds_p ON rune_finds (player, rune);

CREATE TABLE ziggurats (
  player VARCHAR(20),
  deepest INT NOT NULL,
  place VARCHAR(10) NOT NULL,
  zig_time DATETIME NOT NULL,
  -- Game start time, with player name can be used to locate the relevant game.
  start_time DATETIME NOT NULL,
  FOREIGN KEY (player) REFERENCES players (name)
  );
CREATE INDEX ziggurat_depths ON ziggurats (deepest, zig_time);

CREATE TABLE active_streaks (
  player VARCHAR(20) PRIMARY KEY,
  streak MEDIUMINT DEFAULT 1,
  streak_time DATETIME NOT NULL,
  FOREIGN KEY (player) REFERENCES players (name)
  );

-- This is to show the last character played under 'active streaks'
CREATE TABLE most_recent_character (
  player VARCHAR(20) PRIMARY KEY,
  charabbrev CHAR(4) NOT NULL,
  update_time DATETIME NOT NULL,
  FOREIGN KEY (player) REFERENCES players (name)
  );

-- Generated table to keep track of streaks for each player.
CREATE TABLE streaks (
  player VARCHAR(20) PRIMARY KEY,
  -- Because you just know Stabwound's going to win 128 in a row
  streak MEDIUMINT NOT NULL,
  streak_time DATETIME NOT NULL,
  FOREIGN KEY (player) REFERENCES players (name)
  );

CREATE TABLE player_won_gods (
  player VARCHAR(20),
  god VARCHAR(20),
  FOREIGN KEY (player) REFERENCES players (name) ON DELETE CASCADE
);
CREATE INDEX player_won_gods_pg ON player_won_gods (player, god);

-- Audit table for point assignment. Tracks both permanent and
-- temporary points.

CREATE TABLE deaths_to_uniques (
  player  VARCHAR(20),
  uniq    VARCHAR(50),
  start_time DATETIME,
  end_time   DATETIME,
  FOREIGN KEY (player) REFERENCES players (name)
  );
CREATE INDEX deaths_to_uniques_p ON deaths_to_uniques (player);

CREATE TABLE deaths_to_distinct_uniques (
  player VARCHAR(20),
  ndeaths INT,
  death_time DATETIME,
  PRIMARY KEY (player),
  FOREIGN KEY (player) REFERENCES players (name)
  );
CREATE INDEX deaths_to_distinct_uniques_p
ON deaths_to_distinct_uniques (player, ndeaths);

CREATE TABLE player_maxed_skills (
  player VARCHAR(20),
  skill VARCHAR(25),
  PRIMARY KEY (player, skill),
  FOREIGN KEY (player) REFERENCES players (name)
  );
CREATE INDEX player_maxed_sk ON player_maxed_skills (player, skill);

-- Tracks banners won by each player. Banners (badges?) are permanent
-- decorations, so once a player has earned a banner, there's no need to
-- check it again.
CREATE TABLE player_banners (
  player VARCHAR(20),
  banner VARCHAR(50),
  prestige INT NOT NULL,
  temp BOOLEAN,
  PRIMARY KEY (player, banner),
  FOREIGN KEY (player) REFERENCES players (name)
  );
CREATE INDEX player_banners_player ON player_banners (player);

-- Views for trophies

-- The three fastest realtime wins. Ties are broken by who got there first.
CREATE VIEW fastest_realtime AS
SELECT id, player, duration
  FROM games
 WHERE killertype = 'winning'
 ORDER BY duration, end_time
 LIMIT 3;

-- The three fastest wins (turncount)
CREATE VIEW fastest_turncount AS
SELECT id, player, turn
  FROM games
 WHERE killertype = 'winning'
ORDER BY turn, end_time
LIMIT 3;

CREATE VIEW most_pacific_wins AS
SELECT id, player, kills
  FROM games
 WHERE killertype = 'winning' AND kills IS NOT NULL
ORDER BY kills
 LIMIT 3;

CREATE VIEW game_combo_win_highscores AS
SELECT *
FROM combo_highscores
WHERE killertype = 'winning';

CREATE VIEW combo_hs_scoreboard AS
SELECT player, COUNT(*) AS nscores
FROM combo_highscores
GROUP BY player
ORDER BY nscores DESC
LIMIT 3;

CREATE VIEW streak_scoreboard AS
SELECT player, streak
FROM streaks
ORDER BY streak DESC, streak_time
LIMIT 3;

CREATE VIEW best_ziggurat_dives AS
SELECT player, deepest, place, zig_time, start_time
  FROM ziggurats
ORDER BY deepest DESC, zig_time
LIMIT 3;

CREATE VIEW youngest_rune_finds AS
SELECT player, rune, start_time, rune_time, xl
  FROM rune_finds
 WHERE rune != 'abyssal'
ORDER BY xl, rune_time
 LIMIT 5;

CREATE VIEW most_deaths_to_uniques AS
SELECT player, ndeaths, death_time
  FROM deaths_to_distinct_uniques
ORDER BY ndeaths DESC, death_time
 LIMIT 3;

CREATE VIEW double_boris_kills AS
  SELECT player, COUNT(*) AS boris_kills
    FROM milestones
   WHERE noun='Boris'
     AND verb='uniq'
GROUP BY player, start_time
  HAVING boris_kills >= 2
ORDER BY boris_kills DESC;

CREATE VIEW atheist_wins AS
SELECT g.*
  FROM games g
 WHERE g.killertype = 'winning'
   AND (g.god IS NULL OR g.god = '')
   AND g.raceabbr != 'DG'
   AND NOT EXISTS (SELECT noun FROM milestones m
                    WHERE m.player = g.player AND m.start_time = g.start_time
                      AND verb = 'god.renounce' LIMIT 1);

CREATE VIEW super_sigmund_kills AS
SELECT player, COUNT(*) AS sigmund_kills
  FROM kills_of_uniques
 WHERE monster = 'Sigmund'
GROUP BY player
  HAVING sigmund_kills >= 27
ORDER BY sigmund_kills DESC;

CREATE VIEW free_will_wins AS
SELECT *
  FROM games
 WHERE killertype = 'winning'
   AND ((class = 'Fire Elementalist' AND skill = 'Ice Magic') OR
        (class = 'Ice Elementalist' AND skill = 'Fire Magic') OR
        (class = 'Earth Elementalist' AND skill = 'Air Magic') OR
        (class = 'Air Elementalist' AND skill = 'Earth Magic'))
   AND sk_lev = 27;

CREATE VIEW ghostbusters AS
SELECT player, COUNT(*) AS ghost_kills
  FROM milestones
 WHERE verb = 'ghost'
GROUP BY player
  HAVING ghost_kills >= 10
ORDER BY ghost_kills DESC;

CREATE VIEW compulsive_shoppers AS
SELECT *
  FROM games
 WHERE gold_spent >= 5000
   AND gold < 50;