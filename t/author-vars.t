#!perl

use strict;
use warnings;

use Test2::Require::AuthorTesting;

use Test::More;

eval "use Test::Vars 0.015";

all_vars_ok();
