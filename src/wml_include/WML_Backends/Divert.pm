package WML_Backends::Divert;
##
##  divert -- Diversion Filter
##  Copyright (c) 1997-2001 Ralf S. Engelschall, All Rights Reserved.
##  Copyright (c) 1999-2001 Denis Barbier, All Rights Reserved.
##

use strict;
use warnings;

BEGIN { $^W = 0; } # get rid of nasty warnings

use lib '@INSTALLPRIVLIB@';
use lib '@INSTALLARCHLIB@';

use Getopt::Long 2.13;
use IO::Handle 1.15;

sub usage {
    print STDERR <<'EOF';
Usage: divert [options] [file]

Options:
  -o, --outputfile=<file>  set output file instead of stdout
  -q, --quiet              quiet mode (no warnings)
  -v, --verbose            verbose mode
EOF

    exit(1);
}

sub verbose {
    my ($self, $str) = @_;
    if ($self->_opt_v) {
        print STDERR "** Divert:Verbose: $str\n";
    }
}

sub error {
    my ($self, $str) = @_;
    print STDERR "** Divert:Error: $str\n";
    exit(1);
}

sub warning {
    my ($self, $filename, $line, $str) = @_;
    if (not $self->_opt_q) {
        print STDERR "** Divert:Warning: ${filename}:$line: $str\n";
    }
}

use List::Util qw(first min);
use List::MoreUtils qw(any);

use Class::XSAccessor
(
    constructor => '_cons',
    accessors => +{
        map { $_ => $_ }
        qw( _BUFFER _expand_stack _filename _in_fh _line _loc_stack _location
        _opt_o _opt_q _opt_v _OVRWRITE )
    },
);

sub new
{
    my $self = shift->_cons;

    $self->_init;

    return $self;
}

sub _init
{
    my ($self) = @_;

    {
        my $opt_v = 0;
        my $opt_q = 0;
        my $opt_o = '-';
        local $Getopt::Long::bundling = 1;
        local $Getopt::Long::getopt_compat = 0;
        if (not Getopt::Long::GetOptions(
                "v|verbose" => \$opt_v,
                "q|quiet" => \$opt_q,
                "o|outputfile=s" => \$opt_o,
            )
        )
        {
            usage();
        }
        $self->_opt_v($opt_v);
        $self->_opt_q($opt_q);
        $self->_opt_o($opt_o);
    }

    #
    #   open input file and read into buffer
    #
    {
        my $in;

        if ((@ARGV == 1 and $ARGV[0] eq '-') or !@ARGV) {
            $in = IO::Handle->new;
            $self->_filename ('STDIN');
            $in->fdopen(fileno(STDIN), "r") || $self->error("cannot load STDIN: $!");
        }
        elsif (@ARGV == 1) {
            open $in, '<', $self->_filename($ARGV[0])
                or $self->error("cannot load @{[$self->_filename]}: $!");
        }
        else {
            usage();
        }
        $self->_in_fh($in);
    }

    ##
    ##   Pass 1: Parse the input data into disjunct location buffers
    ##           Each location buffer contains plain text blocks and
    ##           location pointers.
    ##

    $self->_location('main');                    # currently active location
    $self->_loc_stack(['null']); # stack of remembered locations
    $self->_BUFFER(+{'null' => [], 'main' => [], }); # the location buffers
    $self->_OVRWRITE(+{});                            # the overwrite flags
    $self->_line(0);
    $self->_expand_stack([]);

    return;
}

sub _run {
    my ($self) = @_;

    while (defined(my $remain = $self->_in_fh->getline)) {
        $self->_line($self->_line + 1);
        while (length $remain > 0) {

            if (my $m1 = (($remain =~ s|^<<([a-zA-Z][a-zA-Z0-9_]*)>>||)
                    ? $1 : ($remain =~ s|^{#([a-zA-Z][a-zA-Z0-9_]*)#}||) ? $1 : undef))
            {
                ##
                ##  Tag: dump location
                ##

                #   initialize new location buffer
                $self->_BUFFER->{$m1} = [] if (not exists($self->_BUFFER->{$m1}));

                #   insert location pointer into current location
                if ($self->_BUFFER->{$self->_location} == $self->_BUFFER->{$m1}) {
                    $self->warning($self->_filename, $self->_line, "self-reference of location ``". $self->_location . "'' - ignoring");
                }
                else {
                    push(@{$self->_BUFFER->{$self->_location}}, $self->_BUFFER->{$m1});
                }
            }
            elsif ( $m1 = (($remain =~ s|^\.\.(\!?[a-zA-Z][a-zA-Z0-9_]*\!?)>>||) ? $1 :
                    ($remain =~ s|^{#(\!?[a-zA-Z][a-zA-Z0-9_]*\!?)#:||) ? $1 : undef))
            {
                ##
                ##  Tag: enter location
                ##

                #   remember old location on stack
                push(@{ $self->_loc_stack }, $self->_location);

                #   determine location and optional
                #   qualifies, then enter this location
                $self->_location($m1);
                my $rewind_now  = 0;
                my $rewind_next = 0;

                if (my ($new_loc) = $self->_location =~ m|^\!(.*)$|) {
                    #   location should be rewinded now
                    $self->_location($new_loc);
                    $rewind_now = 1;
                }

                if (my ($new_loc) = $self->_location =~ m|^(.*)\!$|) {
                    #   location should be rewinded next time
                    $self->_location($new_loc);
                    $rewind_next = 1;
                }

                #   initialize location buffer
                $self->_BUFFER->{$self->_location} = [] if (not exists($self->_BUFFER->{$self->_location}));

                #   is a "rewind now" forced by a "rewind next" from last time?
                if ($self->_OVRWRITE->{$self->_location}) {
                    $rewind_now = 1;
                    $self->_OVRWRITE->{$self->_location} = 0;
                }

                #   remember a "rewind next" for next time
                $self->_OVRWRITE->{$self->_location} = 1 if ($rewind_next);

                #   execute a "rewind now" by clearing the location buffer
                if ($rewind_now == 1) {
                    while ($#{$self->_BUFFER->{$self->_location}} > -1) {
                        shift(@{$self->_BUFFER->{$self->_location}});
                    }
                }
            }
            elsif (   $remain =~ s|^<<([a-zA-Z][a-zA-Z0-9_]*)?\.\.||
                    or $remain =~ s|^:#([a-zA-Z][a-zA-Z0-9_]*)?#}||) {
                ##
                ##  Tag: leave location
                ##

                if (! @{ $self->_loc_stack } ) {
                    $self->warning($self->_filename, $self->_line, "already in ``null'' location -- ignoring leave");
                }
                else {
                    my $loc = ($1 // '');
                    if ($loc eq 'null') {
                        $self->warning($self->_filename, $self->_line, "cannot leave ``null'' location -- ignoring named leave");
                    }
                    elsif ($loc ne '' and $loc ne $self->_location) {
                        #   leave the named location and all locations
                        #   on the stack above it.
                        my $n = -1;
                        for (my $i = $#{$self->_loc_stack}; $i >= 0; $i--) {
                            if ($self->_loc_stack->[$i] eq $loc) {
                                $n = $i;
                                last;
                            }
                        }
                        if ($n == -1) {
                            $self->warning($self->_filename, $self->_line, "no such currently entered location ``$loc'' -- ignoring named leave");
                        }
                        else {
                            splice(@{ $self->_loc_stack }, $n);
                            $self->_location( pop(@{ $self->_loc_stack }) );
                        }
                    }
                    else {
                        #   leave just the current location
                        $self->_location(pop(@{ $self->_loc_stack }));
                    }
                }
            }
            else {
                ##
                ##  Plain text
                ##

                #   calculate the minimum amount of plain characters we can skip
                my $l = length($remain);
                my $i1 = index($remain, '<<');  $i1 = $l if $i1 == -1;
                #   Skip ../ which is often used in URLs
                my $i2 = -1;
                do {
                    $i2 = index($remain, '..', $i2+1);
                } while ($i2 > -1 and $i2+2 < $l and substr($remain, $i2+2, 1) eq '/');
                $i2 = $l if $i2 == -1;

                my $i3 = index($remain, '{#');  $i3 = $l if $i3 == -1; #}
                my $i4 = index($remain, ':#');  $i4 = $l if $i4 == -1;

                my $i = min($i1, $i2, $i3, $i4);

                #   skip at least 2 characters if we are sitting
                #   on just a "<<", "..", "{#" or ":#"
                $i = 1 if ($i == 0);

                #   append plain text to remembered data and adjust $remain
                #   variable
                if ($i == $l) {
                    push(@{$self->_BUFFER->{$self->_location}}, $remain);
                    $remain = '';
                } else {
                    #   substr with 4 arguments was introduced in perl 5.005
                    push(@{$self->_BUFFER->{$self->_location}}, substr($remain, 0, $i));
                    substr($remain, 0, $i) = '';
                }
            }
        }
    }
    $self->_in_fh->close();
}

sub ExpandDiversion {
    my ($self, $loc) = @_;

    #   check for recursion by making sure
    #   the current location has not already been seen.
    if (any { $_ == $loc } @{$self->_expand_stack}) {
        #   find name of location via location pointer
        #   for human readable warning message
        my $name = (
            (first { $self->_BUFFER->{$_} == $loc } keys(%{$self->_BUFFER}))
                //
                'unknown'
        );
        $self->warning($self->_filename, $self->_line, "recursion through location ``$name'' - break");
        return '';
    }

    #   ok, location still not seen,
    #   but remember it for recursive calls.
    push(@{$self->_expand_stack}, $loc);

    #   recursively expand the location
    #   by stepping through its list elements
    my $data = '';
    foreach my $el (@{$loc}) {
        $data .= ref($el) ? $self->ExpandDiversion($el) : $el;
    }

    #   we can remove the location from
    #   the stack because we are back from recursive calls.
    pop(@{ $self->_expand_stack });

    #   return expanded buffer
    return $data;
}

sub calc_result
{
    my ($self) = @_;

    $self->_run;

    ##
    ##   Pass 2: Recursively expand the location structure
    ##           by starting from the main location buffer
    ##
    return $self->ExpandDiversion(
        $self->_BUFFER->{'main'}
    );
}

1;
