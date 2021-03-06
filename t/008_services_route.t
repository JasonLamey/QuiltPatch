use strict;
use warnings;

use QP;
use Test::More tests => 3;
use Plack::Test;
use HTTP::Request::Common;

my $app = QP->to_app;
is( ref $app, 'CODE', 'Got app' );

my $test = Plack::Test->create($app);
my $res  = $test->request( GET '/services' );

ok( $res->is_success, '[GET /services] successful' );
like( $res->content, qr/Sewing Machine Service Note/, '[GET /services] content correct.' );
