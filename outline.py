#!/usr/bin/python

import loaddb
import query
import banner

import logging
from logging import debug, info, warn, error
import crawl_utils
import crawl
import uniq

from loaddb import query_do, query_first_col, wrap_transaction
from query import assign_points, assign_team_points
from query import log_temp_points, log_temp_team_points, get_points

import nemchoice

# So there are a few problems we have to solve:
# 1. Intercepting new logfile events
#    DONE: parsing a logfile line
#    DONE: dealing with deaths
# 2. Intercepting new milestone events
#    DONE: parsing a milestone line
#    How do we write milestone lines into the db?
# 3. DONE: Collecting data from whereis files
# 4. Determining who is the winner of various competitions based on the
#    ruleset: this still needs to be done for the ones that are basically
#    a complicated query.
# 5. Causing the website to be updated with who is currently winning everything
#    and, if necessary, where players are: first priority is a "who is winning
#    the obvious things"

class OutlineListener (loaddb.CrawlEventListener):
  def logfile_event(self, cursor, logdict):
    act_on_logfile_line(cursor, logdict)

  def milestone_event(self, cursor, milestone):
    act_on_milestone(cursor, milestone)

  def cleanup(self, db):
    cursor = db.cursor()
    try:
      update_player_scores(cursor)
    finally:
      cursor.close()

class OutlineTimer (loaddb.CrawlTimerListener):
  def run(self, cursor, elapsed):
    update_player_scores(cursor)

LISTENER = [ OutlineListener() ]

# Update player scores every so often.
TIMER = [ ( crawl_utils.UPDATE_INTERVAL, OutlineTimer() ) ]

def act_on_milestone(c, this_mile):
  """This function takes a milestone line, which is a string composed of key/
  value pairs separated by colons, and parses it into a dictionary.
  Then, depending on what type of milestone it is (key "type"), another
  function may be called to finish the job on the milestone line. Milestones
  have the same broken :: behavior as logfile lines, yay."""
  query.update_most_recent_character(c, this_mile['name'],
                                     this_mile['char'], this_mile['time'])
  if this_mile['type'] == 'unique' and \
        not this_mile['milestone'].startswith('banished '):
    do_milestone_unique(c, this_mile)
  if this_mile['type'] == 'rune':
    do_milestone_rune(c, this_mile)
  if this_mile['type'] == 'ghost':
    do_milestone_ghost(c, this_mile)

def do_milestone_unique(c, mile):
  """This function takes a parsed milestone known to commemorate the death of
  a unique, and checks to see if the player has already killed the unique.
  If so, it does nothing; if not, it marks that the player has killed the
  unique, and checks to see if the player has killed all uniques. If so,
  the player may be awarded points if they are one of the first to do so."""
  unique = loaddb.extract_unique_name(mile['milestone'])
  # DB already has the record for this kill, so == 1 => first kill.
  if query.count_player_unique_kills(c, mile['name'], unique) > 1:
    return
  assign_points(c, "unique", mile['name'], 5)

def do_milestone_rune(c, mile):
  """When the player gets a rune for the first time, they get ten points.
  After that, they get one point. This one is pretty simple."""
  # Check if this player already found this kind of rune. Remember the db
  # is already updated, so for the first rune the count will be 1.
  rune = loaddb.extract_rune(mile['milestone'])
  if query.player_count_runes(c, mile['name'], rune) > 1:
    # player_already_has_rune:
    assign_points(c, "rune:" + rune, mile['name'], 1)
  else:
    # first time getting this rune!
    assign_points(c, "rune_1st:" + rune, mile['name'], 10)
  player = mile['name']
  banner.safe_award_banner(c, player, 'discovered_language', 6)
  if (not banner.player_has_banner(c, player, 'runic_literacy')
      and query.player_count_distinct_runes(c, player) == crawl.NRUNES):
    banner.award_banner(c, player, 'runic_literacy', 12)

def do_milestone_ghost(c, mile):
  """When you kill a player ghost, you get two clan points! Otherwise this
  isn't terribly remarkable."""
  if not mile['milestone'].startswith('banished'):
    assign_team_points(c, "ghost", mile['name'], 2)

def act_on_logfile_line(c, this_game):
  """Actually assign things and write to the db based on a logfile line
  coming through. All lines get written to the db; some will assign
  irrevocable points and those should be assigned immediately. Revocable
  points (high scores, lowest dungeon level, fastest wins) should be
  calculated elsewhere."""
  if this_game['ktyp'] == 'winning':
    crunch_winner(c, this_game) # lots of math to do for winners

  crunch_misc(c, this_game)

  if loaddb.is_ghost_kill(this_game):
    ghost = loaddb.extract_ghost_name(this_game['killer'])
    XL = this_game['xl']
    if XL > 5:
      assign_team_points(c, "gkill", ghost, (XL - 5))

def crunch_misc(c, g):
  player = g['name']
  ktyp = g['ktyp']

  if ktyp != 'winning':
    query.kill_active_streak(c, player)

  banner.safe_award_banner(c, player, 'cartographer', 0)

  def strip_unique_qualifier(x):
    if ',' in x:
      p = x.index(',')
      return x[:p]
    return x

  killer = strip_unique_qualifier(g.get('killer') or '')
  if uniq.is_uniq(killer):
    query_do(c,
             '''INSERT INTO deaths_to_uniques
                            (player, uniq, start_time, end_time)
                     VALUES (%s, %s, %s, %s)''',
             player, killer, g['start'], g['end'])
    cuniqdeaths = query.count_deaths_to_distinct_uniques(c, player)
    olduniqdeaths = query.lookup_deaths_to_distinct_uniques(c, player)
    if cuniqdeaths > olduniqdeaths:
      query.update_deaths_to_distinct_uniques(c, player, cuniqdeaths,
                                              g['end'])

  if g.has_key('maxskills'):
    maxed_skills = g['maxskills'].split(",")
    for sk in maxed_skills:
      query.register_maxed_skill(c, player, sk)

def repeat_race_class(previous_chars, char):
  """Returns 0 if the game does not repeat a previous role or class, 1 if
  it repeats a role xor class, 2 if it repeats a role and a class."""
  repeats = 0
  if char[0:2] in [c[0:2] for c in previous_chars]:
    repeats += 1
  if char[2:] in [c[2:] for c in previous_chars]:
    repeats += 1
  return repeats

def crunch_winner(c, game):
  """A game that wins could assign a variety of irrevocable points for a
  variety of different things. This function needs to calculate them all."""

  player = game['name']
  charabbrev = game['char']

  query.update_active_streak(c, player, game['end'])

  debug("%s win (%s), runes: %d" % (player, charabbrev, game.get('urune') or 0))

  if nemchoice.is_nemelex_choice(charabbrev, game['end']):
    ban = 'nemelex_choice:' + charabbrev
    if not banner.player_has_banner(c, player, ban):
      assign_points(c, ban, player, 100)
      banner.award_banner(c, player, ban, 100, temp=False)

  if is_all_runer(game):
    all_allruners = number_of_allruners_before(c, game)
    assign_points(c, "nth_all_rune_win:%d" % (all_allruners + 1),
                  game['name'],
                  get_points(all_allruners, 200, 100, 50))

    # If this is my first all-rune win, 50 points!
    if query.count_wins(c, player = game['name'],
                        runes = query.MAX_RUNES,
                        before = game['end']) == 0:
      assign_points(c, "my_1st_all_rune_win", game['name'], 50)

  previous_wins = query.count_wins(c, before = game['end'])
  assign_points(c,
                "nth_win:%d" % (previous_wins + 1),
                game['name'], get_points(previous_wins, 200, 100, 50))

  my_wins = query.get_winning_games(c, player = game['name'],
                                    before = game['end'])
  n_my_wins = len(my_wins)

  def game_god(game):
    return game.get('god') or ''

  def banner_god(game):
    return (game.get('god') or 'none').lower().replace(' ', '_')

  # Assign 20 extra points for winning with a god that you haven't used before.
  if (not query.is_god_repeated(c, game['name'], game_god(game))
      and not query.did_change_god(c, game)):
    query.record_won_god(c, game['name'], game_god(game))
    assign_points(c, "win_god:" + banner_god(game), game['name'], 20)

  repeated = 0
  if n_my_wins > 0:
    repeated = repeat_race_class([x['charabbrev'] for x in my_wins],
                                 game['char'])

  if n_my_wins == 0:
    # First win! I bet you don't have a streak
    assign_points(c, "my_1st_win", game['name'], 100)

  elif n_my_wins == 1 and repeated == 0:
    # Second win! If neither repeated race or class, bonus!
    assign_points(c, "my_2nd_win_norep", game['name'], 50)

  else:
    # Any win gets 10 points at this point.
    assign_points(c, "my_win", game['name'], 10)

  # For one or more prior wins, check streaks
  if n_my_wins >= 1:
    # Check if this is a streak. streak_wins will be empty if not on
    # a streak.
    streak_wins = query.wins_in_streak_before(c, game['name'], game['end'])

    debug("%s win (%s), previous games in streak: %s" %
          (game['name'], game['char'], streak_wins))

    if streak_wins:
      streak_len = len(streak_wins) + 1
      # First update the streaks table. We're still in the logfile transaction
      # here, so it's safe.
      if streak_len > loaddb.longest_streak_count(c, game['name']):
        loaddb.update_streak_count(c, game, streak_len)

      streak_repeats = repeat_race_class(streak_wins, game['char'])

      # 100, 30, 10 points for streak games based on no repeat, xor, repeat.
      assign_points(c, "streak_win",
                    game['name'], get_points(streak_repeats, 100, 30, 10))

    # If this is a non-streak win, make sure we're not on the second
    # win with no repeats, since we've already done the bonus points
    # for that above.
    elif n_my_wins >= 2 or (n_my_wins == 1 and repeated == 1):
      assign_points(c, "my_nonstreak_norep",
                    game['name'], get_points(repeated, 30, 10))

def is_all_runer(game):
  """Did this game get every rune? This _might_ require checking the milestones
  associated with the start time..."""
  return game['urune'] == query.MAX_RUNES

def number_of_allruners_before(c, game):
  """How many all-runers happened before this game? We can stop at 3."""
  return query.count_wins(c, runes = query.MAX_RUNES, before = game['end'])

###################### Additional scoring math ##########################

def record_points(point_map, player, points, team_points):
  pdef = point_map.get(player.lower()) or { 'team': 0, 'you': 0 }
  pdef[team_points and 'team' or 'you'] += points
  point_map[player.lower()] = pdef

def player_additional_score(c, player, pmap):
  """Calculates the player's total score, including unchanging score and the
  current volatile score. Best-of-X trophies are not calculated here."""
  banner.process_banners(c, player)

def update_player_scores(c):
  wrap_transaction(safe_update_player_scores)(c)

def award_player_banners(c, banner_name, players, prestige=0):
  if players:
    for p in players:
      banner.safe_award_banner(c, p, banner_name, prestige)

def award_temp_trophy(c, point_map,
                      player_rows, key, points,
                      can_share_places=False, team_points=False):
  place = -1
  last_value = None

  def do_points(player, title, points):
    record_points(point_map, player, points, team_points)
    if team_points:
      log_temp_team_points(c, player, title, points)
    else:
      log_temp_points(c, player, title, points)
    banner.award_banner(c, player, title, points, temp=True)

  for row in player_rows:
    if not can_share_places or row[1] != last_value:
      place += 1
    if can_share_places:
      last_value = row[1]
    if place < len(points):
      title = key % (place + 1)
      p = points[place]
      player = row[0]
      do_points(player, title, p)

def apply_point_map(c, pmap):
  for player, points in pmap.iteritems():
    loaddb.update_player_fullscore(c, player,
                                   points['you'],
                                   points['team'])

def check_temp_trophies(c, pmap):
  award_temp_trophy(c, pmap, query.player_top_scores(c),
                    'top_score_Nth:%d', [200, 100, 50],
                    can_share_places=True)
  award_temp_trophy(c, pmap, query.player_fastest_realtime_win_best(c),
                    'fastest_realtime:%d', [200, 100, 50])

  award_temp_trophy(c, pmap, query.player_fastest_turn_win_best(c),
                    'fastest_turncount:%d', [200, 100, 50])

  award_temp_trophy(c, pmap, query.player_hs_combo_best(c),
                    'max_combo_hs_Nth:%d', [200, 100, 50],
                    can_share_places=True)

  award_temp_trophy(c, pmap, query.player_streak_best(c),
                    'max_streak_Nth:%d', [200, 100, 50])

  award_temp_trophy(c, pmap, query.get_top_unique_killers(c),
                    'top_uniq_killer:%d', [50, 20, 10])

  award_temp_trophy(c, pmap, query.player_pacific_win_best(c),
                    'top_pacific_win:%d', [200, 100, 50],
                    team_points=True)

  award_temp_trophy(c, pmap, query.player_xl1_dive_best(c),
                    'xl1_dive_Nth:%d', [50, 20, 10],
                    team_points=True)

  award_temp_trophy(c, pmap, query.get_top_ziggurats(c),
                    'zig_rank:%d', [200, 100, 50], team_points=True)

  award_temp_trophy(c, pmap, query.player_rune_dive_best(c),
                    'rune_dive_rank:%d', [50, 20, 10], team_points=True)

  award_temp_trophy(c, pmap, query.player_deaths_to_uniques_best(c),
                    'deaths_to_uniques_Nth:%d', [50, 20, 10],
                    can_share_places=False,
                    team_points=True)

def check_banners(c):
  # Award moose & squirrel banners.
  award_player_banners(c, 'moose',
                       query_first_col(c, '''SELECT DISTINCT player
                                             FROM double_boris_kills'''),
                       9)
  # Award 'Atheist' banners
  award_player_banners(c, 'atheist',
                       query_first_col(c, '''SELECT DISTINCT player
                                               FROM atheist_wins'''),
                       11)

  # Award 'Scythe' banners
  award_player_banners(c, 'scythe',
                       query_first_col(c, '''SELECT player
                                             FROM super_sigmund_kills'''),
                       9)

  # Award 'Orb' banner for wins.
  award_player_banners(c, 'orb',
                       query_first_col(c, '''SELECT DISTINCT player
                                               FROM games
                                              WHERE killertype='winning' '''),
                       10)

  award_player_banners(c, 'free_will',
                       query_first_col(c, '''SELECT DISTINCT player
                                             FROM free_will_wins'''),
                       12)
  award_player_banners(c, 'ghostbuster',
                       query_first_col(c,
                                       '''SELECT player FROM ghostbusters'''),
                       3)

  award_player_banners(c, 'shopaholic',
                       query_first_col(c,
                                       '''SELECT DISTINCT player
                                            FROM compulsive_shoppers'''),
                       3)


def check_misc_points(c, pmap):
  def award_misc_points(key, multiplier, rows):
    for r in rows:
      player = r[0]
      points = r[1] * multiplier
      record_points(pmap, player, points, team_points=False)
      log_temp_points(c, player, key % r[1], points)
  award_misc_points('combo_hs:%d', 5, query.all_hs_combos(c))
  award_misc_points('combo_hs_win:%d', 5, query.all_hs_combo_wins(c))
  award_misc_points('species_hs:%d', 10, query.all_hs_species(c))
  award_misc_points('class_hs:%d', 10, query.all_hs_classes(c))

def safe_update_player_scores(c):
  players = query.get_players(c)

  query.audit_flush_player(c)
  banner.flush_temp_banners(c)

  pmap = { }

  for p in players:
    record_points(pmap, p, 0, team_points=False)
    print "Processing banners for " + p
    banner.process_banners(c, p)

  check_misc_points(c, pmap)
  check_temp_trophies(c, pmap)
  check_banners(c)
  apply_point_map(c, pmap)

  # And award overall top banners.
  banner.assign_top_player_banners(c)
