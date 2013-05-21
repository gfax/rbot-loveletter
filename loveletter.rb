# coding: utf-8
#
# Title:: Love Letter
# Author:: Jay Thomas <degradinglight@gmail.com>
# Copyright:: (C) 2013 gfax
# License:: GPL
# Version:: 2013-05-21
#

class LoveLetter

  Title = Irc.color(:red) + 'Love Letter' + NormalText

  Rounds = Struct.new(:played, :total)

  Cards = {
    :guard => {
      :value => 1,
      :quantity => 5,
      :keyword => /guard/,
      :text => 'Name a non-Guard card and choose another player and ' +
               'choose another player; If that player has that card, ' +
               'he or she is our of the round.'
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
      :text => 'If you have this card and the King or Princess ' +
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
      '(' + value.to_s + ') ' + name.to_s.capitalize +
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
    end
    string = "#{player} compares hands with #{opponent}..."
    if player.hand.first.value > opponent.hand.first.value
      oust_player(opponent)
    else
      oust_player(player)
    end
  end

  def do_discard(player, card, opponent, guard_guess)
    if card.nil?
      notify player, "Specify a card name or number."
      return false
    elsif not player.has?(card)
      notify player, "Specify one of your hand cards."
      return false
    end
    player.discard = card
    player.hand.delete(card)
    string = "#{player} plays #{card}"
    # If all other players played Handmaid,
    # the card may be discarded to no effect.
    handmaids = true
    players.each do |p|
      next if p == player
      handmaids = false if p.discard.nil? or p.discard.name != :handmaid
    end
    case card.name
    when :countess
      say string + '.'
      return true
    when :guard
      if opponent and guard_guess
        return do_guard(player, opponent, guard_guess) unless handmaids
      end
    when :handmaid
      say string + " and is now immune until next turn."
      return true
    when :princess
      say string + '!'
      oust_player(player)
      return true
    else
      if handmaids == false or card.name == :prince
        say string + '.'
        return self.send("do_#{card.name}", player, opponent) if opponent
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
    if guard_guess.nil?
      notify player, "Name a card you think #{opponent.user} has."
      return false
    elsif opponent.nil? or opponent == player
      notify player, 'Specify a target player.'
      return false
    elsif opponent.discard.name == :handmaid
      notify player, "#{opponent.user} is protected by #{opponent.discard}."
      return false
    end
    say "#{player} suspects #{opponent} has #{card.name.to_s.capitalize}..."
    oust_player(opponent) if opponent.has?(card)
    return true
  end

  def do_king(player, opponent)
    if opponent.nil?
      notify player, 'Specify another player.'
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
    end
    notify player, "#{opponent} has: #{opponent.hand.first}"
    return true
  end

  def do_prince(player, opponent)
    if player.has?(:countess)
      notify player, 'You must discard the Countess.'
      return false
    elsif opponent.nil?
      opponent = player
    elsif opponent.discard and opponent.discard.name == :handmaid
      notify player, "#{opponent.user} is protected by #{opponent.discard}."
      return false
    end
    if opponent.discard.nil? or opponent.discard.name != :handmaid
      opponent.discard = opponent.hand.first
    end
    say "#{opponent} discards #{opponent.hand.first}."
    opponent.hand.delete_at(0)
    if deck.size > 0 then opponent.hand << @deck.pop else opponent.hand << @reserve.pop end
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
    if in_game < 2
      end_round
      return
    end
    @players << @players.shift unless hold_place
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
    say "#{player}, pick a card to discard."
    show_hand(player)
  end

  def drop_player(dropper, a)
    case player = a.first
    when nil, 'me' then dropper
    else get_player(a.first, dropper)
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
    # Time spent playing the game.
    @started = Time.now.to_i - started.to_i
    say "That's all, folks."
    #update_channel_stats
    #players.each { |p| update_user_stats(p, 0) }
    @plugin.remove_game(channel)
  end

  def end_round
    @rounds.played += 1
    players.each do |p|
      p.discard = p.hand = []
      p.rounds += 1 unless p.out
      say "#{p} wins the round!" unless p.out
      winner = p
      p.out = false
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
      card = player.hand[e.to_i-1] if card.nil? and not e.to_i.zero?
      card = get_card(e) if card.nil?
      guard_guess = get_card(e) if guard_guess.nil? or guard_guess == card
      opponent = get_player(e, player.user)
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
    elsif a.first == /^cards?$/
      say 'Cards: Princess (1), Countess (1), King (1), Prince ' +
          '(2), Handmaid (2), Baron (2), Priest (2), Guard (5).'
    else
      a.each { |e| card = get_card(e) if card.nil? }
      return if card.nil
      notify player, "#{card} - #{Cards[card.name][:text]}"
    end
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
    player= players.first
    string = "It's #{player}'s turn."
    string << " Current discard: #{player.discard}" if player.discard
    string << " Cards left: #{deck.size}"
    say string
  end

  def transfer_management(player, a)
    return if a.size.zero?
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

  def update_channel_stats(stats)
    r = @registry[:chan] || {}
    c = channel.name.downcase
    r[c] = {} if r[c].nil?
    r[c][:games] = r[c][:games].to_i + 1
    r[c][:longest] = started if r[c][:longest].nil?
    r[c][:longest] = started if started > r[c][:longest]
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
      e[:rounds] = e[:rounds].to_i + player.rounds
      # bonus points for winning
      e[:rounds] += (rounds.total * win)
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
      'There are 16 cards total in the deck: Princess (1), ' +
      'Countess (1), King (1), Prince (2), Handmaid (2), ' +
      "Baron (2), Priest (2), Guard (5). Use '#{p}#{plugin} " +
      "help <card>' for card-specific information, or (simply use " +
      "'help card' or 'help <card name>' in game for a quick reference)."
    when /command/
      "In-game commands 'p <card name or number>' to pick/play " +
      "a card, 'p <victim>' to pick a play you wish to play a " +
      "card against (e.g.: p guard; p Frank has the baron!; or " +
      "p guard frank baron for short;), 'help <card name>' for " +
      "card info or preferably 'help <card #>' as to not give " +
      "away the card in your hand, 'drop me' to leave a game in " +
      "progress, 'replace [me with] user' to have another player " +
      "take your spot in the game. See '#{p}#{plugin} manage' " +
      "for commands specific to the game manager."
    when /manage/, /transfer/, /xfer/
      'The player that starts the game is the game manager. ' +
      'Game managers may stop the game at any time, or transfer ownership ' +
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
      "'#{p}#{plugin} stats <channel|user>' displays the stats " +
      'and scores for a channel or user. If no channel or user ' +
      "is specified, this command will show you your own stats.\n" +
      "'#{p}#{plugin} stats <channel> <user>' displays user " +
      "stats for a specific channel\n'#{p}#{plugin} top <num> " +
      "<channel>' shows the top <num> scores for a given channel"
    when /cancel/, /end/, /halt/, /stop/
      "'#{p}#{plugin} stop' stops the current game; Only game " +
      'managers and bot owners can stop a game in progress.'
    when ''
      "#{Title}: cards, commands, manual, object, scoring, stats, stop -- " +
      "'#{p}#{plugin} <rounds>' to create a game"
    end
  end

  def create_game(m, plugin)
    if g = @games[m.channel]
      if m.source == g.manager.user
        m.reply "...you already started #{Title}."
      else
        m.reply "#{g.manager.user} already started #{Title}."
      end
    else
      rounds = 1
      @games[m.channel] = LoveLetter.new(self, m.channel, m.source, rounds)
    end
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

  def do_test(m, params)
    m.reply LoveLetter.get_card("baron").class.to_s
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
    if g.manager == player or @bot.auth.irc_to_botuser(m.source).owner?
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
  :action => :show_stats
p.map 'love top [:n]',
  :action => :show_stats,
  :defaults => { :a => false, :n => 5 }
p.map 'love [:rounds]',
  :action => :create_game,
  :defaults => { :rounds => 1 },
  :private => false,
  :requirements => { :rounds => /^\d+$/ }

p.default_auth('*', true)
p.default_auth('reset', false)
