# coding: utf-8
#
# Title:: Love Letter
# Author:: Jay Thomas <degradinglight@gmail.com>
# Copyright:: (C) 2013 gfax
# License:: GPL
# Version:: 2013-05-22
#

class LoveLetter

  Title = Irc.color(:red) + 'Love Letter' + NormalText

  Rounds = Struct.new(:played, :total)

  Cards = {
    :guard => {
      :value => 1,
      :quantity => 5,
      :keyword => /guard/,
      :text => 'Name a non-Guard card and choose another player; If ' +
               'that player has that card, he or she is out of the round.'
    },
    :priest => {
      :value => 2,
      :quantity => 2,
      :keyword => /priest/,
      :text => 'Look at another player\'s hand.'
    },
    :baron => {
      :value => 3,
      :quantity => 2,
      :keyword => /baron/,
      :text => 'You and another player secretly compare hands. ' +
               'The player with the lower value is out of the round. '
    },
    :handmaid => {
      :value => 4,
      :quantity => 2,
      :keyword => /maid/,
      :text => 'Until your next turn, ignore all ' +
               'effects from other players\' cards.'
    },
    :prince => {
      :value => 5,
      :quantity => 2,
      :keyword => /prince$/,
      :text => 'Choose any player (including yourself) to ' +
               'discard his or her hand and draw a new card.'
    },
    :king => {
      :value => 6,
      :quantity => 1,
      :keyword => /king/,
      :text => 'Trade hands with another player of your choice.'
    },
    :countess => {
      :value => 7,
      :quantity => 1,
      :keyword => /count/,
      :text => 'If you have this card and the King or Prince ' +
               'in your hand, you must discard this card.'
    },
    :princess => {
      :value => 8,
      :quantity => 1,
      :keyword => /princess/,
      :text => 'If you discard this card, you are out of the round.'
    }
  }


  class Card

    attr_reader :name, :value

    def initialize(name)
      @name = name
      @value = Cards[name][:value]
    end

    def to_s
      Irc.color(:red) + '[' + NormalText +
      name.to_s.capitalize + ' (' + value.to_s + ')' +
      Irc.color(:red) + ']' + NormalText
    end

  end


  class Player

    attr_accessor :user, :discard, :hand, :moved, :out, :rounds

    def initialize(user)
      @user = user
      @discard = nil
      @hand = []
      @moved = false
      @out = false
      @rounds = 0
    end

    def has?(card)
      return false if card.nil?
      if card.is_a? Symbol
        hand.each { |e| return true if card == e.name }
      elsif card.is_a? Card
        hand.each { |e| return true if card.name == e.name }
      end
      return false
    end

    def to_s
      Bold + user.to_s + Bold
    end
  end

  attr_reader :channel, :deck, :dropped, :join_timer,
              :manager, :players, :rounds, :started

  def initialize(plugin, channel, user, rounds)
    @bot = plugin.bot
    @channel = channel
    @plugin = plugin
    @registry = plugin.registry
    @deck = []        # card stock
    @dropped = []     # players booted from game
    @join_timer = nil # timer for countdown
    @manager = nil    # player in control of game
    @players = []     # players currently in game
    @reserve = []     # card reserve for round end
    @rounds = Rounds.new(0, rounds)  # rounds in game
    @started = nil    # time the game started
    add_player(user)
  end

  def add_player(user)
    if player = get_player(user)
      say "You're already in the game #{player}."
      return
    elsif players.size  > 3
      say "Sorry, this game can only seat 4 players at a time."
      return
    elsif started and deck.size < 2
      say "Round is about to end. Wait until next round to join, #{user}."
      return
    end
    player = Player.new(user)
    @players << player
    if manager.nil?
      @manager = player
      say "#{player} creates a game of #{Title}. Type 'j' to join."
    else
      say "#{player} joins #{Title}."
    end
    if @join_timer
      if players.size == 4
        @bot.timer.remove(@join_timer)
        do_round
      else
        @bot.timer.reschedule(@join_timer, 10)
      end
    elsif players.size > 1
      countdown = @bot.config['loveletter.countdown']
      @join_timer = @bot.timer.add_once(countdown) { do_round }
      say "Game will start in #{countdown} seconds."
    end
  end

  def do_baron(player, opponent)
    if opponent.nil?
      notify player, 'Specify another player.'
      return false
    elsif opponent.out
      notify player, "#{opponent.user} is already out of the round!"
      return false
    end
    say "#{player} compares hands with #{opponent}..."
    if player.hand.first.value > opponent.hand.first.value
      oust_player(opponent)
    elsif player.hand.first.value == opponent.hand.first.value
      say "It's a draw."
    else
      oust_player(player)
    end
    return true
  end

  def do_discard(player, card, opponent, guard_guess)
    if card.nil?
      notify player, "Specify a card name or number."
      return false
    elsif not player.has?(card)
      notify player, "Specify one of your hand cards."
      return false
    elsif player.has?(:king) or player.has?(:prince)
      if player.has?(:countess) and card.name != :countess
        notify player, 'You must discard the Countess.'
        return false
      end
    end
    if opponent and opponent.out
      say "#{opponent} is already out of the round!"
      return
    end
    player.discard = card
    player.hand.delete_at(player.hand.index { |e| e.name == card.name })
    say "#{player} plays #{card}."
    # If all other players played Handmaid,
    # the card may be discarded to no effect.
    handmaids = true
    players.each do |p|
      next if p == player or p.out
      handmaids = false if p.discard.nil? or p.discard.name != :handmaid
      break if handmaids == false
    end
    case card.name
    when :countess
      return true
    when :guard
      if guard_guess and not handmaids
        return do_guard(player, opponent, guard_guess)
      elsif not handmaids
        say 'Guess a card.'
      end
    when :handmaid
      say "#{player} is immune until next turn."
      return true
    when :prince
      return do_prince(player, opponent)
    when :princess
      oust_player(player)
      return true
    else
      if handmaids == false
        opponent = players.last if players.size == 2
        if opponent
          return self.send("do_#{card.name}", player, opponent)
        else
          say "Pick a player, #{player}."
        end
      end
    end
    if handmaids
      say "#{player} discards to no effect."
      return true
    else
      return false
    end
  end

  def do_guard(player, opponent, guard_guess)
    opponent = players.last if players.size == 2
    if guard_guess.nil?
      notify player, "Name a card you think #{opponent.user} has."
      return false
    elsif guard_guess.name == :guard
      return false
    elsif opponent.nil? or opponent == player
      notify player, 'Specify a target player.'
      return false
    elsif opponent.out
      notify player, "#{opponent.user} is already out of the round!"
      return false
    elsif opponent.discard and opponent.discard.name == :handmaid
      notify player, "#{opponent.user} is protected by #{opponent.discard}."
      return false
    end
    say "#{player} suspects #{opponent} has the " +
        guard_guess.name.to_s.capitalize + '...'
    oust_player(opponent) if opponent.has?(guard_guess)
    return true
  end

  def do_king(player, opponent)
    if opponent.nil?
      notify player, 'Specify another player.'
      return false
    elsif opponent.out
      notify player, "#{opponent.user} is already out of the round!"
      return false
    end
    say "#{player} swaps hands with #{opponent}."
    player.hand, opponent.hand = opponent.hand, player.hand
    show_hand([player, opponent])
    return true
  end

  def do_priest(player, opponent)
    if opponent.nil?
      notify player, 'Specify another player.'
      return false
    elsif opponent.out
      notify player, "#{opponent.user} is already out of the round!"
      return false
    end
    notify player, "#{opponent} has: #{opponent.hand.first}"
    return true
  end

  def do_prince(player, opponent)
    if opponent.nil?
      opponent = player
    elsif opponent.out
      notify player, "#{opponent.user} is already out of the round!"
      return false
    elsif opponent.discard and opponent.discard.name == :handmaid
      notify player, "#{opponent.user} is protected by #{opponent.discard}."
      return false
    end
    if opponent.discard.nil? or opponent.discard.name != :handmaid
      opponent.discard = opponent.hand.first
    end
    say "#{opponent} discards #{opponent.hand.first}."
    opponent.hand.clear
    if deck.size > 0
      opponent.hand << @deck.pop
    else
      opponent.hand << @reserve.pop
    end
    return true
  end

  def do_round(last_winner=nil)
    @started = Time.now if not started
    @players.shuffle!
    # re-create deck
    @deck.clear
    @reserve.clear
    Cards.each_pair do |k, v|
      v[:quantity].times { @deck << Card.new(k) }
    end
    @deck.shuffle!
    # deal players
    players.each { |p| p.hand << @deck.pop }
    if players.size == 2
      @reserve |= @deck.pop(4)
    else
      @reserve << @deck.pop
    end
    if last_winner
      players.size.times do
        if players[1] == last_winner
          break
        else
          @players << @players.shift
        end
      end
    end
    do_turn
  end

  def do_turn(hold_place=false)
    in_game = 0
    players.each { |p| in_game += 1 unless p.out }
    if in_game < 2 or deck.empty?
      end_round
      return
    end
    if hold_place
      # Show everyone their cards at the start of a new round.
      players.each { |p| show_cards(p) unless p == players.first }
    else
      @players << @players.shift
    end
    players.length.times do
      # Keep rotating until reaching a
      # player not out of the round.
      break unless players.first.out
      @players << @players.shift
    end
    player = players.first
    player.discard = nil
    players.last.moved = false
    while player.hand.size < 2
      if deck.empty? and not player.hand.empty?
        end_round
        return
      elsif deck.size > 0
        player.hand << @deck.pop
      else
        player.hand << @reserve.pop
      end
    end
    if deck.size == 1
      say "#{Irc.color(:red)}One card left in the deck.#{NormalText}"
    end
    say "#{player}, pick a card to discard."
    show_hand(player)
  end

  def drop_player(dropper, a)
    case a.first
    when nil, 'me' then player = dropper
    else player = get_player(a.first, dropper)
    end
    if player.nil?
      say "#{dropper}, there is no one playing named '#{a.first}'."
      return
    elsif player != dropper and dropper != manager
      say "Only the game manager is allowed to drop others, #{dropper}."
      return
    end
    n = 0
    n += 1 until players[n] == player
    n = next_turn(n)
    if player == manager and players.size > 2
      unless players[n].user == @bot.nick
        @manager = players[n]
      else
        @manager = players[next_turn(n)]
      end
      say "#{manager} is now game manager."
    end
    say "#{player} has been removed from the game."
    @dropouts << player
    @players.delete(player)
    # If the manager drops the only other player, end the game.
    if players.size < 2
      say "#{player} has been removed from the game. #{Title} stopped."
      @plugin.remove_game(channel)
    else
      do_turn(true) if player == players.first
    end
  end

  def elapsed_time
    return Utils.secs_to_string(Time.now-started)
  end

  def end_game
    players.first.moved = true
    # Time spent playing the game.
    @started = Time.now.to_i - started.to_i
    a = []
    winners = players.sort { |x, y| y.rounds <=> x.rounds }
    winners.each { |p| a << "#{p} - #{p.rounds}"  }
    say 'Game over. Rounds won: ' + a.join(', ')
    winners.reject! { |p| p.rounds < winners.first.rounds }
    update_channel_stats
    if winners.size > 1
      say Utils.comma_list(winners) + ' have won equal affection!'
      winners.each { |p| update_user_stats(p, 1) }
    else
      say "#{winners.first} has won the most affection!"
      update_user_stats(winners.first, 1)
    end
    players.each { |p| update_user_stats(p, 0) unless winners.include?(p) }
    @plugin.remove_game(channel)
  end

  def end_round
    @rounds.played += 1
    # Sort out the winners.
    a = []
    winners = players.reject { |p| p.out }
    winners.each { |p| a << "#{p} discards #{p.hand.first}" }
    say Utils.comma_list(a) + '.'
    winners.sort! { |x, y| y.hand.first.value <=> x.hand.first.value }
    winners.reject! { |p| p.hand.first.value < winners.first.hand.first.value }
    if winners.size > 1
      say 'It\'s a tie between' + Utils.comma_list(winners) + '!'
      winner = nil
    else
      say "#{winners.first} wins the round!"
      winner = winners.first
    end
    players.each do |p|
      p.discard, p.hand = nil, []
      p.moved = p.out = false
      p.rounds += 1 if winners.include?(p)
    end
    if rounds.played == rounds.total
      end_game
    else
      say "Starting round #{rounds.played + 1} of #{rounds.total}..."
      do_round(winner)
    end
  end

  def get_card(card)
    case card
    when Array
      ret = nil
      card.each { |e| ret = get_card(e) if ret.nil? }
      return ret
    when Card
      return card
    when NilClass
      return nil
    when String
      [',', '.', '!', '?'].each { |e| card.gsub!(e, '') }
      Cards.each_pair do |k,v|
        return Card.new(k) if card =~ v[:keyword]
      end
    else
      get_card(card.to_s)
    end
    return nil
  end

  def get_player(user, source='')
    case user
    when NilClass
      return nil
    when User
      players.each do |p|
        return p if p.user == user
      end
    when String
      players.each do |p|
        return p if p.user.irc_downcase == user.irc_downcase(channel.casemap)
      end
      players.each do |p|
        if p.user.irc_downcase =~ /^#{user.irc_downcase(channel.casemap)}/
          return p unless p.user.irc_downcase == source.downcase
        end
      end
    else
      get_player(user.to_s)
    end
    return nil
  end

  def notify(player, msg, opts={})
    @bot.notice player.user, msg, opts
  end

  def oust_player(player)
    player.out = true
    say "#{player} is out of the round! Discarding #{player.hand.first}."
    player.discard = player.hand.first
  end

  def processor(player, a)
    return unless player == players.first
    return if player.moved or a.empty?
    player.moved = true
    card = guard_guess = opponent = nil
    a.each do |e|
      card = player.hand[e.to_i-1] unless card or e.to_i.zero?
      card = card || get_card(e)
      guard_guess = get_card(e) || guard_guess
      opponent = opponent || get_player(e, player.user)
    end
    player.moved = if player.discard and player.discard.name == :guard
      do_guard(player, opponent, guard_guess)
    elsif player.discard
      self.send("do_#{player.discard.name}", player, opponent)
    else
      do_discard(player, card, opponent, guard_guess)
    end
    do_turn if player.moved
  end

  def replace_player(replacer, a)
    old_player = new_player = nil
    a.each do |e|
      next if e == @bot.nick.downcase
      if old_player.nil?
        e = replacer.user.nick if e == 'me'
        old_player = channel.get_user(e)
      elsif new_player.nil?
        new_player = channel.get_user(e)
      end
    end
    unless old_player
      notify replacer, "Specify a replacement user, #{replacer.user}."
      return
    end
    # Player only specified one name. Assume that is the new player.
    unless new_player
      new_player = old_player
      old_player = channel.get_user(replacer.user.nick)
    end
    if replacer.user == new_player
      notify replacer, "You're already playing, #{replacer.user}."
    elsif old_player == new_player
      notify replacer, 'Replace someone with someone else.'
    elsif get_player(new_player.nick)
      notify replacer, "#{new_player.nick} is already playing #{Title}."
    elsif not player = get_player(old_player) # assign player or return nil
      notify replacer, "#{old_player} is not playing #{Title}."
    elsif player != replacer and replacer != manager
      notify replacer, 'Only game managers can replace other players.'
    else
      say "#{player} was replaced by #{Bold + new_player.nick + Bold}!"
      player.user = new_player
      say "#{player} is now game manager." if player == manager
    end
  end

  def say(msg, who=channel, opts={})
    return unless msg.is_a? String
    return if msg.empty?
    @bot.say who, msg, opts
  end

  def show_help(player, a)
    if a.first.to_i.between?(1, player.hand.size)
      card = player.hand[a.first.to_i-1]
    elsif a.first =~ /^cards?$/
      say 'Cards: Princess (1), Countess (1), King (1), Prince ' +
          '(2), Handmaid (2), Baron (2), Priest (2), Guard (5).'
    else
      a.each { |e| card = get_card(e) if card.nil? }
    end
    return if card.nil?
    notify player, "#{card} - #{Cards[card.name][:text]}"
  end

  def show_hand(p_array=players)
    [*p_array].each do |p|
      next if p.hand.size < 1
      i = 0
      string = 'Cards: '
      string <<  p.hand.map { |e| "#{Bold}#{i += 1}.)#{Bold} #{e}" }.join(' ')
      notify p, string
    end
  end

  def show_turn
    return unless started
    a, player = [], players.first
    string = "It's #{player}'s turn."
    players.each do |p|
      us = p.out ? "#{p.user} (out)" : p.user.to_s
      ds = p.discard ? p.discard.to_s : '(none)'
      a << us + ' - ' + ds
    end
    string << 'Discard: ' + a.join(', ')
    string << " -- Cards left: #{deck.size}"
    say string
  end

  def transfer_management(player, a)
    return if a.empty?
    unless player == manager
      notify player, "You can't transfer ownership. " +
                     "#{manager} manages this game."
      return
    end
    a.each do |e|
      break if new_manager = get_player(e, manager.user)
    end
    if new_manager.nil?
      say "#{player}: Specify another player."
      return
    elsif manager == new_manager
      say "#{player.user}: You are already game manager."
      return
    end
    @manager = new_manager
    say "#{new_manager} is now game manager."
  end

  def update_channel_stats
    r = @registry[:chan] || {}
    c = channel.name.downcase
    r[c] = {} if r[c].nil?
    r[c][:games] = r[c][:games].to_i + 1
    # display-name for proper caps
    r[c][:name] = channel.name
    r[c][:rounds] = r[c][:rounds].to_i + rounds.total
    r[c][:time] = r[c][:time].to_i + started
    @registry[:chan] = r
  end

  def update_user_stats(player, win)
    @registry[:user] = {} if @registry[:user].nil?
    c, n = channel.name.downcase, player.user.nick.downcase
    h1 = @registry[:chan][c][n] || {}
    h2 = @registry[:user][n] || {}
    [ h1, h2 ].each do |e|
      e[:games] = e[:games].to_i + 1
      # Get player's nick in proper caps.
      e[:nick] = player.user.to_s
      e[:score] = e[:score].to_i + player.rounds
      # bonus points for winning
      e[:score] += (rounds.total * win)
      e[:wins] = e[:wins].to_i + win
    end
    r1 = @registry[:chan]
    r2 = @registry[:user]
    r1[c][n], r2[n] = h1, h2
    @registry[:chan], @registry[:user] = r1, r2
  end

end


class LoveLetterPlugin < Plugin

  Title = LoveLetter::Title

  Config.register Config::IntegerValue.new 'loveletter.countdown',
    :default => 10, :validate => Proc.new{|v| v > 0},
    :desc => 'Number of seconds before starting a game of Love Letter.'

  attr :games

  def initialize
    super
    @games = {}
  end

  def help(plugin, topic='')
    p = @bot.config['core.address_prefix'].first
    case topic.downcase
    when /princess/
      "#{Bold}Princess Annette #{Bold}- If you discard the " +
      "Princess―no matter how or why―she has tossed your " +
      "letter into the fire. You are knocked out of the round."
    when /countess/
      "#{Bold}Countess Wilhelmina #{Bold}- Unlike other cards, which takes " +
      "effect when discarded, the text on the Countess applies while she " +
      "is in your hand. In fact, she has no effect when you discard her.\n" +
      "If you ever have the Countess and either the Princes or King in " +
      "your hand, you must discard the Countess. You do not have to reveal " +
      "the other card in your hand. Of course, you can also discard the " +
      "Countess even if you do not have a royal family member in your " +
      "hand. She likes to play mind games...."
    when /king/
      "#{Bold}King Arnaud IV #{Bold}- When you discard the King, " +
      "trade the card in your hand with the card held by another " +
      "player of your choice. You cannot trade with a player who " +
      "is out of the round, nor with someone protected by the " +
      "Handmaid. If all other players still in the round are " +
      "protected by the Handmaid, this card does nothing."
    when /prince/
      "#{Bold}Prince Arnaud #{Bold}- when you discard the Prince, " +
      "choose one player still in the round (including yourself) " +
      "That player discards his or her hand (do not apply its " +
      "effect) and draws a new card. If the deck is empty, that " +
      "player draws a card that was removed at the start of the " +
      "round.\nIf all other players are protected by the " +
      "Handmaid, you must choose yourself."
    when /maid/
      "#{Bold}Handmaid Susannah #{Bold}- When you discard " +
      'the Handmaid, you are immune to the effects of other ' +
      'players\' cards until the start of your next turn.'
    when /baron/
      "#{Bold}Baron Talus #{Bold}- When discarded, choose one other " +
      'player still in the round. You and that player secretly compare ' +
      'your hands. The player with the lower rank is knocked out of the ' +
      'round. In case of a tie, nothing happens. If all other players ' +
      'still in the round are protected by the Handmaid, ' +
      'this card does nothing.'
    when /priest/
      "#{Bold}Priest Tomas #{Bold}- When you discard the " +
      "Priest, you can look at one other player’s hand. " +
      'Do not reveal the hand to all players.'
    when /guard/
      "#{Bold}Guard Odette #{Bold}- When you discard the Guard, " +
      'choose a player and name a card (other than Guard). If ' +
      'that player has that card, that player is knocked out ' +
      'of the round. If all other players still in the round ' +
      'are protected by the Handmaid, this card does nothing.'
    when /drop/
      "Type 'drop me' to leave the game in progress, or " +
      "'drop <another player>' if you are the game manager."
    when /card/
      'There are 16 cards total in the deck: Princess (1), Countess ' +
      '(1), King (1), Prince (2), Handmaid (2), Baron (2), Priest ' +
      "(2), Guard (5). Use '#{p}help #{plugin} <card>' for " +
      "card-specific information, (or simply use 'help card', " +
      "or 'help <card name>' in game for a quick reference)."
    when /command/
      "In-game commands: 'p <card name or number>' to pick/play " +
      "a card, 'p <victim>' to pick a player you wish to play a " +
      "card against (e.g.: 'p guard', 'p Frank has the baron!', " +
      "or 'p guard fr baron' for short), 'help <card name>' for " +
      "quick card info, or preferably 'help <card #>' as to not " +
      "give away the card in your hand, 'drop me' to leave a game " +
      "in progress, 'replace [me with] user' to have another " +
      "player take your spot in the game.\nSee '#{p}help #{plugin} " +
      "manage' for commands specific to the game manager."
    when /manage/, /transfer/, /xfer/
      'The player that starts the game is the game manager. Game ' +
      'managers may stop the game at any time, or transfer ownership ' +
      "by typing 'transfer [game to] <player>'. Managers may replace " +
      'themselves as well as other players in the game by typing ' +
      "'replace [me with] <user> / replace <player> [with] <nick>'"
    when /object/
      "During the game, you hold one secret card in your hand. This is " +
      "who currently carries your message of love for the princess. " +
      "Make sure that the person closest to the princess holds your " +
      "love letter at the end of the day, so it reaches her first!\n" +
      "(The higher the card value, the closer the person is to the " +
      "princess, but be careful as the higher value cards are more " +
      "likely to get you knocked out of the round before it's over!)"
    when /rule/, /manual/
      "http://www.alderac.com/tempest/files/2012/09/Love_Letter_Rules_Final.pdf"
    when /scoring/
      'The winner of each round receives a token of affection ' +
      'from the princess. The player that received the most affection ' +
      'by the end of all the rounds is declared the winner. Players\' ' +
      'scores are updated relative to the amount of affection won. ' +
      'The winner over all rounds receives a bonus relative ' +
      'to the total number of rounds played.'
    when /stat/, /scor/
      "'#{p}love stats <channel/user>' displays the stats and score for " +
      'a channel or user. If no channel or user is specified, this ' +
      "command will show you your own stats.\n'#{p}love stats <channel> " +
      "<user>' displays a user's stats for a specific channel.\n'#{p}love " +
      "top <num> <channel>' shows the top <num> scores for a given channel."
    when /cancel/, /end/, /halt/, /stop/
      "'#{p}love stop' stops the current game; Only game " +
      'managers and bot owners can stop a game in progress.'
    when ''
      "#{Title}: cards, commands, manual, object, scoring, stats, stop -- " +
      "'#{p}love <rounds>' to create a game"
    end
  end

  def create_game(m, p)
    if g = @games[m.channel]
      if m.source == g.manager.user
        m.reply "...you already started #{Title}."
      else
        m.reply "#{g.manager.user} already started #{Title}."
      end
      return
    end
    rounds = p[:rounds].to_i
    if rounds > 50 or rounds.zero?
      m.reply 'That\'s not a good idea...'
      return
    end
    @games[m.channel] = LoveLetter.new(self, m.channel, m.source, rounds)
  end

  def message(m)
    return unless m.plugin and g = @games[m.channel]
    case m.message.downcase
    when 'j', 'jo', 'join'
      g.add_player(m.source)
    when 'ti', 'time'
      if g.started
        @bot.say m.replyto, Title + " has been in play for #{g.elapsed_time}."
      else
        m.reply Title + " hasn't started yet."
      end
    end
    # Messages only concerning players:
    player = g.get_player(m.source.nick)
    return unless player and g.started
    a = m.message.downcase.split(' ').uniq[1..-1]
    case m.message.downcase
    when /^(ca?|cards?)( |\z)/
      g.show_hand(player)
    when /^drop( |\z)/
      g.drop_player(player, a)
    when /^h(elp)?( |\z)/
      g.show_help(player, a)
    when /^(pi?|pl|play)( |\z)/
      g.processor(player, a)
    when /^(tu?|turn)( |\z)/
      g.show_turn
    when /^replace( |\z)/
      g.replace_player(player, a)
    when /^transfer( |\z)/
      g.transfer_management(player, a)
    end
  end

  def show_stats(m, params)
    if @registry[:chan].nil?
      m.reply "No #{Title} stats recorded yet."
      return
    end
    if params[:a] == false
      if @registry[:chan][m.channel.name.downcase]
        show_stats_chan(m, m.channel.name.downcase, params[:n].to_i)
      else
        m.reply "No one has played #{Title} in #{m.channel.name}."
      end
      return
    end
    a, chan, user, n = params[:a], nil, nil, 0
    if a.empty?
      user = m.source.nick.downcase
    else
      a.each do |e|
        chan = e.downcase if @registry[:chan][e.downcase]
        user = e.downcase if @registry[:user][e.downcase]
        n = e.to_i if e.to_i > n
      end
    end
    if chan.nil? and user.nil?
      # Check for missing # symbol.
      a.each { |e| chan = "##{chan}" if @registry[:chan]["##{chan}"] }
      if chan
        show_stats_chan(m, chan, n)
      else
        m.reply "No stats for #{a.join(' or ')}."
      end
    elsif user
      show_stats_user(m, user, chan)
    elsif chan
      show_stats_chan(m, chan, n)
    end
  end

  def show_stats_chan(m, chan, n)
    c = @registry[:chan][chan]
    if n.zero?
      str = "#{Bold}#{c[:name]}:#{Bold} #{c[:games]} games played, "
      str << "rounds played: #{c[:rounds]} "
      i = c[:games] > 1
      str << "(#{c[:rounds]/c[:games]} rounds average per game), " if i
      str << "time accumulated: #{Utils.secs_to_string(c[:time])} "
      str << "(#{Utils.secs_to_string(c[:time]/c[:games])} average per game)." if i
      @bot.say m.replyto, str
      return
    end
    n = 5 unless n.between?(1,20)
    tops = {}
    c.each_pair do |k, v|
      next unless k.is_a? String
      tops[v[:score]] = k
    end
    n = tops.size if n > tops.size
    @bot.say m.replyto, "#{c[:name]}'s top #{n} players:"
    i = 1
    if n.between?(1,8)
      tops.sort.reverse.each do |e|
        str = "#{Bold}#{i}.) #{c[e[1]][:nick]}#{Bold} - "
        str << "#{e.first} points, "
        str << "#{c[e[1]][:wins]}/#{c[e[1]][:games]} wins"
        @bot.say m.replyto, str
        i += 1
      end
    else
      str = ''
      tops.sort.reverse.each do |e|
        str << "#{Bold}#{i}.) #{c[e[1]][:nick]}#{Bold} - "
        str << "#{e.first} pts."
        i += 1
        if i > n
          break
        else
          str << ', '
        end
      end
      @bot.say m.replyto, str
    end
  end

  def show_stats_user(m, user, chan=nil)
    if chan
      u = @registry[:chan][chan][user]
      chan = @registry[:chan][chan][:name]
      str = "#{Bold}#{u[:nick]}#{Bold} (in #{chan}) -- "
    else
      u = @registry[:user][user]
      str = "#{Bold}#{u[:nick]}#{Bold} -- "
    end
    str << "score: #{u[:score]}, "
    str << "wins: #{u[:wins]}, "
    str << "games played: #{u[:games]}"
    @bot.say m.replyto, str
  end

  # Called from within the game.
  def remove_game(channel)
    if t = @games[channel].join_timer
      @bot.timer.remove(t)
    end
    @games.delete(channel)
  end

  def reset_everything(m, params)
    @registry.clear
    m.reply 'Registry cleared.'
  end

  def stop_game(m, plugin=nil)
    unless g = @games[m.channel]
      m.reply "No one is playing #{Title} here."
      return
    end
    player = @games[m.channel].get_player(m.source.nick)
    owner = @bot.auth.irc_to_botuser(m.source).owner?
    if g.manager == player or owner or not started
      remove_game(m.channel)
      @bot.say m.replyto, "#{Title} stopped."
    else
      m.reply 'Only game managers may stop the game.'
    end
  end

end

p = LoveLetterPlugin.new

[ 'cancel', 'end', 'halt', 'stop' ].each do |x|
  p.map "love #{x}",
    :action => :stop_game,
    :private => false
end
p.map 'love reset everything',
  :action => :reset_everything,
  :auth_path => 'reset'
p.map 'love stat[s] *a',
  :action => :show_stats,
  :defaults => {:a => [] }
p.map 'love top [:n]',
  :action => :show_stats,
  :defaults => { :a => false, :n => 5 }
p.map 'love [rounds] [:rounds]',
  :action => :create_game,
  :defaults => { :rounds => 1 },
  :private => false,
  :requirements => { :rounds => /^\d+$/ }

p.default_auth('*', true)
p.default_auth('reset', false)
