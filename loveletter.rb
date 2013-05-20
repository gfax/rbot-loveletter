# Title:: Love Letter
# Author:: Jay Thomas <degradinglight@gmail.com>
# Copyright:: (C) 2013 gfax
# License:: GPL
# Version:: 2013-05
#

class LoveLetter

  Title = Irc.color(:red) + 'Love Letter'

  Rounds = Struct.new(:played, :total)

  Cards = {
    :guard => {
      :value => 1,
      :quantity => 5,
      :keywords => [ /guard/ ],
      :text => 'Name a non-Guard card and choose another player and ' +
               'choose another player; If that player has that card, ' +
               'he or she is our of the round.'
    },
    :priest => { 
      :value => 2,
      :quantity => 2,
      :keywords => [ /priest/ ],
      :text => 'Look at another player\'s hand.'
    },
    :baron => {
      :value => 3,
      :quantity => 2,
      :keywords => [ /baron/ ],
      :text => 'You and another player secretly compare hands. ' +
               'The player with the lower value is out of the round. '
    },
    :handmaid => {
      :value => 4,
      :quantity => 2,
      :keywords => [ /maid/ ],
      :text => 'Until your next turn, ignore all ' +
               'effects from other players\' cards.'
    },
    :prince => {
      :value => 5,
      :quantity => 2,
      :keywords => [ /prince$/ ],
      :text => 'Choose any player (including yourself) to ' +
               'discard his or her hand and draw a new card.'
    },
    :king => {
      :value => 6,
      :quantity => 1,
      :keywords => [ /king/ ],
      :text => 'Trade hands with another player of your choice.'
    },
    :countess => {
      :value => 7,
      :quantity => 1,
      :keywords => [ /count/ ],
      :text => 'If you have this card and the King or Princess ' +
               'in your hand, you must discard this card.'
    },
    :princess => {
      :value => 8,
      :quantity => 1,
      :keywords => [ /princess/ ],
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
      value.to_s + '. 'name.to_s.capitalize +
      Irc.color(:red) + ']' + NormalText
    end

  end


  class Player

    attr_accessor :user, :discard, :hand, :moved, :out, :time

    def initialize(user)
      @user = user
      @discard = []
      @hand = []
      @moved = false
      @out = false
    end

    def has?(requests)
      return false if requests.nil?
      [*requests].each do |e|
        if e.is_a? Card
          hand.each { |c| return true if e == c }
        elsif e.is_a? Symbol
          hand.each { |c| return true if e == c.id }
        end
      end
      return false
    end

    def to_s
      Bold + user.to_s + Bold
    end
  end

  attr_reader :deck, :discard, :dropped, :manager,
              :players, :queue, :rounds, :started

  def initialize(plugin, channel, user, rounds)
    @bot = plugin.bot
    @channel = channel
    @plugin = plugin
    @registry = plugin.registry
    @deck = []        # card stock
    @discard = nil    # current discard
    @dropped = []     # players booted from game
    @join_timer = nil # timer for countdown
    @manager = nil    # player in control of game
    @players = []     # players currently in game
    @queue = nil      # temporary message queue
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
    elsif deck.size < 2
      say "Round is about to end. Wait until next round to join, #{user}."
    end
    player = Player.new(user)
    @players << player
    if manager.nil?
      @manager = player
      say "#{player} creates a game of #{Title}. Type 'j' to join."
    else
      say "#{player} joins #{Title}."
    end
    player.hand << draw
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

  def do_discard(player, a)
    card = opponent = guard_guess = nil
    a.each do |e|
      case e
      when Fixnum
        card = player.hand[e] if e >= 0 and card.nil?
      when Player
        opponent = e if opponent.nil?
      when Card
        card = e if card.nil? and player.has?(e)
        guard_guess = e if guard_guess.nil?
      end
    end
    if card.nil?
      notify player, "Specify a card name or number."
      return false
    end
    @discard = card
    player.discard << card
    player.hand.delete(card)
    @queue = "#{player} plays #{card}"
    case card.id
    when :guard
      return do_guard([opponent, guard_guess]) if opponent and guard_guess
    when :priest
      return do_priest([opponent]) if opponent
    when :baron
      return do_baron([opponent]) if opponent
    when :handmaid
      @queue << " and is now immune until next turn."
      return true
    when :prince
      return do_prince([opponent]) if opponent
    when :king
      return do_king([opponent]) if opponent
    when :countess
      @queue << '.'
      return true
    when :princess
      @queue << " and is knocked out of the round."
      player.out = true
      return true
    end
    return false
  end

  def do_round(last_winner=nil)
    @started = Time.now if not started
    @players.shuffle!
    # Reset deck:
    @deck.clear
    @reserve.clear
    Cards.each_pair do |k, v|
      v[:quantity].times { @deck << Card.new(k) }
    end
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
    done = true
    players.each { |p| done = false unless player.moved }
    if done
      end_round
      return
    end
    @players << @players.shift unless hold_place
    player = players.first
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
    @discard |= player.hand
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
  end

  def get_card(cards)
    [*cards].each do |e|
      Cards.each_pair do |k,v|
        return Card.new(k) if e.gsub('.','') =~ v[:keyword]
      end
    end
    return nil
  end

  def get_player(user, source=nil)
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
          return p unless p.user.irc_downcase == source.to_s.downcase
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

  def processor(player, a)
    return unless player == players.first
    return if player.moved or a.empty?
    player.moved = true
    a.map! do |e|
      get_card(e) || get_player(e, player.user) || e.to_i - 1
    end
    player.moved = if discard
      self.send("do_#{discard.id}", player, a)
    else
      do_discard(player, a)
    end
    if player.moved
      do_turn
    else
      say queue
      @queue = nil
    end
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
    return if msg.empty?
    @bot.say who, msg, opts
  end

  def show_help(player, a)
    return unless a.first.to_i.between?(1, player.hand.size)
    card = player.hand[a.first.to_i-1]
    notify player, "#{card} - #{Cards[card.id[:text]}"
  end

  def show_hand(p_array=players)
    [*p_array].each do |p|
      next if p.hand.size < 1
      notify p, "Cards: 1.) #{p.hand[0]}, 2.) #{p.hand[1]}"
    end
  end

  def show_turn
    return unless started
    string = "It's #{players.first}'s turn."
    string << " Current discard: #{discard}" if discard
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
      'player still in the round. You andthat player secretly compare ' +
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
      "love letter at the end of the day, so it reaches her first!"
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
      "#{Title}: commands, manual, object, scoring, stats, stop -- " +
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
      @games[m.channel] = LoveLetter.new(self, m.channel, m.source)
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
  :action => :show_stats
  :defaults => { :a => false, :n => 5 }
p.map 'love [:rounds]',
  :action => :create_game,
  :defaults => { :rounds => 1 },
  :private => false,
  :requirements => { :rounds => /^\d+$/ }

p.default_auth('*', true)
p.default_auth('reset', false)
