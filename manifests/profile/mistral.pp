# == Class: st2::profile::mistral
#
# This class installs OpenStack Mistral, a workflow engine that integrates with
# StackStorm. Has the option to manage a companion MySQL Server
#
# === Parameters
#  [*manage_mysql*]        - Flag used to have MySQL installed/managed via this profile (Default: false)
#  [*git_branch*]          - Tagged branch of Mistral to download/install
#  [*db_root_password*]    - Root MySQL Password
#  [*db_mistral_password*] - Mistral user MySQL Password
#  [*db_server*]           - Server hosting Mistral DB
#  [*db_database*]         - Database storing Mistral Data
#  [*db_max_pool_size*]    - Max DB Pool size for Mistral Connections
#  [*db_max_overflow*]     - Max DB overload for Mistral Connections
#  [*db_pool_recycle*]     - DB Pool recycle time
#
# === Examples
#
#  include st2::profile::mistral
#
#  class { '::st2::profile::mistral':
#    manage_mysql        => true,
#    db_root_password    => 'datsupersecretpassword',
#    db_mistral_password => 'mistralpassword',
#  }
#
class st2::profile::mistral(
  $manage_mysql        = false,
  $git_branch          = $::st2::mistral_git_branch,
  $db_root_password    = 'StackStorm',
  $db_mistral_password = 'StackStorm',
  $db_server           = 'localhost',
  $db_database         = 'mistral',
  $db_max_pool_size    = '100',
  $db_max_overflow     = '400',
  $db_pool_recycle     = '3600',
) inherits st2 {
  include '::st2::dependencies'

  # This needs a bit more modeling... need to understand
  # what current mistral code ships with st2 - jdf

  ### Dependencies ###
  if !defined(Class['::mysql::bindings']) {
    class { '::mysql::bindings':
      client_dev => true,
      daemon_dev => true,
    }
  }

  ### Mistral Downloads ###
  if !defined(File['/opt/openstack']) {
    file { '/opt/openstack':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
  }

  file { [ '/etc/mistral', '/etc/mistral/actions']:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  vcsrepo { '/opt/openstack/mistral':
    ensure   => present,
    source   => 'https://github.com/StackStorm/mistral.git',
    revision => $git_branch,
    provider => 'git',
    require  => File['/opt/openstack'],
    before   => [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
    ],
  }

  vcsrepo { '/etc/mistral/actions/st2mistral':
    ensure => present,
    source => 'https://github.com/StackStorm/st2mistral.git',
    revision => $git_branch,
    provider => 'git',
    require  => File['/etc/mistral/actions'],
    before   => [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
    ],
  }
  ### END Mistral Downloads ###

  ### Bootstrap Python ###
  python::virtualenv { '/opt/openstack/mistral':
    ensure       => present,
    version      => 'system',
    systempkgs   => false,
    venv_dir     => '/opt/openstack/mistral/.venv',
    cwd          => '/opt/openstack/mistral',
    require      => Vcsrepo['/opt/openstack/mistral'],
    notify       => [
      Exec['setup mistral', 'setup st2mistral plugin'],
      Exec['python_requirementsmistral'],
    ],
    before       => File['/etc/mistral/database_setup.lock'],
  }

  # Not using virtualenv requirements attribute because oslo has bad wheel, and fails
  python::requirements { 'mistral':
    requirements => '/opt/openstack/mistral/requirements.txt',
    virtualenv   => '/opt/openstack/mistral/.venv',
  }

  python::pip { 'mysql-python':
    ensure     => present,
    virtualenv => '/opt/openstack/mistral/.venv',
    require    => Vcsrepo['/opt/openstack/mistral'],
    before   => [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
      Exec['setup mistral database'],
    ],
  }

  python::pip { 'python-mistralclient':
    ensure => present,
    url    => "git+https://github.com/StackStorm/python-mistralclient.git@${git_branch}",
    before   => [
      Exec['setup mistral'],
      Exec['setup st2mistral plugin'],
      Exec['setup mistral database'],
    ],
  }
  ### END Bootstrap Python ###

  ### Bootstrap Mistral ###
  exec { 'setup mistral':
    command     => 'python setup.py develop',
    cwd         => '/opt/openstack/mistral',
    path        => [
      '/opt/openstack/mistral/.venv/bin',
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/usr/sbin',
      '/bin',
      '/sbin',
    ],
    refreshonly => true,
  }

  exec { 'setup st2mistral plugin':
    command     => 'python setup.py develop',
    cwd         => '/etc/mistral/actions/st2mistral',
    path        => [
      '/opt/openstack/mistral/.venv/bin',
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/usr/sbin',
      '/bin',
      '/sbin',
    ],
    refreshonly => true,
  }
  ### END Bootstrap Mistral ###


  ### Mistral Config Modeling ###
  ini_setting { 'connection config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'connection',
    value   => "mysql://mistral:${db_mistral_password}@${db_server}/${db_database}",
  }
  ini_setting { 'connection pool config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'max_pool_size',
    value   => $db_max_pool_size,
  }
  ini_setting { 'connection overflow config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'max_overflow',
    value   => $db_max_overflow,
  }
  ini_setting { 'db pool recycle config':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'database',
    setting => 'pool_recycle',
    value   => $db_pool_recycle,
  }

  ini_setting { 'pecan settings':
    ensure  => present,
    path    => '/etc/mistral/mistral.conf',
    section => 'pecan',
    setting => 'auth_enable',
    value   => 'false',
  }


  File<| tag == 'mistral' |> -> Ini_setting <| tag == 'mistral' |> -> Exec['setup mistral database']
  ### End Mistral Config Modeling ###

  ### Setup Mistral Database ###
  if $manage_mysql {
    class { '::mysql::server':
      root_password => $db_root_password,
    }
  }

  mysql::db { 'mistral':
    user     => 'mistral',
    password => $db_mistral_password,
    before   => Exec['setup mistral database'],
  }

  file { '/etc/mistral/database_setup.lock':
    ensure => file,
    content => 'This file is the lock file that prevents Puppet from attempting to setup the database again. Delete this file if it needs to be re-run',
    notify  => Exec['setup mistral database'],
  }

  exec { 'setup mistral database':
    command     => 'python ./tools/sync_db.py --config-file /etc/mistral/mistral.conf',
    refreshonly => true,
    cwd         => '/opt/openstack/mistral',
    path        => [
      '/opt/openstack/mistral/.venv/bin',
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/usr/sbin',
      '/bin',
      '/sbin',
    ],
    require     => [
      Vcsrepo['/opt/openstack/mistral'],
    ],
  }

  ### Mistral Init Scripts ###
  case $::osfamily {
    'Debian': {
      # A bit sloppy, but this only covers Ubuntu right now. Fix this
      file { '/etc/init/mistral.conf':
        ensure => file,
        owner  => 'root',
        group  => 'root',
        mode   => '0444',
        source => 'puppet:///modules/st2/etc/init/mistral.conf',
      }
    }
    'RedHat': {
      file { '/etc/systemd/system/mistral.service':
        ensure => file,
        owner  => 'root',
        group  => 'root',
        mode   => '0444',
        source => 'puppet:///modules/st2/etc/systemd/system/mistral.service',
      }
    }
  }
  ### END Mistral Init Scripts ###
}
