package Sys::Syslog;
require 5.000;
require Exporter;
use Carp;

@ISA = qw(Exporter);
@EXPORT = qw(openlog closelog setlogmask syslog);

use Socket;
use Sys::Hostname;

#
# syslog.pl
#
# $Log:	syslog.pl,v $
# 
# tom christiansen <tchrist@convex.com>
# modified to use sockets by Larry Wall <lwall@jpl-devvax.jpl.nasa.gov>
# NOTE: openlog now takes three arguments, just like openlog(3)
#
# call syslog() with a string priority and a list of printf() args
# like syslog(3)
#
#  usage: use Syslog;
#
#  then (put these all in a script to test function)
#		
#	openlog($program,'cons,pid','user');
#	syslog('info','this is another test');
#	syslog('mail|warning','this is a better test: %d', time);
#	closelog();
#	
#	syslog('debug','this is the last test');
#	openlog("$program $$",'ndelay','user');
#	syslog('notice','fooprogram: this is really done');
#
#	$! = 55;
#	syslog('info','problem was %m'); # %m == $! in syslog(3)

$host = hostname() unless $host;	# set $Syslog::host to change

require 'syslog.ph';

$maskpri = &LOG_UPTO(&LOG_DEBUG);

sub openlog {
    ($ident, $logopt, $facility) = @_;  # package vars
    $lo_pid = $logopt =~ /\bpid\b/;
    $lo_ndelay = $logopt =~ /\bndelay\b/;
    $lo_cons = $logopt =~ /\bcons\b/;
    $lo_nowait = $logopt =~ /\bnowait\b/;
    &connect if $lo_ndelay;
} 

sub closelog {
    $facility = $ident = '';
    &disconnect;
} 

sub setlogmask {
    local($oldmask) = $maskpri;
    $maskpri = shift;
    $oldmask;
}
 
sub syslog {
    local($priority) = shift;
    local($mask) = shift;
    local($message, $whoami);
    local(@words, $num, $numpri, $numfac, $sum);
    local($facility) = $facility;	# may need to change temporarily.

    croak "syslog: expected both priority and mask" unless $mask && $priority;

    @words = split(/\W+/, $priority, 2);# Allow "level" or "level|facility".
    undef $numpri;
    undef $numfac;
    foreach (@words) {
	$num = &xlate($_);		# Translate word to number.
	if (/^kern$/ || $num < 0) {
	    croak "syslog: invalid level/facility: $_";
	}
	elsif ($num <= &LOG_PRIMASK) {
	    croak "syslog: too many levels given: $_" if defined($numpri);
	    $numpri = $num;
	    return 0 unless &LOG_MASK($numpri) & $maskpri;
	}
	else {
	    croak "syslog: too many facilities given: $_" if defined($numfac);
	    $facility = $_;
	    $numfac = $num;
	}
    }

    croak "syslog: level must be given" unless defined($numpri);

    if (!defined($numfac)) {	# Facility not specified in this call.
	$facility = 'user' unless $facility;
	$numfac = &xlate($facility);
    }

    &connect unless $connected;

    $whoami = $ident;

    if (!$ident && $mask =~ /^(\S.*):\s?(.*)/) {
	$whoami = $1;
	$mask = $2;
    } 

    unless ($whoami) {
	($whoami = getlogin) ||
	    ($whoami = getpwuid($<)) ||
		($whoami = 'syslog');
    }

    $whoami .= "[$$]" if $lo_pid;

    $mask =~ s/%m/$!/g;
    $mask .= "\n" unless $mask =~ /\n$/;
    $message = sprintf ($mask, @_);

    $sum = $numpri + $numfac;
    unless (send(SYSLOG,"<$sum>$whoami: $message",0)) {
	if ($lo_cons) {
	    if ($pid = fork) {
		unless ($lo_nowait) {
		    $died = waitpid($pid, 0);
		}
	    }
	    else {
		open(CONS,">/dev/console");
		print CONS "<$facility.$priority>$whoami: $message\r";
		exit if defined $pid;		# if fork failed, we're parent
		close CONS;
	    }
	}
    }
}

sub xlate {
    local($name) = @_;
    $name =~ y/a-z/A-Z/;
    $name = "LOG_$name" unless $name =~ /^LOG_/;
    $name = "Sys::Syslog::$name";
    eval(&$name) || -1;
}

sub connect {
    my $udp = getprotobyname('udp');
    my $syslog = getservbyname('syslog','udp');
    my $this = sockaddr_in($syslog, INADDR_ANY);
    my $that = sockaddr_in($syslog, inet_aton($host) || croak "Can't lookup $host");
    socket(SYSLOG,AF_INET,SOCK_DGRAM,$udp) 	     || croak "socket: $!";
    connect(SYSLOG,$that) 			     || croak "connect: $!";
    local($old) = select(SYSLOG); $| = 1; select($old);
    $connected = 1;
}

sub disconnect {
    close SYSLOG;
    $connected = 0;
}

1;

