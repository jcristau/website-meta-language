#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw/ GetOptions /;

use File::Glob;

use File::Basename qw(dirname);
use File::Spec;

use Cwd ();
use IO::All qw / io /;

use File::Path qw / rmtree /;

my $is_interactive;

GetOptions(
    'interactive!' => \$is_interactive,
);

my $script_dir = File::Spec->rel2abs(dirname(__FILE__));

my $myprefix = Cwd::getcwd() . "/tests/installation";

my $build_dir = "FOO";

if (! -e $myprefix)
{
    rmtree ([$build_dir]);
    if (system("mkdir $build_dir && cd $build_dir && cmake -DCMAKE_INSTALL_PREFIX=$myprefix $script_dir/.. && make && make install"))
    {
        rmtree ([$myprefix]);
        die "cmake Failed";
    }
}

my $P5L = $ENV{PERL5LIB} ? $ENV{PERL5LIB}.':' : ':';
$ENV{PERL5LIB} = "$myprefix/lib/perl5:$P5L$script_dir";
$ENV{QUAD_PRES_NO_HOME_LIB} = 1;
$ENV{PATH} = "$myprefix/bin:$ENV{PATH}";
$ENV{WML} = "$myprefix/bin/wml -q -W1-N";
$ENV{LANG} = $ENV{LC_ALL} = 'C';

chdir($script_dir);

if ($is_interactive)
{
    system("bash");
}
else
{
    exec {'prove' } ('prove', '-v', glob('t/{02,03,05,06,07,08,09,10,des,std}-*.t'));
}

=head1 COPYRIGHT & LICENSE

Copyright 2014 by Shlomi Fish

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut
