use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'App::Prove::Plugin::Distributed',
    VERSION_FROM      => 'lib/App/Prove/Plugin/Distributed.pm', # finds $VERSION
    PREREQ_PM         => {
			    'App::Prove' => 3.23,
			    'Carp' => 0,
			    'Cwd' => 0,
			    'Getopt::Long' => 0,
			    'IO::Select' => 0,
			    'IO::Socket::INET' => 0,
			    'Sys::Hostname' => 0,
			    'Test::More' => 0,
                         }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/App/Prove/Plugin/Distributed.pm', # retrieve abstract from module
       AUTHOR         => 'Shin Leong <lsf@cpan.org>') : ()),
);
