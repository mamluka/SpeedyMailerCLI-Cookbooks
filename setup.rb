require 'fileutils'

text = File.read('solo.rb')
File.open('solo.rb','w') { |f| f.puts text.gsub(/homedir/,ENV['HOME'])}

FileUtils.cp('solo.rb','../')
ileUtils.cp('node.json','../')
