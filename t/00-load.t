#!/usr/bin/env perl

use lib 'lib';
use Test::Most;

use Data::FauxSON ();

pass "We were able to lood our primary modules";

diag "Testing Data::FauxSON Data::FauxSON:VERSION, Perl $], $^X";

done_testing;
