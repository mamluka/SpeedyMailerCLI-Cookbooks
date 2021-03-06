package 'mailutils'
package 'dnsutils'

#stop apache - we don't need it
service "apache2" do
  action :stop
end


#set host to be a mail serverl
file "/etc/hostname" do
  content "mail"
end

#set the domain in the hosts file
script "add-domain-to-hosts-file" do
  interpreter "bash"
  user "root"
  cwd "/tmp"
  code <<-EOH
                
        echo "#{node[:drone][:ip]} #{node[:drone][:domain]}" > /etc/hosts
        echo "#{node[:drone][:ip]} localhost.localdomain mail" >> /etc/hosts
        echo "#{node[:drone][:ip]} localhost" >> /etc/hosts

        service hostname restart
  EOH
end

execute "create-deploy-dirs" do
  command "mkdir -p /deploy/domain-keys && mkdir -p /deploy/utils && mkdir -p /etc/mail"
end

#configure postfix

service "sendmail" do
  action :stop
end

package 'postfix'
package 'postfix-pcre'
package 'dk-filter'
package 'opendkim'
package 'opendkim-tools'


template "/etc/postfix/main.cf" do
  source "main.cf.erb"
  mode 0664
  owner "root"
  group "root"
  variables({
                :domain => node[:drone][:domain]
            })
end

template "/etc/postfix/header_checks" do
  source "header_checks.erb"
  mode 0664
  owner "root"
  group "root"
end

template "/etc/opendkim.conf" do
  source "opendkim.conf.erb"
  mode 0664
  owner "root"
  group "root"
  variables({
                :domain => node[:drone][:domain]
            })
end

template "/etc/default/opendkim" do
  source "opendkim.erb"
  mode 0664
  owner "root"
  group "root"
end

template "/etc/mail/dkim-InternalHosts.txt" do
  source "dkim-InternalHosts.txt.erb"
  mode 0664
  owner "root"
  group "root"
  
  variables({
                :domain => node[:drone][:domain]
            })
end

template "/etc/default/dk-filter" do
  source "dk-filter.erb"
  mode 0664
  owner "root"
  group "root"
  variables({
                :domain => node[:drone][:domain]
            })
end

script "create-dkim-key" do
  interpreter "bash"
  user "root"
  cwd "/tmp"
  code <<-EOH
      opendkim-genkey -t -s mail -d #{node[:drone][:domain]}
      cp mail.private /etc/mail/dkim.key
      cp mail.txt /deploy/domain-keys/dkim-dns.txt
  EOH

  not_if "test -f /deploy/domain-keys/dkim-dns.txt"
end

script "create-domain-key" do
  interpreter "bash"
  user "root"
  cwd "/tmp"
  code <<-EOH
      openssl genrsa -out private.key 1024
      openssl rsa -in private.key -out public.key -pubout -outform PEM
      cp private.key /etc/mail/domainkey.key
      cp public.key /deploy/domain-keys/domain-keys-dns.txt
      sudo service dk-filter stop
      sudo service dk-filter start
  EOH

  not_if "test -f /deploy/domain-keys/domain-keys-dns.txt"
end



service "opendkim" do
  action :restart
end

#clean deferred queue cron job
script "setup drone alias" do
  interpreter "bash"
  user "root"
  cwd "/tmp"
  code <<-EOH
        crontab -l > mycron
        sed -i '/no crontab for root/d' mycron
        echo "0 */1 * * * /usr/sbin/postsuper -d ALL deferred" >> mycron
        crontab mycron
        rm mycron
  EOH
end

#setup rsyslog logging to speedymailer reader and then to elastic

apt_repository "rsyslog" do
  uri "http://ppa.launchpad.net/tmortensen/rsyslogv7/ubuntu/"
  distribution node['lsb']['codename']
  components ["main"]
  keyserver "keyserver.ubuntu.com"
  key "431533D8"
  deb_src true
end

package 'rsyslog' do
  action :upgrade
end

template "/etc/rsyslog.conf" do
  source "rsyslog.conf.erb"
  mode 0664
  owner "root"
  group "root"
end

service "rsyslog" do
  action :restart
end

execute "change log permissions" do
  command "chmod 655 /var/log/mail.log"
end

template "#{File.expand_path('~')}/SpeedyMailerCLI/drones/config.json" do
  source "config.json.erb"
  variables({
                :drone_domain => node[:drone][:domain],
                :master_domain => node[:drone][:master]
            })
end

script "install tmuxifier" do
  interpreter "bash"
  cwd "/tmp"
  code <<-EOH
        git clone https://github.com/jimeh/tmuxifier.git ~/.tmuxifier
        echo 'export PATH="~/.tmuxifier/bin:$PATH"' >> ~/.bash_profile
        
  EOH
  
  not_if "grep tmuxifier ~/.bash_profile" 
end

execute "add bashrc to bash profile" do
  command "echo '. ~/.bashrc' >> ~/.bash_profile"
  not_if "grep ~/.bashrc ~/.bash_profile"
end

package 'fontconfig'

script "install phantomjs" do
  interpreter "bash"
  cwd "/tmp"
  code <<-EOH
        wget https://phantomjs.googlecode.com/files/phantomjs-1.9.2-linux-x86_64.tar.bz2
        tar -xvf phantomjs-1.9.2-linux-x86_64.tar.bz2
        
        mkdir -p /home/drone/bin
        mv phantomjs-1.9.2-linux-x86_64/bin/phantomjs /home/drone/bin/
        chown drone:drone /home/drone/bin/phantomjs
        chmod +x /home/drone/bin/phantomjs 
        
  EOH
end

#add phantim to bashrc
execute "add phantom js to bashrc" do
  command "echo 'export PATH=\"$HOME/bin:$PATH\"' >> /home/drone/.bashrc"
  not_if "grep /bin ~/.bashrc"
end

template "#{File.expand_path('~')}/.tmuxifier/layouts/drone.session.sh" do
  source "drone.session.sh.erb"
  variables({
                :drone_domain => node[:drone][:domain]
            })
end

#setup the redis url to use in sidekiq
execute "setup-master-redis-url" do
  command "echo 'export REDIS_URL=redis://#{node[:drone][:master]}:6379/0' >> ~/.bash_profile"
  not_if "grep REDIS_URL ~/.bash_profile"
end

#install nginx

apt_repository "nginx" do
  uri "http://ppa.launchpad.net/nginx/stable/ubuntu/"
  distribution node['lsb']['codename']
  components ["main"]
  keyserver "keyserver.ubuntu.com"
  key "C300EE8C"
  deb_src true
end

package 'nginx'

template "/etc/nginx/sites-enabled/drone-site" do
  source "drone-site.erb"
  variables({
                :drone_domain => node[:drone][:domain]
            })
end

execute "remove-default-site" do
  command "rm /etc/nginx/sites-enabled/default"
  only_if "test -f /etc/nginx/sites-enabled/default"
end

service "nginx" do
  action :restart
end

# start things
service "postfix" do
  action :start
end

#run bundler

execute "run-bundler" do
  command "cd #{File.expand_path('~')}/SpeedyMailerCLI/drones && bundle"
end

#register dns records
execute "register-dns-records" do
  command "ruby #{File.expand_path('~')}/SpeedyMailerCLI/drones/scripts/create-dns-records.rb"
end

#install squid
package 'squid'

template "/etc/squid3/squid.conf" do
  source "squid.conf.erb"
  variables({
                :drone_ip => node[:drone][:ip]
            })
end

service "squid3" do
  action :restart
end
