require 'fileutils'
require 'json'

FileUtils.cp('solo.rb','../')
FileUtils.cp('node.json','../')

text = File.read('../solo.rb')
File.open('../solo.rb','w') { |f| f.puts text.gsub(/homedir/,ENV['HOME'])}

node = JSON.parse(File.read('../node.json'))

node['drone'] = Hash.new
node['drone']['domain'] = ARGV[0]
node['drone']['ip'] = `wget -q -O- http://ipecho.net/plain`
node['drone']['master'] = ARGV[1]

File.open('../node.json','w') { |f| f.puts JSON.generate(node) }
