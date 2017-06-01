requires "Dancer2" => "0.203001";

recommends "YAML"             => "0";
recommends "URL::Encode::XS"  => "0";
recommends "CGI::Deurl::XS"   => "0";
recommends "HTTP::Parser::XS" => "0";

requires   "Dancer2"                  => "0.205000";
requires   "Dancer2::Plugin::Flash"   => "0.03";
requires   "DBI"                      => "1.636";
requires   "DBD::mysql"               => "4.042";
requires   "DBIx::Class"              => "0.082840";
requires   "Const::Fast"              => "0.014";
requires   "DateTime"                 => "1.42";
requires   "URI::Escape::JavaScript"  => "0.04";
requires   "Date::Calc"               => "6.4";
requires   "Date::Manip"              => "6.58";
requires   "Emailesque"               => "1.26";

on "test" => sub {
    requires "Test::More"            => "0";
    requires "HTTP::Request::Common" => "0";
};
