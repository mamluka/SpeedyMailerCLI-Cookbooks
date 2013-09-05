maintainer	"Iain Ballard"

recipe "mono", "Installs Mono runtime and development environment"

%w{ debian ubuntu }.each do |os|
  supports os
end

