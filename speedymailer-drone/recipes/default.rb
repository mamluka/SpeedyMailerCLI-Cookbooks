package 'mailutils'

#stop apache - we don't need it
service "apache2" do
  action :stop
end


#set host to be a mail server
file "/etc/hostname" do
  content "mail"
end

#set the domain in the hosts file
script "add-domain-to-hosts-file" do
  interpreter "bash"
  user "root"
  cwd "/tmp"
  code <<-EOH
        original_hostname=$(hostname)
        cat /etc/hosts | grep -Ev $original_hostname | sudo tee /etc/hosts
                
        echo "#{node[:drone][:ip]} mail.#{node[:drone][:domain]} mail" >> /etc/hosts
        echo "#{node[:drone][:ip]} localhost.localdomain mail" >> /etc/hosts

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
      service dk-filter stop
      service dk-filter start
  EOH

  not_if "test -f /deploy/domain-keys/domain-keys-dns.txt"
end

service "postfix" do
  action :start
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

#setup rsyslog logging to mongo

template "/etc/rsyslog.d/10-mongodb.conf" do
  source "10-mongodb.conf.erb"
  mode 0664
  owner "root"
  group "root"
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

template "#{File.expand_path('~')}/.tmuxifier/layouts/drone.session.sh" do
  source "drone.session.sh.erb"
  variables({
                :drone_domain => node[:drone][:domain]
            })
end

#setup the redis url to use in sidekiq
execute "setup-master-redis-url" do
  command "export REDIS_URL=#redis://#{node[:drone][:master]}:6379/0""
end
