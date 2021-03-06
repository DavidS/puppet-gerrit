# = Class: gerrit
#
# This is the main gerrit class
#
#
# == Parameters
#
# Standard class parameters
# Define the general class behaviour and customizations
#
# [*gerrit_version*]
#   Version of gerrit to install
#
# [*gerrit_group*]
#   Name of group gerrit runs under
#
# [*gerrit_gid*]
#   GroupId of gerrit_group
#
# [*gerrit_user*]
#   Name of user gerrit runs under
#
# [*gerrit_groups*]
#   Additional user groups
#
# [*gerrit_uid*]
#   UserId of gerrit_user
#
# [*gerrit_home*]
#   Home-Dir of gerrit user
#
# [*gerrit_site_name*]
#   Name of gerrit review site directory
#
# Gerrit config variables:
#
# [*canonical_web_url*]
#   Canonical URL of the Gerrit review site, used on generated links
#
# [*sshd_listen_address*]
#   "<ip>:<port>" for the Gerrit SSH server to bind to
#
# [*httpd_listen_url*]
#   "<schema>://<ip>:<port>/<context>" for the Gerrit webapp to bind to
#
# [*my_class*]
# Name of a custom class to autoload to manage module's customizations
# If defined, apache class will automatically "include $my_class"
# Can be defined also by the (top scope) variable $apache_myclass
#
# == Author
#   Robert Einsle <robert@einsle.de>
#
class gerrit (
  $gerrit_version       = params_lookup('gerrit_version'),
  $gerrit_group         = params_lookup('gerrit_group'),
  $gerrit_gid           = params_lookup('gerrit_gid'),
  $gerrit_user          = params_lookup('gerrit_user'),
  $gerrit_groups        = params_lookup('gerrit_groups'),
  $gerrit_home          = params_lookup('gerrit_home'),
  $gerrit_uid           = params_lookup('gerrit_uid'),
  $gerrit_site_name     = params_lookup('gerrit_site_name'),
  $gerrit_database_type = params_lookup('gerrit_database_type'),
  $gerrit_java          = params_lookup('gerrit_java'),
  $gerrit_java_home     = params_lookup('gerrit_java_home'),
  $gerrit_heap_limit    = params_lookup('gerrit_heap_limit'),
  $canonical_web_url    = params_lookup('canonical_web_url'),
  $sshd_listen_address  = params_lookup('sshd_listen_address'),
  $httpd_listen_url     = params_lookup('httpd_listen_url'),
  $download_mirror      = 'http://gerrit-releases.storage.googleapis.com',
  $auth_type            = params_lookup('auth_type'),
  $gitweb		= false,
  $ldap_server          = undef,
  $ldap_username        = undef,
  $ldap_password        = undef,
  $ldap_account_base    = undef,
  $ldap_account_pattern = '(uid=${username})',
  $ldap_account_full_name = 'cn',
  $ldap_account_email_address = 'mail',
  $ldap_group_base      = undef,
  $ldap_group_pattern   = '(cn=${groupname})',
  $ldap_group_member_pattern = '(memberUid=${username})',
  $email_format         = '{0}@example.com',
  $my_class             = params_lookup('my_class'),
) inherits gerrit::params {

  $gerrit_war_file = "${gerrit_home}/gerrit-${gerrit_version}.war"

  #LDAP
  $use_ldap = $auth_type ? {
    /(LDAP|HTTP_LDAP|CLIENT_SSL_CERT_LDAP)/ => true,
    default            => false,
  }

  # Install required packages
  package {
  "gerrit_java":
    ensure => installed,
    name   => "${gerrit_java}",
  }

  if $gitweb {
    package { "gitweb":
      ensure => installed;
    }
  }

  # Crate Group for gerrit
  group { $gerrit_group:
    gid        => "$gerrit_gid", 
    ensure     => "present",
  }

  # Create User for gerrit-home
  user { $gerrit_user:
    comment    => "User for gerrit instance",
    home       => "$gerrit_home",
    shell      => "/bin/false",
    uid        => "$gerrit_uid",
    gid        => "$gerrit_gid",
    groups     => $gerrit_groups,
    ensure     => "present",
    managehome => true,
    require    => Group["$gerrit_group"]
  }

  # Correct gerrit_home uid & gid
  file { "${gerrit_home}":
    ensure     => directory,
    owner      => "${gerrit_uid}",
    group      => "${gerrit_gid}",
    require    => [
      User["${gerrit_user}"],
      Group["${gerrit_group}"],
    ]
  }

  if versioncmp($gerrit_version, '2.5') < 0 or versioncmp($gerrit_version, '2.5.2') > 0{
    $warfile = "gerrit-${gerrit_version}.war"
  } else {
    $warfile = "gerrit-full-${gerrit_version}.war"
  }

  # Funktion für Download eines Files per URL
  exec { "download_gerrit":
    command => "wget -q '${download_mirror}/${warfile}' -O ${gerrit_war_file}",
    path => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    creates => "${gerrit_war_file}",
    require => [ 
    Package["wget"],
    User["${gerrit_user}"],
    File[$gerrit_home]
    ],
    notify => Exec["delete_old_gerrit_sh"],
  }

  # Changes user / group of gerrit war
  file { "gerrit_war":
    path => "${gerrit_war_file}",
    owner => "${gerrit_user}",
    group => "${gerrit_group}",
    require => Exec["download_gerrit"],
  }

  exec { "delete_old_gerrit_sh":
    command => "service gerrit stop; rm -f ${gerrit_home}/${gerrit_site_name}/bin/gerrit.sh",
    path => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    require => [ 
    User["${gerrit_user}"],
    File[$gerrit_home]
    ],
    refreshonly => true,
    notify => Exec["init_gerrit"],
  }


  # ´exec' doesn't work with additional groups, so we resort to sudo
  $command = "sudo -u ${gerrit_user} java -jar ${gerrit_war_file} init -d $gerrit_home/${gerrit_site_name} --batch --no-auto-start"

  # Initialisation of gerrit site
  exec {
    "init_gerrit":
      cwd       => $gerrit_home,
      command   => $command,
      path => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      creates   => "${gerrit_home}/${gerrit_site_name}/bin/gerrit.sh",
      logoutput => on_failure,
      require   => [
        Package["${gerrit_java}"],
        File["gerrit_war"],
        ],
  }

  # some init script would be nice
  file {'/etc/default/gerritcodereview':
    ensure  => present,
    content => "GERRIT_SITE=${gerrit_home}/${gerrit_site_name}\n",
    owner   => $gerrit_user,
    group   => $gerrit_group,
    mode    => '0444',
    require => Exec['init_gerrit']
  }->
  file {'/etc/init.d/gerrit':
    ensure  => symlink,
    target  => "${gerrit_home}/${gerrit_site_name}/bin/gerrit.sh",
    require => Exec['init_gerrit']
  }

  # Manage Gerrit's configuration file (augeas would be more suitable).
  file { "${gerrit_home}/${gerrit_site_name}/etc/gerrit.config":
    content => template('gerrit/gerrit.config.erb'),
    owner   => $gerrit_user,
    group   => $gerrit_group,
    mode    => '0444',
    require => Exec['init_gerrit'],
    notify  => Service['gerrit']
  }

  service { 'gerrit':
    ensure    => running,
    enable    => true,
    hasstatus => false,
    pattern   => 'GerritCodeReview',
    require   => File['/etc/init.d/gerrit']
  }

  ### Include custom class if $my_class is set
  if $gerrit::my_class {
    include $gerrit::my_class
  }
}
