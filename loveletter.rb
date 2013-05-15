# Title:: Love Letter
# Author:: Jay Thomas <degradinglight@gmail.com>
# Copyright:: (C) 2013 gfax
# License:: GPL
# Version:: 2013-05
#

class LoveLetter

end

class LoveLetterPlugin < Plugin

end

p = LoveLetterPlugin.new

[ 'cancel', 'end', 'halt', 'stop' ].each do |x|
  p.map "love #{x}",
    :private => false, :action => :stop_game
end
p.map 'love reset',
  :action => :reset_everything
p.map 'love stat[s] *a',
  :action => :show_stats
p.map 'love top [:n]',
  :private => false, :action => :show_stats,
  :defaults => { :a => false, :n => 5 }
p.map 'love',
  :private => false, :action => :create_game

p.default_auth('*', true)
