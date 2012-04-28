package App::Prove::Plugin::Distributed;

use strict;
use Getopt::Long;
use Carp;
use Test::More;
use IO::Socket::INET;
use Sys::Hostname;
use constant LOCK_EX => 2;
use constant LOCK_NB => 4;
use File::Spec;

use vars qw($VERSION @ISA);

my $error = '';

=head1 NAME

App::Prove::Plugin::Distributed - to distribute test job using client and server model.

=head1 VERSION

Version 0.03

=cut

$VERSION = '0.03';

=head3 C<load>

Load the plugin configuration.
It will setup all of the tests to be distributed through the 
L<TAP::Parser::SourceHandler::Worker> source handler class.

=cut

sub load {
    my ( $class, $p ) = @_;
    my @args = @{ $p->{args} };
    my $app  = $p->{app_prove};

    {
        local @ARGV = @args;

        push @ARGV, grep { /^--/ } @{ $app->{argv} };
        $app->{argv} = [ grep { !/^--/ } @{ $app->{argv} } ];
        Getopt::Long::Configure(qw(no_ignore_case bundling pass_through));

        # Don't add coderefs to GetOptions
        GetOptions(
            'manager=s'          => \$app->{manager},
            'distributed-type=s' => \$app->{distributed_type},
            'start-up=s'         => \$app->{start_up},
            'tear-down=s'        => \$app->{tear_down},
            'error-log=s'        => \$app->{error_log},
            'detach'             => \$app->{detach},
        ) or croak('Unable to continue');

#LSF: We pass the option to the source handler if the source handler want the options.
        unless ( $app->{manager} ) {
            my $source_handler_class =
                'TAP::Parser::SourceHandler::' 
              . 'Worker'
              . (
                $app->{distributed_type}
                ? '::' . $app->{distributed_type}
                : ''
              );
            eval "use $source_handler_class";
            unless ($@) {
                unless ( $source_handler_class->load_options( $app, \@ARGV ) ) {
                    croak('Unable to continue without needed worker options.');
                }
            }
        }

    }
    my $type = $app->{distributed_type};
    my $option_name = '--worker' . ( $type ? '-' . lc($type) : '' ) . '-option';
    if (   $app->{argv}->[0]
        && $app->{argv}->[0] =~ /$option_name=number_of_workers=(\d+)/ )
    {
        if ( $app->{jobs} ) {
            die
              "-j and $option_name=number_of_workers are mutually exclusive.\n";
        }
        else {
            $app->{jobs} = $1;
        }
    }
    else {
        $app->{jobs} ||= 1;
        unshift @{ $app->{argv} },
          "$option_name=number_of_workers=" . $app->{jobs};
    }

    for (qw(start_up tear_down error_log detach)) {
        if ( $app->{$_} ) {
            unshift @{ $app->{argv} }, "$option_name=$_=" . $app->{$_};
        }
    }

    unless ( $app->{manager} ) {

        #LSF: Set the iterator.
        $app->sources(
            [
                'Worker'
                  . (
                    $app->{distributed_type}
                    ? '::' . $app->{distributed_type}
                    : ''
                  )
            ]
        );
        return 1;
    }

    my $original_perl_5_lib = $ENV{PERL5LIB} || '';
    my @original_include = @INC;
    if ( $app->{includes} ) {
        my @includes = split /:/, $original_perl_5_lib;
        unshift @includes, @original_include;
        unshift @includes, @{ $app->{includes} };
        my %found;
        my @wanted;
        for my $include (@includes) {
            unless ( $found{$include} ) {
                push @wanted, $include;
            }
        }
        $ENV{PERL5LIB} = join ':', @wanted;
        @INC = @wanted;
    }

    #LSF: Start up.
    if ( $app->{start_up} ) {
        unless ( $class->_do( $app->{start_up} ) ) {
            die "start server error with error [$error].\n";
        }
    }

    while (1) {

        #LSF: The is the server to serve the test.
        $class->start_server(
            app  => $app,
            spec => $app->{manager},
            ( $app->{error_log} ? ( error_log => $app->{error_log} ) : () ),
            ( $app->{detach}    ? ( detach    => $app->{detach} )    : () ),

        );
    }

    #LSF: Anything below here might not be called.
    #LSF: Tear down
    if ( $app->{tear_down} ) {
        unless ( $class->_do( $app->{tear_down} ) ) {
            die "tear down error with error [$error].\n";
        }
    }
    $ENV{PER5LIB} = $original_perl_5_lib;
    @INC = @original_include;
    return 1;
}

=head3 C<start_server>

Start a server to serve the test.

Parameter is the contoller peer address.

=cut

sub start_server {
    my $class = shift;
    my %args  = @_;
    my ( $app, $spec, $error_log, $detach ) =
      @args{ 'app', 'spec', 'error_log', 'detach' };

    my $socket = IO::Socket::INET->new(
        PeerAddr => $spec,
        Proto    => 'tcp'
    );
    unless ($socket) {
        die "failed to connect to controller with address : $spec.\n";
    }

    #LSF: Waiting for job from controller.
    my $job_info = <$socket>;
    chomp($job_info);

    #LSF: Run job.
    my $pid = fork();
    if ($pid) {
        waitpid( $pid, 0 );
    }
    elsif ( $pid == 0 ) {

        #LSF: Intercept all output from Test::More. Output all of them at one.
        my $builder = Test::More->builder;
        $builder->output($socket);
        $builder->failure_output($socket);
        $builder->todo_output($socket);
        *STDERR = $socket;
        *STDOUT = $socket;
        if ($detach) {
            my $command = join ' ',
              ( $job_info,
                ( $app->{test_args} ? @{ $app->{test_args} } : () ) );
            {
                require TAP::Parser::Source;
                require TAP::Parser::SourceHandler::Worker;
                my $source = TAP::Parser::Source->new();
                $source->raw( \$job_info )->assemble_meta;
                my $vote =
                  TAP::Parser::SourceHandler::Worker->can_handle($source);
                if ( $vote >= 0.75 ) {
                    $command = $^X . ' ' . $command;
                }
                print $socket `$command`;
            }
            exit;
        }
        unless ( $class->_do( $job_info, $app->{test_args} ) ) {
            print $socket "$0\n$error\n\b";
            if ($error_log) {
                use IO::File;
                my $fh = IO::File->new( "$error_log", 'a+' );
                unless ( flock( $fh, LOCK_EX | LOCK_NB ) ) {
                    warn
"can't immediately write-lock the file ($!), blocking ...";
                    unless ( flock( $fh, LOCK_EX ) ) {
                        die "can't get write-lock on numfile: $!";
                    }
                }
                my $server_spec = (
                    $socket->sockhost eq '0.0.0.0'
                    ? hostname
                    : $socket->sockhost
                  )
                  . ':'
                  . $socket->sockport;
                print $fh
"<< START $job_info >>\nSERVER: $server_spec\nPID: $$\nERROR: $error\n<< END $job_info >>\n\b";
                close $fh;
            }
        }
        exit;
    }
    else {
        die "should not get here.\n";
    }
    $socket->close();
    return 1;
}

sub _do {
    my $proto    = shift;
    my $job_info = shift;
    my $args     = shift;

    my $cwd = File::Spec->rel2abs('.');

    #LSF: The code from here to exit is from  L<FCGI::Daemon> module.
    local *CORE::GLOBAL::exit = sub { die 'notr3a11yeXit' };
    local $0 = $job_info;    #fixes FindBin (in English $0 means $PROGRAM_NAME)
    no strict;               # default for Perl5
    {

        package main;
        local @ARGV = $args ? @$args : ();
        do $0;               # do $0; could be enough for strict scripts
        chdir($cwd);

        if ($EVAL_ERROR) {
            $EVAL_ERROR =~ s{\n+\z}{};
            unless ( $EVAL_ERROR =~ m{^notr3a11yeXit} ) {
                $error = $EVAL_ERROR;
                return;
            }
        }
        elsif ($@) {
            $error = $@;
            return;
        }
    }
    return 1;
}

1;

__END__

##############################################################################
