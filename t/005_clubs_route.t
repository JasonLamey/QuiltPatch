use strict;
use warnings;

use QP;
use Test::More tests => 3;
use Plack::Test;
use HTTP::Request::Common;

my $app = QP->to_app;
is( ref $app, 'CODE', 'Got app' );

my $test = Plack::Test->create($app);
my $res  = $test->request( GET '/clubs' );

ok( $res->is_success, '[GET /clubs] successful' );
like( $res->content, qr/Book Club/, '[GET /clubs] content correct.' );
