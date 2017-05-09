package QP;
use Dancer2;

our $VERSION = '2.0';

get '/' => sub {
    template 'index';
};

true;
