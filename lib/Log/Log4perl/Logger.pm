##################################################
package Log::Log4perl::Logger;
##################################################

use 5.006;
use strict;
use warnings;

use Log::Log4perl::Level;
use Log::Log4perl::Layout;
use Log::Log4perl::Appender;
use Log::Dispatch;
use Carp;

    # Initialization
our $ROOT_LOGGER;
our $LOGGERS_BY_NAME;
our %LAYOUT_BY_APPENDER;
our %APPENDER_BY_NAME = ();

__PACKAGE__->reset();

##################################################
sub init {
##################################################
    my($class) = @_;

    return $ROOT_LOGGER;
}

##################################################
sub reset {
##################################################
    our $ROOT_LOGGER        = __PACKAGE__->_new("", $DEBUG);
    our $LOGGERS_BY_NAME    = {};
}

##################################################
sub _new {
##################################################
    my($class, $category, $level) = @_;

    die "usage: __PACKAGE__->_new(category)" unless
        defined $category;
    
    $category  =~ s/::/./g;

       # Have we created it previously?
    if(exists $LOGGERS_BY_NAME->{$category}) {
        return $LOGGERS_BY_NAME->{$category};
    }

    my $self  = {
        logger_class  => $category,
        num_appenders => 0,
        additivity    => 1,
        level         => $level,
        dispatcher    => Log::Dispatch->new(),
        layout        => undef,
                };

        # Save it in global structure
    $LOGGERS_BY_NAME->{$category} = $self;

    bless $self, $class;

    return $self;
}

##################################################
sub parent_string {
##################################################
    my($string) = @_;

    if($string eq "") {
        return undef; # root doesn't have a parent.
    }

    my @components = split /\./, $string;
    
    if(@components == 1) {
        return "";
    }

    pop @components;

    return join('.', @components);
}

##################################################
sub level {
##################################################
    my($self, $level) = @_;

        # 'Set' function
    if(defined $level) {
        croak "invalid level '$level'" 
                unless Log::Log4perl::Level::is_valid($level);
        $self->{level} = $level;   
        return $level;
    }

        # 'Get' function
    if(defined $self->{level}) {
        return $self->{level};
    }

    for(my $logger = $self; $logger; $logger = parent_logger($logger)) {

        # Does the current logger have the level defined?

        if($logger->{logger_class} eq "") {
            # It's the root logger
            return $ROOT_LOGGER->{level};
        }
            
        if(defined $LOGGERS_BY_NAME->{$logger->{logger_class}}->{level}) {
            return $LOGGERS_BY_NAME->{$logger->{logger_class}}->{level};
        }
    }

    # We should never get here because at least the root logger should
    # have a level defined
    die "We should never get here.";
}

##################################################
sub parent_logger {
# Get the parent of the current logger or undef
##################################################
    my($logger) = @_;

        # Is it the root logger?
    if($logger->{logger_class} eq "") {
        # Root has no parent
        return undef;
    }

        # Go to the next defined (!) parent
    my $parent_class = parent_string($logger->{logger_class});

    while($parent_class ne "" and
          ! exists $LOGGERS_BY_NAME->{$parent_class}) {
        $parent_class = parent_string($parent_class);
        $logger =  $LOGGERS_BY_NAME->{$parent_class};
    }

    if($parent_class eq "") {
        $logger = $ROOT_LOGGER;
    } else {
        $logger = $LOGGERS_BY_NAME->{$parent_class};
    }

    return $logger;
}

##################################################
sub get_root_logger {
##################################################
    my($class) = @_;
    return $ROOT_LOGGER;    
}

##################################################
sub additivity {
##################################################
    my($self, $onoff) = @_;

    if(defined $onoff) {
        $self->{additivity} = $onoff;
    }

    return $self->{additivity};
}

##################################################
sub get_logger {
##################################################
    my($class, $logger_class) = @_;

    unless(defined $ROOT_LOGGER) {
        die "Logger not initialized. No previous call to init()?";
    }

    return $ROOT_LOGGER if $logger_class eq "";

    my $logger = $class->_new($logger_class);
    return $logger;
}

##################################################
sub add_appender {
##################################################
    my($self, $appender) = @_;

    my $appender_name = $appender->name();

    $self->{num_appenders}++;

    unless (grep{$_ eq $appender_name} @{$self->{appender_names}}){
        $self->{appender_names} = [sort @{$self->{appender_names}}, 
                                        $appender_name];
    }

    $APPENDER_BY_NAME{$appender_name} = $appender;

    $self->{dispatcher}->add($appender);    
}

##################################################
sub has_appenders {
##################################################
    my($self) = @_;

    return $self->{num_appenders};
}

##################################################
sub log {
##################################################
    my($self, $level, $priority, @message) = @_;

    my %seen;

    my $message = join '', @message;

    my $category = $self->{logger_class};

    if($priority <= $self->level()) {
        # Call the dispatchers up the hierarchy
        for(my $logger = $self; $logger; $logger = parent_logger($logger)) {

               # Only format the message if there's going to be an appender.
            next unless $logger->has_appenders();

            foreach my $appender_name (@{$logger->{appender_names}}){

                    #only one message per appender, please
                next if $seen{$appender_name} ++;

                my $appender = $APPENDER_BY_NAME{$appender_name};

                my $rendered_msg;

                #is this proper behavior if no layout defined?  !!!
                if ($appender->layout()) {
                    $rendered_msg = $appender->layout()->render(
                            $logger, $message, $category,
                            $level, 2);
                }else{
                    # Accoding to 
                    # http://jakarta.apache.org/log4j/docs/api/org/...
                    # apache/log4j/SimpleLayout.html this is the default layout
                    # TODO: Replace with SimpleFormat
                    $rendered_msg = "$level - $message";
                }

                    # Dispatch the (formatted) message
                $logger->{dispatcher}->log_to(
                    name    => $appender_name,
                    level   => lc(Log::Log4perl::Level::to_string($priority)),
                    message => $rendered_msg,
                    );
            }
            last unless $logger->{additivity};
        }
    }
}

##################################################
sub debug { &log($_[0], 'DEBUG', $DEBUG, @_[1,]); }
sub info  { &log($_[0], 'INFO',  $INFO,  @_[1,]); }
sub warn  { &log($_[0], 'WARN',  $WARN,  @_[1,]); }
sub error { &log($_[0], 'ERROR', $ERROR, @_[1,]); }
sub fatal { &log($_[0], 'FATAL', $FATAL, @_[1,]); }

sub is_debug { return $_[0]->level() >= $DEBUG; }
sub is_info  { return $_[0]->level() >= $INFO; }
sub is_warn  { return $_[0]->level() >= $WARN; }
sub is_error { return $_[0]->level() >= $ERROR; }
sub is_fatal { return $_[0]->level() >= $FATAL; }
##################################################

1;

__END__

=head1 NAME

Log::Log4perl::Logger - Main Logger

=head1 SYNOPSIS

  use Log::Log4perl::Logger;

  my $log =  Log::Log4perl::Logger();
  $log->debug("Debug Message");

=head1 DESCRIPTION

=head1 SEE ALSO

=head1 AUTHOR

Mike Schilli, E<lt>m@perlmeister.comE<gt>

=cut
